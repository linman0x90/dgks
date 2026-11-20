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
local KINDS = { K = true, D = true, W = true, L = true } -- Kill, Death, duel Win, duel Loss

H.KIND_NAMES = { K = "Kill", D = "Death", W = "Duel win", L = "Duel loss" }

local queue = {}          -- outgoing messages waiting for a moment when sending is allowed
local pending = {}        -- [stream] = { peer = name, at = time } requests we are waiting on
local roster = {}         -- [Name-Realm] = true, guild members
local nextSummaryAt = 0
local myName, myRealm, guildKey

-- Helpers -------------------------------------------------------------------------------------

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A value we may store: not secret, and of the expected type
local function usable(v, wantType)
	return v ~= nil and not isSecret(v) and type(v) == wantType
end

local function realmName()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if usable(realm, "string") and realm ~= "" then return realm end
	realm = GetRealmName and GetRealmName()
	if usable(realm, "string") then return (realm:gsub("[%s%-]", "")) end
	return "Unknown"
end

-- "Name" -> "Name-Realm" (our realm); "Name-Realm" stays as it is
function H.FullName(name)
	if not usable(name, "string") or name == "" then return nil end
	if name:find("-", 1, true) then return name end
	return name .. "-" .. (myRealm or realmName())
end

-- Short display name: drop our own realm
function H.ShortName(name)
	if type(name) ~= "string" then return "?" end
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

-- Addon traffic in instances and combat is restricted on clients with secret values; queue it.
local function canSend()
	if issecretvalue == nil then return true end
	if InCombatLockdown() then return false end
	local inInstance = IsInInstance()
	return not inInstance
end

local function send(dist, target, prio, ...)
	queue[#queue + 1] = { msg = dgks:Serialize(...), dist = dist, target = target, prio = prio }
end

local function flushQueue()
	if #queue == 0 or not canSend() then return end
	local q = queue
	queue = {}
	for _, m in ipairs(q) do
		local ok = pcall(dgks.SendCommMessage, dgks, PREFIX, m.msg, m.dist, m.target, m.prio)
		if not ok then break end -- the rest is lost; the next summary round repairs it
	end
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
function H:GuildRecords()
	local list = {}
	local store = guildStore(false)
	if not store then return list end
	for _, st in pairs(store.streams) do
		for _, rec in pairs(st.r) do list[#list + 1] = rec end
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
	if not usable(guid, "string") then return end
	if not guid:match("^Player%-") then return end
	rec.p = 1
	local ok, _, classFile, _, raceFile, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok then return end
	if usable(classFile, "string") and classFile ~= "" then rec.oc = classFile end
	if usable(raceFile, "string") and raceFile ~= "" then rec.orc = raceFile end
	if usable(name, "string") and name ~= "" and not rec.o:find("-", 1, true) then
		if usable(realm, "string") and realm ~= "" then
			rec.o = name .. "-" .. realm
		else
			rec.o = name .. "-" .. myRealm
		end
	end
	local tguid = UnitGUID("target")
	if usable(tguid, "string") and tguid == guid then
		local level = UnitLevel("target")
		if usable(level, "number") then rec.ol = level end
	end
end

-- Record something that happened to us. kind: K, D, W or L. opponent: the other player's name.
-- guid: the opponent's GUID when known. streak/multikill: the counters after this event.
-- Called from the kill and death handlers, so a failure here must never reach them.
function H:Record(kind, opponent, guid, streak, multikill)
	local ok, err = pcall(H.RecordUnsafe, H, kind, opponent, guid, streak, multikill)
	--@debug@
	if not ok then dgks:Print("DEBUG: History record failed: " .. tostring(err)) end
	--@end-debug@
end

function H:RecordUnsafe(kind, opponent, guid, streak, multikill)
	if not KINDS[kind] or not usable(opponent, "string") or opponent == "" then return end
	if not myName then H:UpdateIdentity() end
	if not myName then return end

	local rec = { k = kind, t = now(), o = opponent:sub(1, 64), a = myName }
	opponentInfo(rec, guid)

	local _, classFile = UnitClass("player")
	if usable(classFile, "string") then rec.c = classFile end
	local level = UnitLevel("player")
	if usable(level, "number") then rec.l = level end
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

	-- Shared records get a place in our stream
	local store = dgks.db.profile.historyShare and guildStore(true)
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
	return name ~= nil and roster[name] == true
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

local function onLiveRecord(sender, raw)
	local rec = cleanRecord(raw)
	-- Only the author may announce a new record
	if not rec or rec.a ~= sender then return end
	if storeRecord(guildStore(true), rec) then H:NotifyChanged() end
end

function dgks:OnHistoryComm(prefix, message, distribution, sender)
	if prefix ~= PREFIX or not guildKey or not dgks.db.profile.historyShare then return end
	if isSecret(message) or isSecret(sender) or type(sender) ~= "string" then return end
	sender = H.FullName(sender)
	if sender == myName then return end
	local ok, op, gk, a, b, c, d = dgks:Deserialize(message)
	if not ok or gk ~= guildKey then return end

	if distribution == "GUILD" then
		if op == "R" then onLiveRecord(sender, a)
		elseif op == "S" then onSummary(sender, a, b, c) end
	elseif distribution == "WHISPER" and isMember(sender) then
		if op == "Q" then onRequest(sender, a)
		elseif op == "B" then onBatch(sender, a, b)
		elseif op == "E" then onEnd(sender, a, b) end
	end
end

-- Guild and identity ----------------------------------------------------------------------------

function H:UpdateIdentity()
	local name = UnitName("player")
	if usable(name, "string") and name ~= "" and name ~= UNKNOWNOBJECT then
		myRealm = realmName()
		myName = name .. "-" .. myRealm
	end
end

function H:UpdateGuild()
	local old = guildKey
	guildKey = nil
	if IsInGuild() then
		local gname, _, _, grealm = GetGuildInfo("player")
		if usable(gname, "string") and gname ~= "" then
			if not usable(grealm, "string") or grealm == "" then grealm = myRealm end
			guildKey = gname .. "-" .. grealm
		end
	end
	if guildKey ~= old then
		wipe(pending)
		nextSummaryAt = now() + SUMMARY_FIRST_DELAY
		H:NotifyChanged()
	end
end

function H:UpdateRoster()
	wipe(roster)
	if not IsInGuild() then return end
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local name = GetGuildRosterInfo(i)
		if usable(name, "string") then roster[H.FullName(name)] = true end
	end
end

-- Old data --------------------------------------------------------------------------------------

-- Copy the old killList/deathList (name -> list of "mm/dd/yy HH:MM:SS") into personal history once.
-- Those lists live in the shared profile, so they go to the first character that loads this version.
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
	if type(name) ~= "string" or name == "" then return nil end
	local n, realm = name:match("^([^%-]+)%-(.+)$")
	if not n then n, realm = name, defaultRealm or myRealm end
	if not realm then return nil end
	return n .. "-" .. realm:gsub("[%s%-]", "")
end

local function authorRealm(rec)
	return type(rec.a) == "string" and rec.a:match("%-(.+)$") or myRealm
end

local function buildCounts(records, into)
	for _, rec in ipairs(records) do
		if rec.k == "K" or rec.k == "D" then
			local key = H.PlayerKey(rec.o, authorRealm(rec))
			if key then
				local c = into[key]
				if not c then
					c = { K = 0, D = 0 }
					into[key] = c
				end
				c[rec.k] = c[rec.k] + 1
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
		buildCounts(H:GuildRecords(), cache.guild)
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
		dgks:Print("History sync is waiting until you leave combat or the instance.")
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
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end

	local lastPrune = now()
	C_Timer.NewTicker(2, function()
		if not guildKey then H:UpdateGuild() end
		if guildKey and now() >= nextSummaryAt then H:SendSummary() end
		flushQueue()
		if now() - lastPrune > 3600 then
			lastPrune = now()
			H:Prune()
		end
	end)
end
