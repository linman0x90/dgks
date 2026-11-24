-- dG KillShot kill and death history
--
-- Two databases:
--   * Personal history (dgksDB.char.history): every kill, death, duel win and duel loss of this
--     character. Kept forever.
--   * Guild history (dgksDB.global.history.guilds[guildKey]): the records of every guild member
--     running dgks, shared over the guild addon channel. Pruned after a configurable number of days.
--
-- Records are written once by the character they happened to (the "author") and never changed, so
-- copies can never conflict. Each author writes into a "stream" ("Name-Realm#epoch"); every record
-- in a stream gets the next sequence number. The epoch is the time the stream was created, so a
-- character whose saved variables were wiped starts a new stream instead of reusing old numbers.
--
-- Sync (addon prefix "dgksH"):
--   R  (GUILD)    a new record, sent by its author right after it happens
--   S  (GUILD)    summary: for every stream, the highest sequence number we hold completely.
--                 Sent at login and every SUMMARY_INTERVAL; postponed when someone else just sent
--                 an identical summary.
--   Q  (WHISPER)  request to a peer whose summary shows newer records: "send stream X after #n"
--   B  (WHISPER)  a batch of records for one stream, in answer to Q
--   E  (WHISPER)  end of an answer: "you now have everything in stream X up to #n". Records older
--                 than the sender's retention are not sent, so this is what lets the receiver's
--                 head move past pruned records.
--
-- A stream's head means "we hold every non-expired record up to this number". Heads only move up
-- by contiguous records, by the author's own writes, or by an E marker from the peer we asked.

local dgks = dgks
local H = {}
dgks.History = H

local PREFIX = "dgksH"
local PROTOCOL = 1
local SUMMARY_FIRST_DELAY = 30        -- seconds after login before the first summary
local SUMMARY_INTERVAL = 15 * 60      -- seconds between summaries
local REQUEST_TIMEOUT = 120           -- seconds before a request that got no answer may be retried
local MAX_STREAMS_PER_REQUEST = 40
local MAX_RECORDS_PER_ANSWER = 300    -- per stream per request; the rest follows next round
local RECORDS_PER_BATCH = 8
-- Kill, Death, duel Win, duel Loss, and X: a killing blow by a party or raid member that we saw
local KINDS = { K = true, D = true, W = true, L = true, X = true }

H.KIND_NAMES = { K = "Kill", D = "Death", W = "Duel win", L = "Duel loss", X = "Team kill" }

local queue = {}          -- outgoing messages waiting for a moment when sending is allowed
local pending = {}        -- [stream] = { peer = name, at = time } requests we are waiting on
local roster = {}         -- [Name-Realm] = { online = bool, target = name as the roster spells it }
local rosterAt = 0        -- when we last asked the server for the roster
local whispered = {}      -- [lowercased name] = time of our last addon whisper to it
local memberCache = {}    -- [name] = canonical member name, see H.CanonicalMember
local nextSummaryAt = 0
local myName, myRealm, guildKey
local legacyKey -- Forever: the key this guild had before the realm fell back to "Unknown" ("Guild-"); still heard

-- Helpers -------------------------------------------------------------------------------------

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A value we may store: not secret, and of the expected type
local function usable(v, wantType)
	return v ~= nil and not isSecret(v) and type(v) == wantType
end

local function realmName()
	return dgks.RealmName() or "Unknown"
end

-- "Name-" (an empty realm: the likely-killer guess wrote these on Forever, where the game's
-- normalized realm name is empty) -> "Name"
local function dropEmptyRealm(name)
	return (name:gsub("%-+$", ""))
end

-- "Name" -> "Name-Realm" (our realm); "Name-Realm" stays as it is
function H.FullName(name)
	if not usable(name, "string") then return nil end
	name = dropEmptyRealm(name)
	if name == "" then return nil end
	if name:find("-", 1, true) then return name end
	return name .. "-" .. (myRealm or realmName())
end

-- Short display name: drop our own realm
function H.ShortName(name)
	if type(name) ~= "string" then return "?" end
	name = dropEmptyRealm(name)
	local n, r = name:match("^(.-)%-(.+)$")
	if n and r == myRealm then return n end
	return name
end

local function streamKey(author, epoch)
	return author .. "#" .. epoch
end

local function now() return time() end

local function retentionDays()
	local d = dgks.db.profile.historyRetentionDays
	if type(d) ~= "number" or d < 1 then d = 90 end
	return d
end

local function cutoff()
	return now() - retentionDays() * 86400
end

-- Can sync traffic go out now? On clients with secret values, addon messages are blocked while the
-- game reports chat messaging lockdown (encounters, Mythic+ and the like). Battlegrounds and arenas
-- are not restricted, so records are shared during the match. Dungeons, raids and scenarios wait
-- until we leave, to keep sync traffic out of group content.
local function canSend()
	if issecretvalue == nil then return true end
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if not ok or isSecret(locked) or locked == true then return false end
	end
	local inInstance, instanceType = IsInInstance()
	if isSecret(inInstance) or isSecret(instanceType) then return false end
	if not inInstance then return true end
	return instanceType == "pvp" or instanceType == "arena"
end

local function send(dist, target, prio, ...)
	queue[#queue + 1] = { msg = dgks:Serialize(...), dist = dist, target = target, prio = prio }
end

-- Ask the server for a fresh guild roster (online flags), at most every 30 seconds
local function requestRoster()
	if now() - rosterAt < 30 or not IsInGuild() then return end
	rosterAt = now()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		pcall(C_GuildInfo.GuildRoster)
	elseif GuildRoster then
		pcall(GuildRoster)
	end
end

-- Whispers go only to guild members the roster shows online, spelled as the roster spells them.
-- A whisper to anyone else makes the game print "No player named ... is currently playing", and
-- queued sync whispers can wait minutes (dungeons, raids) while the member logs off.
local function whisperTarget(name)
	local m = roster[name]
	if not m or not m.online then return nil end
	return m.target
end

-- The game answers an addon whisper that finds nobody with "No player named ... is currently
-- playing": a guild member or friend who logs off with our message on its way, a Battle.net friend
-- the game cannot reach by that name. Every addon whisper (sync, kill and version messages to
-- friends, version replies) goes through dgks:SendCommMessage, so note each target there and hide
-- that line for names we whispered in the last minute.
local function noteWhisper(target)
	if type(target) ~= "string" or isSecret(target) then return end
	local t = now()
	whispered[target:lower()] = t
	-- The line may name the player without the realm we added
	local base = target:match("^(.-)%-[^%-]+$")
	if base and base ~= "" then whispered[base:lower()] = t end
end
local aceSendCommMessage = dgks.SendCommMessage
function dgks:SendCommMessage(prefix, text, distribution, target, ...)
	if distribution == "WHISPER" then noteWhisper(target) end
	return aceSendCommMessage(self, prefix, text, distribution, target, ...)
end

local function flushQueue()
	if #queue == 0 or not canSend() then return end
	local q = queue
	queue = {}
	for _, m in ipairs(q) do
		local target = m.target
		if m.dist == "WHISPER" then target = whisperTarget(m.target) end
		if m.dist ~= "WHISPER" or target then
			if target then noteWhisper(target) end -- also kept if another addon re-embeds AceComm
			local ok = pcall(dgks.SendCommMessage, dgks, PREFIX, m.msg, m.dist, target, m.prio)
			if not ok then break end -- the rest is lost; the next summary round repairs it
		end
	end
end

-- Hide "No player named ..." for a name we whispered in the last minute (see noteWhisper)
local function hidePlayerNotFound(_, _, msg, ...)
	if type(msg) ~= "string" or isSecret(msg) or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return false end
	local pattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
	local name = msg:match(pattern)
	if not name then return false end
	local t = whispered[name:lower()]
	return t ~= nil and now() - t < 60
end

-- Records ---------------------------------------------------------------------------------------

local FIELDS = {
	-- name = { type, max length or { min, max } }
	a = { "string", 64 },  -- author, "Name-Realm"
	e = { "number", { 0, 4e9 } }, -- stream epoch
	s = { "number", { 1, 1e9 } }, -- sequence number in the stream
	t = { "number", { 1e9, 4e9 } }, -- time() when it happened
	k = { "string", 1 },   -- kind: K, D, W, L
	o = { "string", 64 },  -- opponent: victim for K/W, killer for D/L
	p = { "number", { 1, 1 } }, -- 1 when the opponent is known to be a player
	oc = { "string", 20 }, -- opponent class file, e.g. "MAGE"
	orc = { "string", 30 }, -- opponent race file
	ol = { "number", { -1, 1000 } }, -- opponent level
	c = { "string", 20 },  -- author class file
	l = { "number", { 0, 1000 } }, -- author level
	z = { "string", 100 }, -- zone
	sz = { "string", 100 }, -- subzone
	m = { "number", { 0, 1e7 } }, -- map ID
	i = { "string", 16 },  -- instance type: none, pvp, arena, party, raid, scenario
	st = { "number", { 0, 1e6 } }, -- killing streak after this record
	mk = { "number", { 0, 100 } }, -- multikill level
	lg = { "number", { 1, 1 } }, -- imported from the old kill/death lists (personal only)
	u = { "number", { 1, 1 } },  -- the killer is not known; o says why ("Hidden by the game", ...)
	g = { "number", { 1, 1 } },  -- the killer is a guess: an enemy player targeting us when we died
	gn = { "number", { 1, 40 } }, -- how many enemy players were targeting us then
	os = { "number", { 1, 100000 } }, -- opponent spec ID (when an inspect found it)
	cs = { "number", { 1, 100000 } }, -- author spec ID
	kn = { "string", 64 }, -- team kill (X): the killer, "Name-Realm"
	kc = { "string", 20 }, -- team kill: killer class file
	ks = { "number", { 1, 100000 } }, -- team kill: killer spec ID
}
local REQUIRED = { a = true, e = true, s = true, t = true, k = true, o = true }

-- Returns a clean copy of a record received from someone else, or nil if it is malformed
local function cleanRecord(rec)
	if type(rec) ~= "table" then return nil end
	local out = {}
	for name, spec in pairs(FIELDS) do
		local v = rec[name]
		if v == nil then
			if REQUIRED[name] then return nil end
		else
			if type(v) ~= spec[1] then return nil end
			if spec[1] == "string" then
				if #v > spec[2] or v == "" then return nil end
			else
				if v ~= v or v < spec[2][1] or v > spec[2][2] then return nil end
			end
			out[name] = v
		end
	end
	if not KINDS[out.k] or out.s ~= math.floor(out.s) then return nil end
	if out.t > now() + 86400 then return nil end
	return out
end

local function copyRecord(rec)
	local out = {}
	for k, v in pairs(rec) do out[k] = v end
	return out
end

-- Guild store -----------------------------------------------------------------------------------

local function guildStore(create)
	if not guildKey then return nil end
	local guilds = dgks.db.global.history.guilds
	if not guilds[guildKey] and create then
		guilds[guildKey] = { streams = {} }
	end
	return guilds[guildKey]
end

local function getStream(store, stream)
	local st = store.streams[stream]
	if not st then
		st = { h = 0, r = {} }
		store.streams[stream] = st
	end
	return st
end

local function advanceHead(st)
	while st.r[st.h + 1] do st.h = st.h + 1 end
end

-- Store a record in the guild store. Returns true if it was new.
local function storeRecord(store, rec)
	if rec.t < cutoff() then return false end
	local st = getStream(store, streamKey(rec.a, rec.e))
	if st.r[rec.s] then return false end
	st.r[rec.s] = rec
	advanceHead(st)
	return true
end

function H:Prune()
	local limit = cutoff()
	for _, store in pairs(dgks.db.global.history.guilds) do
		for _, st in pairs(store.streams) do
			for seq, rec in pairs(st.r) do
				if rec.t < limit then st.r[seq] = nil end
			end
		end
	end
end

-- Every record in the current guild store, as a list
-- Two records within this many seconds of each other describe the same kill
local SAME_KILL_WINDOW = 15

-- Every record in the current guild store, as a list. Team kills (X) are dropped when the killer
-- recorded the kill themselves, or when another member already reported the same kill.
function H:GuildRecords()
	local list, teamKills = {}, {}
	local store = guildStore(false)
	if not store then return list end
	local ownKills = {} -- [killerKey|victimKey] = { times }
	for _, st in pairs(store.streams) do
		for _, rec in pairs(st.r) do
			if rec.k == "X" then
				teamKills[#teamKills + 1] = rec
			else
				list[#list + 1] = rec
				if rec.k == "K" then
					local key = (H.PlayerKey(H.CanonicalMember(rec.a)) or "?") .. "|" .. (H.OpponentKey(rec) or "?")
					ownKills[key] = ownKills[key] or {}
					table.insert(ownKills[key], rec.t)
				end
			end
		end
	end
	local function near(times, t)
		if not times then return false end
		for _, other in ipairs(times) do
			if math.abs(other - t) <= SAME_KILL_WINDOW then return true end
		end
		return false
	end
	table.sort(teamKills, function(a, b) return a.t < b.t end)
	local seen = {}
	for _, rec in ipairs(teamKills) do
		-- The killer's own record may name them by first name only ("Pink") while the witness wrote the full
		-- name ("Pink Tonic"): compare them as the same member, or the kill is listed twice
		local key = (H.PlayerKey(H.CanonicalMember(rec.kn), rec.a and rec.a:match("%-(.+)$")) or "?") .. "|" .. (H.OpponentKey(rec) or "?")
		if not near(ownKills[key], rec.t) and not near(seen[key], rec.t) then
			seen[key] = seen[key] or {}
			table.insert(seen[key], rec.t)
			list[#list + 1] = rec
		end
	end
	return list
end

function H:PersonalRecords()
	return dgks.db.char.history.records
end

function H:GuildKey()
	return guildKey
end

-- Recording -------------------------------------------------------------------------------------

-- Details about a player we can read from their GUID
local function opponentInfo(rec, guid)
	-- The player cache (dgks_players.lua) knows players we have seen: the Death Recap only gives a
	-- killer's name, so look it up there for their GUID, level and spec
	local seen = dgks.Players and dgks.Players:Lookup(rec.o, usable(guid, "string") and guid or nil)
	if seen then
		if not usable(guid, "string") then guid = seen.guid end
		if seen.class then rec.oc = seen.class end
		if seen.race then rec.orc = seen.race end
		if seen.level then rec.ol = seen.level end
		if seen.spec then rec.os = seen.spec end
	end
	if not usable(guid, "string") then return end
	if not guid:match("^Player%-") then return end
	rec.p = 1
	local ok, _, classFile, _, raceFile, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok then return end
	if usable(classFile, "string") and classFile ~= "" then rec.oc = classFile end
	if usable(raceFile, "string") and raceFile ~= "" then rec.orc = raceFile end
	name, realm = dgks.SplitName(name, realm) -- Forever: "First Surname", no realm
	if name and not rec.o:find("-", 1, true) then
		rec.o = name .. "-" .. (realm or myRealm)
	end
	local tguid = UnitGUID("target")
	if usable(tguid, "string") and tguid == guid then
		local level = UnitLevel("target")
		if usable(level, "number") then rec.ol = level end
	end
end

-- Killer names written by older versions when the killer was not known
local LEGACY_UNKNOWN = { ["Unknown because of retail"] = true, ["Unknown Entity"] = true }

-- Is this record's opponent unknown (a reason rather than a name)?
function H.IsUnknown(rec)
	return rec.u ~= nil or LEGACY_UNKNOWN[rec.o] == true
end

-- Record something that happened to us. kind: K, D, W or L. opponent: the other player's name.
-- guid: the opponent's GUID when known. streak/multikill: the counters after this event.
-- flags (optional): { unknown = true } when opponent is a reason, not a name;
-- { guessed = n } when opponent is a guess made from n enemy players targeting us.
-- Called from the kill and death handlers, so a failure here must never reach them.
function H:Record(kind, opponent, guid, streak, multikill, flags)
	local ok, result = pcall(H.RecordUnsafe, H, kind, opponent, guid, streak, multikill, flags)
	--@debug@
	if not ok then dgks:Print("DEBUG: History record failed: " .. tostring(result)) end
	--@end-debug@
	if ok then return result end
end

-- A killing blow by a party or raid member on another player, seen through PARTY_KILL (retail) or
-- the combat log (Classic). Recorded as a team kill: in our history, and in guild history when the
-- killer is a guild member, where it counts as their kill.
function H:RecordTeamKill(killerGUID, victimGUID)
	if not dgks.db.profile.recordTeamKills then return end
	if not (usable(killerGUID, "string") and usable(victimGUID, "string")) then return end
	if not victimGUID:match("^Player%-") then return end
	local function info(guid)
		local ok, _, classFile, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
		if not ok then return nil end
		name, realm = dgks.SplitName(name, realm) -- Forever: "First Surname", no realm
		if not name then return nil end
		return name .. "-" .. (realm or myRealm), usable(classFile, "string") and classFile or nil
	end
	local killerName, killerClass = info(killerGUID)
	local victimName = info(victimGUID)
	if not killerName or not victimName then return end
	local spec = dgks.Players and dgks.Players:SpecFor(killerGUID)
	return H:Record("X", victimName, victimGUID, nil, nil, { killer = { name = killerName, class = killerClass, spec = spec } })
end

function H:RecordUnsafe(kind, opponent, guid, streak, multikill, flags)
	if not KINDS[kind] or not usable(opponent, "string") or opponent == "" then return end
	if not myName then H:UpdateIdentity() end
	if not myName then return end

	local rec = { k = kind, t = now(), o = opponent:sub(1, 64), a = myName }
	opponentInfo(rec, guid)

	local _, classFile = UnitClass("player")
	if usable(classFile, "string") then rec.c = classFile end
	local level = UnitLevel("player")
	if usable(level, "number") then rec.l = level end
	local mySpec = dgks.Players and dgks.Players.MySpec()
	if mySpec then rec.cs = mySpec end
	local zone, subzone = GetRealZoneText(), GetSubZoneText()
	if usable(zone, "string") and zone ~= "" then rec.z = zone:sub(1, 100) end
	if usable(subzone, "string") and subzone ~= "" then rec.sz = subzone:sub(1, 100) end
	if C_Map and C_Map.GetBestMapForUnit then
		local mapID = C_Map.GetBestMapForUnit("player")
		if usable(mapID, "number") then rec.m = mapID end
	end
	local _, instanceType = IsInInstance()
	if usable(instanceType, "string") then rec.i = instanceType end
	if usable(streak, "number") then rec.st = streak end
	if usable(multikill, "number") and multikill > 0 then rec.mk = multikill end
	if LEGACY_UNKNOWN[rec.o] or (flags and flags.unknown) then rec.u = 1 end
	if kind == "X" then
		local killer = flags and flags.killer
		if not (killer and usable(killer.name, "string")) then return end
		rec.kn = killer.name:sub(1, 64)
		if usable(killer.class, "string") then rec.kc = killer.class end
		if usable(killer.spec, "number") then rec.ks = killer.spec end
	end
	if flags and type(flags.guessed) == "number" then
		rec.g = 1
		rec.gn = math.max(1, math.min(40, math.floor(flags.guessed)))
	end

	-- Shared records get a place in our stream
	local store = dgks.db.profile.historyShare and guildStore(true)
	-- A team kill is guild history only when the killer is in our guild
	if store and kind == "X" and not (flags and flags.killer and roster[H.FullName(flags.killer.name)]) then store = nil end
	if store then
		local stream = dgks.db.char.historyStream
		if not stream or stream.a ~= myName then
			stream = { a = myName, e = now(), s = 0 }
			dgks.db.char.historyStream = stream
		end
		stream.s = stream.s + 1
		rec.e, rec.s = stream.e, stream.s
	end

	local records = dgks.db.char.history.records
	records[#records + 1] = copyRecord(rec)

	if store then
		local st = getStream(store, streamKey(rec.a, rec.e))
		st.r[rec.s] = rec
		st.h = math.max(st.h, rec.s) -- we are the author: everything up to here is complete
		send("GUILD", nil, "NORMAL", "R", guildKey, rec)
	end
	H:NotifyChanged()
	return records[#records]
end

-- Sync ------------------------------------------------------------------------------------------

local function headsAndDigest()
	local store = guildStore(false)
	local heads, keys = {}, {}
	if store then
		for stream, st in pairs(store.streams) do
			if st.h > 0 then
				heads[stream] = st.h
				keys[#keys + 1] = stream
			end
		end
	end
	table.sort(keys)
	local h = 5381
	for _, k in ipairs(keys) do
		local s = k .. "=" .. heads[k] .. ";"
		for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	end
	return heads, h
end

function H:SendSummary()
	nextSummaryAt = now() + SUMMARY_INTERVAL + math.random(0, 60)
	if not guildKey or not dgks.db.profile.historyShare then return end
	local heads, digest = headsAndDigest()
	send("GUILD", nil, "BULK", "S", guildKey, PROTOCOL, digest, heads)
end

local function isMember(name)
	return name ~= nil and roster[name] ~= nil
end

local function onSummary(sender, proto, digest, heads)
	if proto ~= PROTOCOL or type(heads) ~= "table" then return end
	local _, myDigest = headsAndDigest()
	if digest == myDigest then
		-- Someone just said what we would say: skip our next summary
		nextSummaryAt = now() + SUMMARY_INTERVAL + math.random(0, 60)
		return
	end
	local store = guildStore(true)
	local wants, count, t = {}, 0, now()
	for stream, head in pairs(heads) do
		if count >= MAX_STREAMS_PER_REQUEST then break end
		if type(stream) == "string" and #stream <= 80 and stream:find("#", 1, true)
			and type(head) == "number" and head == math.floor(head) and head > 0 then
			local mine = store.streams[stream] and store.streams[stream].h or 0
			local p = pending[stream]
			if head > mine and not (p and t - p.at < REQUEST_TIMEOUT) then
				wants[stream] = mine
				pending[stream] = { peer = sender, at = t, target = head }
				count = count + 1
			end
		end
	end
	if count > 0 then
		send("WHISPER", sender, "BULK", "Q", guildKey, wants)
	end
	-- If the sender is missing records we hold (a member who just logged in, say), send our summary
	-- soon so they can ask for them. Whoever goes first suppresses the identical summaries of the rest.
	for stream, st in pairs(store.streams) do
		local theirs = heads[stream]
		if st.h > 0 and (type(theirs) ~= "number" or theirs < st.h) then
			nextSummaryAt = math.min(nextSummaryAt, t + math.random(3, 15))
			break
		end
	end
end

local function onRequest(sender, wants)
	if type(wants) ~= "table" then return end
	local store = guildStore(false)
	if not store then return end
	local count = 0
	for stream, from in pairs(wants) do
		count = count + 1
		if count > MAX_STREAMS_PER_REQUEST then break end
		local st = type(stream) == "string" and store.streams[stream]
		if st and type(from) == "number" and from >= 0 and from < st.h then
			local batch, sent, upTo = {}, 0, st.h
			for seq = math.floor(from) + 1, st.h do
				local rec = st.r[seq]
				if rec then
					batch[#batch + 1] = rec
					sent = sent + 1
					if #batch >= RECORDS_PER_BATCH then
						send("WHISPER", sender, "BULK", "B", guildKey, stream, batch)
						batch = {}
					end
					if sent >= MAX_RECORDS_PER_ANSWER then
						upTo = seq
						break
					end
				end
			end
			if #batch > 0 then send("WHISPER", sender, "BULK", "B", guildKey, stream, batch) end
			send("WHISPER", sender, "BULK", "E", guildKey, stream, upTo)
		end
	end
end

local function onBatch(sender, stream, batch)
	local p = type(stream) == "string" and pending[stream]
	if not p or p.peer ~= sender or type(batch) ~= "table" then return end
	p.at = now() -- still answering
	local store = guildStore(true)
	local added = false
	for _, raw in ipairs(batch) do
		local rec = cleanRecord(raw)
		if rec and streamKey(rec.a, rec.e) == stream then
			if storeRecord(store, rec) then added = true end
		end
	end
	if added then H:NotifyChanged() end
end

local function onEnd(sender, stream, upTo)
	local p = type(stream) == "string" and pending[stream]
	if not p or p.peer ~= sender then return end
	pending[stream] = nil
	if type(upTo) ~= "number" or upTo ~= math.floor(upTo) or upTo < 1 then return end
	local st = getStream(guildStore(true), stream)
	if upTo > st.h then
		st.h = upTo
		advanceHead(st)
	end
	-- An answer is capped at MAX_RECORDS_PER_ANSWER; ask the same peer for the rest right away
	if p.target and st.h < p.target and upTo > 0 then
		pending[stream] = { peer = sender, at = now(), target = p.target }
		send("WHISPER", sender, "BULK", "Q", guildKey, { [stream] = st.h })
	end
end

-- Is `author` (a record's author) the sender? On Forever a member on a version before 12.0.010 writes
-- themselves "Name-" (an empty realm) where the sender is "Name-Unknown": accept exactly that spelling too.
local function sameMember(author, sender)
	if author == sender then return true end
	return dgks.UsesSurnames() and type(author) == "string" and type(sender) == "string"
		and author == H.ShortName(sender) .. "-"
end

local function onLiveRecord(sender, raw)
	local rec = cleanRecord(raw)
	-- Only the author may announce a new record
	if not rec or not sameMember(rec.a, sender) then return end
	if storeRecord(guildStore(true), rec) then H:NotifyChanged() end
end

function dgks:OnHistoryComm(prefix, message, distribution, sender)
	if prefix ~= PREFIX or not guildKey or not dgks.db.profile.historyShare then return end
	if isSecret(message) or isSecret(sender) or type(sender) ~= "string" then return end
	sender = H.FullName(sender)
	if sender == myName then return end
	local ok, op, gk, a, b, c, d = dgks:Deserialize(message)
	-- On Forever a member on an older version still speaks with the old key ("Guild-"). We can hear them
	-- but they cannot hear us, so we only take their live records: a summary would make us ask them for
	-- records (a request they drop, which would also hold off the same streams from anyone else) and send
	-- summaries they ignore.
	if not ok or (gk ~= guildKey and gk ~= legacyKey) then return end
	local legacy = gk ~= guildKey

	if distribution == "GUILD" then
		-- They just spoke in guild chat, so they are online whatever the roster last said
		if roster[sender] then roster[sender].online = true end
		if op == "R" then onLiveRecord(sender, a)
		elseif op == "S" and not legacy then onSummary(sender, a, b, c) end
	elseif distribution == "WHISPER" and not legacy and isMember(sender) then
		if op == "Q" then onRequest(sender, a)
		elseif op == "B" then onBatch(sender, a, b)
		elseif op == "E" then onEnd(sender, a, b) end
	end
end

-- Guild and identity ----------------------------------------------------------------------------

function H:UpdateIdentity()
	local name = dgks.PlayerFullName() -- Forever: "First Surname"
	if usable(name, "string") and name ~= "" and name ~= UNKNOWNOBJECT then
		myRealm = realmName()
		myName = name .. "-" .. myRealm
	end
end

-- On Forever there is no realm, and the realm part of the guild key has changed with the version: "Guild-"
-- before 12.0.010, "Guild-Unknown" since (dgks.RealmName() falls back to "Unknown"). Guild names are unique
-- on Forever, so a store saved under any of those keys is the same guild. Merge each of them into the
-- current one, so the history does not look reset after an update (or after the next change): a stream that
-- is not there yet is moved over, one that is gets the records it lacks and its head advanced. It only adds
-- records, and an old store is removed only once it has been merged.
local function mergeGuildStore(oldKey)
	local guilds = dgks.db.global.history.guilds
	local old = guilds[oldKey]
	if type(old) ~= "table" or type(old.streams) ~= "table" then return end
	local store = guildStore(true)
	if not store then return end
	for key, ost in pairs(old.streams) do
		if type(key) == "string" and type(ost) == "table" and type(ost.r) == "table" then
			local st = getStream(store, key)
			local top = 0
			for seq, rec in pairs(ost.r) do
				-- Only what a received record would have to be: a whole sequence number and a valid record
				if type(seq) == "number" and seq >= 1 and seq == math.floor(seq) then
					local clean = cleanRecord(rec)
					if clean then
						if st.r[seq] == nil then st.r[seq] = clean end
						if seq > top then top = seq end
					end
				end
			end
			-- The old head may sit past records that expired (and were pruned), so the records alone would
			-- leave a gap at the start and the head at 0, which is never advertised. Keep it, but never past
			-- the last record we actually hold.
			if type(ost.h) == "number" and ost.h == math.floor(ost.h) then
				st.h = math.max(st.h, math.min(ost.h, top))
			end
			advanceHead(st)
		end
	end
	guilds[oldKey] = nil
	H.countCache = nil
end

-- The only keys a guild's history has been saved under on Forever: "Guild-" (before 12.0.010) and
-- "Guild-Unknown" (since). Not every "Guild-<realm>": on a real realm that is another guild's store.
local function mergeGuildStores(gname)
	local guilds = dgks.db.global.history.guilds
	for _, key in ipairs({ gname .. "-", gname .. "-Unknown" }) do
		if key ~= guildKey and guilds[key] ~= nil then
			pcall(mergeGuildStore, key) -- one damaged store must not stop the other
		end
	end
end

function H:UpdateGuild()
	local old = guildKey
	guildKey, legacyKey = nil, nil
	local gname, fellBack
	if IsInGuild() then
		local gn, _, _, grealm = GetGuildInfo("player")
		if usable(gn, "string") and gn ~= "" then
			gname = gn
			if not usable(grealm, "string") or grealm == "" then
				grealm = myRealm or realmName() -- myRealm is not known yet if the identity was not ready at login
				fellBack = dgks.UsesSurnames() -- Forever: no realm, so the stand-in is used
			end
			guildKey = gname .. "-" .. grealm
		end
	end
	if guildKey and fellBack then
		-- A member on an older version still speaks with the old key
		if gname .. "-" ~= guildKey then legacyKey = gname .. "-" end
		-- A failure here must never stop the guild from being set up
		pcall(mergeGuildStores, gname)
	end
	if guildKey ~= old then
		wipe(pending)
		nextSummaryAt = now() + SUMMARY_FIRST_DELAY
		H:NotifyChanged()
	end
end

-- The name a guild member is listed under. On WoW Forever characters have a first name and a surname, and
-- versions before 12.0.009 recorded some names as the first name only ("Pink" for "Pink Tonic"), and
-- team kills are credited to the killer's name as the witnessing client wrote it, so one member could
-- appear twice in the guild tables and a kill be listed twice. A name without a surname that is the start
-- of exactly one guild member's full name ("Pink " + "Tonic") is that member. Nothing stored is changed:
-- this only decides which row a record is counted under. A name is left alone when it is already a full
-- name, when it is a real one-word member, when two members could match, or when there is no roster yet.
-- Forever only. Our own realm and a bare "-" are dropped first, like H.ShortName does, so "Pink-Unknown"
-- (a name saved with this client's stand-in realm) is "Pink".
function H.CanonicalMember(name)
	if type(name) ~= "string" or name == "" then return name end
	if not dgks.UsesSurnames() then return name end
	name = H.ShortName(name)
	local cached = memberCache[name]
	if cached ~= nil then return cached end
	local result = name
	if not name:find(" ", 1, true) and not name:find("-", 1, true) then
		local prefix = name .. " "
		local found, ambiguous, isMemberName = nil, false, false
		for full in pairs(roster) do
			local base = H.ShortName(full)
			if base == name then
				isMemberName = true -- a real member with this exact name
			elseif base:sub(1, #prefix) == prefix then
				if found and found ~= base then ambiguous = true end
				found = found or base
			end
		end
		if found and not ambiguous and not isMemberName then result = found end
	end
	memberCache[name] = result
	return result
end

function H:UpdateRoster()
	local old = {}
	for k in pairs(roster) do old[k] = true end
	wipe(roster)
	if IsInGuild() then
		local n = GetNumGuildMembers() or 0
		for i = 1, n do
			local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
			if usable(name, "string") then
				roster[H.FullName(name)] = { online = online == true, target = name }
			end
		end
	end
	-- The roster refreshes often; only redo the member names when the members themselves changed
	local changed = false
	for k in pairs(roster) do if not old[k] then changed = true break end end
	if not changed then for k in pairs(old) do if not roster[k] then changed = true break end end end
	if changed then
		wipe(memberCache)
		-- Only Forever has member names to redo; elsewhere the tables are left exactly as they were
		if dgks.UsesSurnames() then H:NotifyChanged() end
	end
end

-- Old data --------------------------------------------------------------------------------------

-- Copy the old killList/deathList (name -> list of "mm/dd/yy HH:MM:SS") into personal history once.
-- Those lists live in the shared profile, so they go to the first character that loads this version.
-- Names saved as "Name-" (see dropEmptyRealm) get the realm they were meant to have: the author's.
-- Authors are never changed: guild streams are keyed by them.
function H:RepairEmptyRealms()
	local function repair(rec)
		local realm = rec.a and rec.a:match("%-([^%-]+)$") or myRealm
		for _, field in ipairs({ "o", "kn" }) do
			local v = rec[field]
			if type(v) == "string" and v:sub(-1) == "-" then
				v = dropEmptyRealm(v)
				if v ~= "" and realm then rec[field] = v .. "-" .. realm end
			end
		end
	end
	for _, rec in ipairs(dgks.db.char.history.records) do repair(rec) end
	for _, store in pairs(dgks.db.global.history.guilds) do
		for _, st in pairs(store.streams or {}) do
			for _, rec in pairs(st.r or {}) do repair(rec) end
		end
	end
end

local function importLegacy()
	local profile = dgks.db.profile
	if profile.historyLegacyImported then return end
	profile.historyLegacyImported = true
	local records = dgks.db.char.history.records
	local imported = {}
	local function import(list, kind)
		if type(list) ~= "table" then return end
		for name, dates in pairs(list) do
			if type(name) == "string" and type(dates) == "table" then
				for _, d in pairs(dates) do
					local mo, dd, yy, hh, mi, ss = tostring(d):match("^(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+)$")
					if mo then
						local t = time({ year = 2000 + tonumber(yy), month = tonumber(mo), day = tonumber(dd),
							hour = tonumber(hh), min = tonumber(mi), sec = tonumber(ss) })
						imported[#imported + 1] = { k = kind, t = t, o = name, a = myName, lg = 1 }
					end
				end
			end
		end
	end
	import(profile.killList, "K")
	import(profile.deathList, "D")
	table.sort(imported, function(x, y) return x.t < y.t end)
	-- Older than anything recorded so far: put them first
	for i = #imported, 1, -1 do table.insert(records, 1, imported[i]) end
	if #imported > 0 then
		dgks:Print(("Imported %d kills and deaths from the old kill and death lists into your history."):format(#imported))
	end
end

-- Counts per player (for tooltips) ----------------------------------------------------------------

-- A key that names one player the same way everywhere: "Name-Realm" with the realm written like
-- GetNormalizedRealmName (no spaces or hyphens). A name without a realm belongs to defaultRealm.
function H.PlayerKey(name, defaultRealm)
	if type(name) ~= "string" then return nil end
	name = dropEmptyRealm(name)
	if name == "" then return nil end
	local n, realm = name:match("^([^%-]+)%-(.+)$")
	if not n then n, realm = name, defaultRealm or myRealm end
	if not realm then return nil end
	return n .. "-" .. realm:gsub("[%s%-]", "")
end

local function authorRealm(rec)
	return type(rec.a) == "string" and rec.a:match("%-(.+)$") or myRealm
end

-- The PlayerKey of a record's opponent. A name without a realm is on the author's realm.
function H.OpponentKey(rec)
	return H.PlayerKey(rec.o, authorRealm(rec))
end

-- teamKills: count team kills (X) as kills; true for the guild, false for our own counts
local function buildCounts(records, into, teamKills)
	for _, rec in ipairs(records) do
		local kind = rec.k
		if kind == "X" and teamKills then kind = "K" end
		if (kind == "K" or kind == "D") and not H.IsUnknown(rec) then
			local key = H.PlayerKey(rec.o, authorRealm(rec))
			if key then
				local c = into[key]
				if not c then
					c = { K = 0, D = 0 }
					into[key] = c
				end
				c[kind] = c[kind] + 1
			end
		end
	end
end

-- How often this character, and the guild, killed (K) and were killed by (D) the given player.
-- Returns two tables { K = n, D = n }, or nil for the guild when we are not in one.
function H:CountsFor(key)
	if not H.countCache then
		local cache = { personal = {}, guild = {} }
		buildCounts(H:PersonalRecords(), cache.personal)
		buildCounts(H:GuildRecords(), cache.guild, true)
		H.countCache = cache
	end
	local none = { K = 0, D = 0 }
	local guild = guildKey and (H.countCache.guild[key] or none) or nil
	return H.countCache.personal[key] or none, guild
end

-- Change notification (the UI listens) -----------------------------------------------------------

H.listeners = {}
local notifyScheduled = false
function H:NotifyChanged()
	H.countCache = nil
	if notifyScheduled then return end
	notifyScheduled = true
	C_Timer.After(1, function()
		notifyScheduled = false
		for _, fn in pairs(H.listeners) do pcall(fn) end
	end)
end

-- Setup -----------------------------------------------------------------------------------------

function H:ClearGuild()
	if not guildKey then return end
	dgks.db.global.history.guilds[guildKey] = nil
	wipe(pending)
	H:NotifyChanged()
end

function H:SyncNow()
	if not guildKey then
		dgks:Print("You are not in a guild, so there is nothing to sync.")
		return
	end
	wipe(pending)
	H:SendSummary()
	if not canSend() then
		dgks:Print("History sync is waiting: the game is restricting addon messages, or you are in a dungeon or raid.")
	end
end

function H:Initialize()
	local db = dgks.db
	db.global.history = db.global.history or {}
	db.global.history.guilds = db.global.history.guilds or {}
	db.char.history = db.char.history or {}
	db.char.history.records = db.char.history.records or {}

	H:UpdateIdentity()
	dgks:RegisterComm(PREFIX, "OnHistoryComm")
end

function H:Enable()
	H:UpdateIdentity()
	importLegacy()
	H:RepairEmptyRealms()
	H:Prune()
	H:InstallTooltip() -- dgks_history_ui.lua

	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_GUILD_UPDATE")
	f:RegisterEvent("GUILD_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function(_, event)
		if event == "GUILD_ROSTER_UPDATE" then
			H:UpdateRoster()
		end
		H:UpdateGuild()
	end)
	requestRoster()
	local filter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if filter then pcall(filter, "CHAT_MSG_SYSTEM", hidePlayerNotFound) end

	local lastPrune = now()
	C_Timer.NewTicker(2, function()
		if not guildKey then H:UpdateGuild() end
		-- Keep the online flags fresh while whispers wait
		for _, m in ipairs(queue) do
			if m.dist == "WHISPER" then requestRoster() break end
		end
		if guildKey and now() >= nextSummaryAt then H:SendSummary() end
		flushQueue()
		if now() - lastPrune > 3600 then
			lastPrune = now()
			H:Prune()
		end
	end)
end
