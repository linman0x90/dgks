--@debug@
-- Battleground probe (development copies only: the packager comments this whole file out).
--
-- Kills in battlegrounds are missed on retail and Forever because PARTY_KILL hands addons secret
-- GUIDs there. This probe records which other signals still reach addon code, readable or secret,
-- so we can pick a way to capture battleground kills:
--   * PARTY_KILL itself: does it fire, and what can be done with its secret GUIDs
--   * the scoreboard's killing-blow count (C_PvP.GetScoreInfoByPlayerGuid, GetBattlefieldScore)
--   * the PvP session stats and the Killing blows / Honorable kills statistics
--   * honor and battleground chat messages
--   * the units around you at the moment of a kill: names, levels, dead or alive, health
--
-- /dgksprobe on       start logging (stays on across reloads until turned off)
-- /dgksprobe off      stop logging
-- /dgksprobe snap     log the units around you now
-- /dgksprobe status   say whether it is on and how many lines are logged
-- /dgksprobe clear    empty the log
--
-- The log is saved in dgksDB (WTF\Account\<account>\SavedVariables\dgks.lua, under global.bgprobe)
-- when you log out or /reload, so it can be read after a battleground.

local MAX_LINES = 2000
local SCORE_INTERVAL = 3 -- seconds between scoreboard requests in a battleground

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- A value as text: SECRET, nil, or the value (strings shortened)
local function show(v)
	if isSecret(v) then return "SECRET" end
	if v == nil then return "nil" end
	if type(v) == "string" then return #v > 60 and (v:sub(1, 60) .. "...") or v end
	if type(v) == "table" then return "table" end
	return tostring(v)
end

-- Calls fn and shows what came back: "missing", "error: ...", or the results
local function try(fn, ...)
	if type(fn) ~= "function" then return "missing" end
	local r = { pcall(fn, ...) }
	if not r[1] then return "error: " .. show(tostring(r[2])) end
	local out = {}
	for i = 2, math.min(#r, 7) do out[#out + 1] = show(r[i]) end
	return #out > 0 and table.concat(out, ", ") or "(nothing)"
end

-- The first result of fn when it is readable, else nil
local function readable(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or isSecret(v) then return nil end
	return v
end

local state -- dgks.db.global.bgprobe, once the database is loaded

local function log(fmt, ...)
	if not state or not state.on then return end
	local line = ("%s %.1f  " .. fmt):format(date("%H:%M:%S"), GetTime(), ...)
	local lines = state.log
	lines[#lines + 1] = line
	while #lines > MAX_LINES do table.remove(lines, 1) end
end

local function say(msg)
	print("|cffff8000dgks probe:|r " .. msg)
end

local function inPvPInstance()
	local _, kind = IsInInstance()
	return not isSecret(kind) and (kind == "pvp" or kind == "arena"), kind
end

-- Units around us ---------------------------------------------------------------------------------

local SNAP_UNITS = { "target", "focus", "mouseover", "softenemy" }
for i = 1, 40 do SNAP_UNITS[#SNAP_UNITS + 1] = "nameplate" .. i end

-- One line per player unit around us: what each check returns, readable or secret
local function snapshot(reason)
	log("SNAP %s", reason)
	local count = 0
	for _, unit in ipairs(SNAP_UNITS) do
		-- A secret answer counts as "maybe", so it is logged too
		local ok, exists = pcall(UnitExists, unit)
		if ok and (isSecret(exists) or exists) then
			local isPlayer = select(2, pcall(UnitIsPlayer, unit))
			if isSecret(isPlayer) or isPlayer then
				count = count + 1
				log("  %s: exists=%s player=%s enemy=%s name=%s level=%s dead=%s deadOrGhost=%s health=%s/%s guid=%s targetIsMe=%s",
					unit, try(UnitExists, unit), show(isPlayer), try(UnitCanAttack, "player", unit), try(UnitName, unit),
					try(UnitLevel, unit), try(UnitIsDead, unit), try(UnitIsDeadOrGhost, unit), try(UnitHealth, unit),
					try(UnitHealthMax, unit), try(UnitGUID, unit), try(UnitIsUnit, unit .. "target", "player"))
			end
		end
	end
	log("  %d player units", count)
end

-- Scoreboard, session stats, statistics -----------------------------------------------------------

local last = {} -- last readable values, to log changes only

local function myScore()
	local guid = UnitGUID("player")
	if C_PvP and C_PvP.GetScoreInfoByPlayerGuid then
		local ok, info = pcall(C_PvP.GetScoreInfoByPlayerGuid, guid)
		if not ok then return "error: " .. show(tostring(info)) end
		if isSecret(info) then return "SECRET table" end
		if type(info) == "table" then
			return ("kb=%s hk=%s deaths=%s honor=%s name=%s"):format(show(info.killingBlows), show(info.honorableKills),
				show(info.deaths), show(info.honorGained), show(info.name)), info.killingBlows
		end
		return "no row (" .. show(info) .. ")"
	end
	return "C_PvP.GetScoreInfoByPlayerGuid missing"
end

-- The old scoreboard API: find our row and show it
local function myOldScore()
	local n = readable(GetNumBattlefieldScores)
	if type(n) ~= "number" then return "GetNumBattlefieldScores: " .. try(GetNumBattlefieldScores) end
	local me = UnitName("player")
	for i = 1, n do
		local ok, name, kb, hk, deaths = pcall(GetBattlefieldScore, i)
		if not ok then return "GetBattlefieldScore error: " .. show(tostring(name)) end
		if isSecret(name) then return ("row %d name SECRET, kb=%s"):format(i, show(kb)) end
		if type(name) == "string" and (name == me or name:match("^([^%-]+)") == me) then
			return ("row %d of %d: kb=%s hk=%s deaths=%s"):format(i, n, show(kb), show(hk), show(deaths))
		end
	end
	return ("%d rows, ours not found"):format(n)
end

local function checkScore(reason)
	local text, kb = myScore()
	local old = myOldScore()
	local line = text .. " | old API: " .. old
	if line ~= last.score then
		log("SCORE (%s) %s", reason, line)
		last.score = line
	end
	if type(kb) == "number" and not isSecret(kb) then
		if last.kb and kb > last.kb then
			log("KILLING BLOW: scoreboard kb %d -> %d", last.kb, kb)
			say(("scoreboard killing blows %d -> %d"):format(last.kb, kb))
			snapshot("scoreboard kb up")
		end
		last.kb = kb
	end
end

-- Statistics whose names mention killing blows or honorable kills, found by name once
local stats

local function findStats()
	stats = {}
	local ok, cats = pcall(GetStatisticsCategoryList)
	if not ok or type(cats) ~= "table" then
		log("STATS: GetStatisticsCategoryList %s", ok and show(cats) or ("error: " .. show(tostring(cats))))
		return
	end
	for _, cat in ipairs(cats) do
		local n = readable(GetCategoryNumAchievements, cat) or 0
		for i = 1, n do
			local id, name = select(2, pcall(GetAchievementInfo, cat, i))
			if type(name) == "string" and not isSecret(name)
				and (name:find("[Kk]illing [Bb]low") or name:find("[Hh]onorable [Kk]ill")) then
				stats[#stats + 1] = { id = id, name = name }
			end
		end
	end
	log("STATS: %d found", #stats)
end

local function checkStats(reason)
	if not stats then findStats() end
	local parts = {}
	for _, s in ipairs(stats) do parts[#parts + 1] = ("%s [%s]=%s"):format(s.name, show(s.id), try(GetStatistic, s.id)) end
	parts[#parts + 1] = "session=" .. try(GetPVPSessionStats)
	local line = table.concat(parts, "; ")
	if line ~= last.stats then
		log("STATS (%s) %s", reason, line)
		last.stats = line
	end
end

-- Events ------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
local ticker

local function startTicker()
	if ticker or not C_Timer or not C_Timer.NewTicker then return end
	ticker = C_Timer.NewTicker(SCORE_INTERVAL, function()
		if not state or not state.on or not inPvPInstance() then return end
		pcall(RequestBattlefieldScoreData)
	end)
end

local function where(reason)
	local pvp, kind = inPvPInstance()
	log("WHERE (%s) instance=%s zone=%s isBattleground=%s issecretvalue=%s", reason, show(kind),
		try(GetRealZoneText), C_PvP and try(C_PvP.IsBattleground) or "missing", tostring(issecretvalue ~= nil))
	if pvp then
		pcall(RequestBattlefieldScoreData)
		checkStats("entered")
	end
end

function handlers.PLAYER_ENTERING_WORLD() last = {}; where("entering world") end
function handlers.ZONE_CHANGED_NEW_AREA() where("zone change") end

function handlers.PARTY_KILL(attacker, victim)
	log("PARTY_KILL attacker=%s victim=%s", show(attacker), show(victim))
	-- What can be done with the GUIDs when they are secret?
	local me = UnitGUID("player")
	log("  attacker==me: %s", try(function() return attacker == me end))
	log("  UnitNameFromGUID(victim)=%s  GetPlayerInfoByGUID(victim)=%s", try(UnitNameFromGUID, victim), try(GetPlayerInfoByGUID, victim))
	log("  UnitTokenFromGUID(victim)=%s  UnitTokenFromGUID(attacker)=%s", try(UnitTokenFromGUID, victim), try(UnitTokenFromGUID, attacker))
	log("  GUIDIsPlayer(victim)=%s  IsGUIDInGroup(attacker)=%s", C_PlayerInfo and try(C_PlayerInfo.GUIDIsPlayer, victim) or "missing",
		try(IsGUIDInGroup, attacker))
	say("PARTY_KILL" .. ((isSecret(attacker) or isSecret(victim)) and " (secret GUIDs)" or ""))
	snapshot("PARTY_KILL")
	checkStats("PARTY_KILL")
	pcall(RequestBattlefieldScoreData)
end

function handlers.UPDATE_BATTLEFIELD_SCORE() checkScore("scoreboard update") end

function handlers.PLAYER_PVP_KILLS_CHANGED(unit)
	log("PLAYER_PVP_KILLS_CHANGED unit=%s", show(unit))
	checkStats("pvp kills changed")
end

local criteriaAt = 0
function handlers.CRITERIA_UPDATE()
	-- Fires often; check the statistics at most once a second
	if GetTime() - criteriaAt < 1 then return end
	criteriaAt = GetTime()
	checkStats("criteria update")
end

local function chat(event)
	return function(msg) log("%s %s", event, show(msg)) end
end
for _, e in ipairs({ "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
	"CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_COMBAT_XP_GAIN" }) do
	handlers[e] = chat(e)
end
local honorChat = handlers.CHAT_MSG_COMBAT_HONOR_GAIN
handlers.CHAT_MSG_COMBAT_HONOR_GAIN = function(msg)
	honorChat(msg)
	snapshot("honor gain")
end

function handlers.PLAYER_DEAD() log("PLAYER_DEAD"); checkScore("we died") end

frame:SetScript("OnEvent", function(_, event, ...)
	if not state or not state.on or not handlers[event] then return end
	local ok, err = pcall(handlers[event], ...)
	if not ok then log("ERROR in %s: %s", event, show(tostring(err))) end
end)

-- Registers every event the probe uses; returns the ones the game refused
local function register()
	local refused = {}
	for e in pairs(handlers) do
		if not pcall(frame.RegisterEvent, frame, e) then refused[#refused + 1] = e end
	end
	return refused
end

local function start()
	local refused = register()
	if #refused > 0 then log("REFUSED events: %s", table.concat(refused, ", ")) end
	-- No test of the combat log here: it is closed to addons on retail, and touching its registration is
	-- a protected action (ADDON_ACTION_FORBIDDEN), which pcall cannot catch
	log("C_DamageMeter: %s", type(C_DamageMeter) == "table" and "present" or "missing")
	startTicker()
	where("probe started")
end

-- Setup -------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if not (dgks and dgks.db and dgks.db.global) then return end
	dgks.db.global.bgprobe = dgks.db.global.bgprobe or { on = false, log = {} }
	state = dgks.db.global.bgprobe
	state.log = state.log or {}
	if state.on then
		start()
		say(("on, %d lines logged. /dgksprobe off to stop."):format(#state.log))
	end
end)

SLASH_DGKSPROBE1 = "/dgksprobe"
SlashCmdList.DGKSPROBE = function(msg)
	if not state then say("the database is not loaded yet") return end
	local cmd = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
	if cmd == "on" then
		state.on = true
		log("PROBE ON (%s)", try(GetBuildInfo))
		start()
		say("on. Play a battleground, then /reload or log out to save the log.")
	elseif cmd == "off" then
		log("PROBE OFF")
		state.on = false
		say(("off, %d lines logged."):format(#state.log))
	elseif cmd == "snap" then
		if not state.on then say("turn it on first: /dgksprobe on") return end
		snapshot("manual")
		checkScore("manual")
		checkStats("manual")
		say("logged the units around you, the scoreboard and the statistics")
	elseif cmd == "clear" then
		wipe(state.log)
		last = {}
		say("log cleared")
	else
		say(("%s, %d lines logged. Commands: on, off, snap, status, clear"):format(state.on and "on" or "off", #state.log))
	end
end
--@end-debug@
