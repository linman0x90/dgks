--@debug@
-- Battleground probe (development copies only: the packager comments this whole file out).
--
-- Kills in battlegrounds are missed on retail and Forever because PARTY_KILL hands addons secret
-- GUIDs there. This probe records which other signals still reach addon code, readable or secret,
-- so we can pick a way to capture battleground kills.
--
-- The first run (Forever, Alterac Valley) found: PARTY_KILL fires with secret GUIDs; the Battleground
-- Killing Blows statistic is readable and rises in the same instant when the kill is ours; enemy names
-- and levels are readable; the scoreboard is secret until the battle ends. So for each PARTY_KILL this
-- version logs:
--   * whether it was ours: did Battleground Killing Blows rise
--   * the enemy players around us then, and at +0.25, 0.5, 1 and 2 seconds which of them is dead,
--     to see whether the victim can be named
--   * a VERDICT line: ours or a groupmate's, and the victim if exactly one candidate died
--   * every player nameplate that goes away (NAME_PLATE_UNIT_REMOVED): name, enemy, dead or alive
--     then; the VERDICT lists the enemy plates that vanished dead from 1 s before the kill to 2 s after
--   * Blizzard's damage meter (C_DamageMeter) each time we leave combat: the Deaths, EnemyDamageTaken,
--     DamageDone and DamageTaken views (names, classes, death times, recap IDs), our own spell
--     breakdowns (whom we hit, who hit us, deadly spells), and the Death Recap of each death listed
-- It also keeps logging the scoreboard, statistics, honor and battleground chat, and our deaths.
-- Only battlegrounds and arenas are logged (and where we are, everywhere).
--
-- /dgksprobe on       start logging (stays on across reloads until turned off)
-- /dgksprobe off      stop logging
-- /dgksprobe snap     log the units around you and the damage meter now
-- /dgksprobe status   say whether it is on and how many lines are logged
-- /dgksprobe clear    empty the log
--
-- The log is saved in dgksDB (WTF\Account\<account>\SavedVariables\dgks.lua, under global.bgprobe)
-- when you log out or /reload, so it can be read after a battleground.

local MAX_LINES = 5000
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

-- The statistics the first run found readable in a battleground (ids from that log)
local KB_STAT = 1491 -- Battleground Killing Blows
local STATS = {
	{ id = 1487, name = "Total KB" }, { id = 1488, name = "World KB" }, { id = KB_STAT, name = "BG KB" },
	{ id = 588, name = "Total HK" }, { id = 382, name = "BG HK" },
}

-- A statistic as a number: GetStatistic returns text, "--" before the first one
local function statValue(id)
	local v = readable(GetStatistic, id)
	if type(v) == "string" then return tonumber(v:match("^%d+")) or 0 end
	return type(v) == "number" and v or nil
end

local function checkStats(reason)
	local parts = {}
	for _, s in ipairs(STATS) do parts[#parts + 1] = ("%s=%s"):format(s.name, show(statValue(s.id))) end
	parts[#parts + 1] = "session=" .. try(GetPVPSessionStats)
	local line = table.concat(parts, " ")
	if line ~= last.stats then
		log("STATS (%s) %s", reason, line)
		last.stats = line
	end
	-- A rise in battleground killing blows, with the time it was seen
	local kb = statValue(KB_STAT)
	if kb and last.kbStat and kb > last.kbStat then last.kbRiseAt = GetTime() end
	if kb then last.kbStat = kb end
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

-- Enemy players around us right now, by unit: { unit, name, level }. The first run found names and
-- levels readable in a battleground, and the victim usually our target or soft target.
local CANDIDATE_UNITS = { "target", "softenemy", "focus", "mouseover" }
for i = 1, 40 do CANDIDATE_UNITS[#CANDIDATE_UNITS + 1] = "nameplate" .. i end

local function enemyPlayers()
	local found, seen = {}, {}
	for _, unit in ipairs(CANDIDATE_UNITS) do
		if readable(UnitExists, unit) and readable(UnitIsPlayer, unit) and readable(UnitCanAttack, "player", unit) then
			local name = readable(UnitName, unit)
			if type(name) == "string" and not seen[name] then
				seen[name] = true
				found[#found + 1] = { unit = unit, name = name, level = readable(UnitLevel, unit) }
			end
		end
	end
	return found
end

-- Dead or alive, read again after a delay: is the unit still the same player, and dead now?
local FOLLOW_UPS = { 0.25, 0.5, 1, 2 }

-- Player nameplates that went away, newest last: { t, name, enemy, dead }. A dead player's plate
-- should vanish, and the unit can still be asked about while NAME_PLATE_UNIT_REMOVED runs, so this
-- may confirm the victim better than our target, which no longer shows them a moment later.
local plates = {}
local PLATE_WINDOW = 1 -- seconds before a kill a plate may have gone and still count

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
	if isSecret(unit) or type(unit) ~= "string" then log("PLATE GONE unit=%s", show(unit)) return end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if ok and isPlayer == false then return end -- NPCs: too many in a battleground
	local name = readable(UnitName, unit)
	local enemy = readable(UnitCanAttack, "player", unit)
	local dead = readable(UnitIsDeadOrGhost, unit)
	log("PLATE GONE %s name=%s player=%s enemy=%s dead=%s deadOrGhost=%s health=%s", unit, try(UnitName, unit),
		show(isPlayer), try(UnitCanAttack, "player", unit), try(UnitIsDead, unit), try(UnitIsDeadOrGhost, unit), try(UnitHealth, unit))
	if type(name) == "string" then
		plates[#plates + 1] = { t = GetTime(), name = name, enemy = enemy, dead = dead == true }
		if #plates > 60 then table.remove(plates, 1) end
	end
end

-- Enemy plates that vanished dead around a kill: "Name(+0.12s)" relative to the PARTY_KILL
local function deadPlates(kill)
	local found = {}
	for _, p in ipairs(plates) do
		if p.dead and p.enemy ~= false and p.t >= kill.t - PLATE_WINDOW and p.t <= kill.t + FOLLOW_UPS[#FOLLOW_UPS] then
			found[#found + 1] = { name = p.name, text = ("%s(%+.2fs)"):format(p.name, p.t - kill.t) }
		end
	end
	return found
end

local function followUp(kill, delay)
	local parts = {}
	for _, c in ipairs(kill.candidates) do
		local name = readable(UnitName, c.unit)
		if name ~= c.name then
			parts[#parts + 1] = c.name .. "=gone"
		else
			parts[#parts + 1] = ("%s=%s"):format(c.name, (readable(UnitIsDeadOrGhost, c.unit) == true) and "DEAD"
				or ("alive(" .. try(UnitIsDeadOrGhost, c.unit) .. ")"))
		end
	end
	-- Anyone dead now who was not a candidate?
	for _, e in ipairs(enemyPlayers()) do
		if readable(UnitIsDeadOrGhost, e.unit) == true and not kill.names[e.name] then
			parts[#parts + 1] = e.name .. "=DEAD(new, " .. e.unit .. ")"
		end
	end
	local kb = statValue(KB_STAT)
	local ours = kb and kill.kbBefore and kb > kill.kbBefore
	log("  +%.2fs kill #%d: BG KB %s -> %s (%s) | %s", delay, kill.n, show(kill.kbBefore), show(kb),
		ours and "OURS" or "not ours", #parts > 0 and table.concat(parts, ", ") or "no enemy players around")
	if delay == FOLLOW_UPS[#FOLLOW_UPS] then
		local dead = {}
		for _, p in ipairs(parts) do if p:find("=DEAD") then dead[#dead + 1] = p:match("^(.-)=") end end
		local gone, goneText = deadPlates(kill), {}
		for _, p in ipairs(gone) do goneText[#goneText + 1] = p.text end
		log("  VERDICT kill #%d: %s, victim %s | plates gone dead: %s", kill.n, ours and "OURS" or "a groupmate's",
			#dead == 1 and dead[1] or #dead == 0 and "not seen dead" or ("one of " .. table.concat(dead, "/")),
			#goneText > 0 and table.concat(goneText, ", ") or "none")
		local victim = #dead == 1 and dead[1] or #gone == 1 and (gone[1].name .. " (plate)") or "victim unclear"
		if ours then say(("your kill #%d: %s"):format(kill.n, victim)) end
	end
end

local killCount = 0
function handlers.PARTY_KILL(attacker, victim)
	killCount = killCount + 1
	-- The statistic before this kill: the last value seen, unless it rose in the last half second
	-- (CRITERIA_UPDATE may have been handled first), in which case one less
	local kbBefore = last.kbStat
	if kbBefore and last.kbRiseAt and GetTime() - last.kbRiseAt < 0.5 then kbBefore = kbBefore - 1 end
	local candidates = enemyPlayers()
	local kill = { n = killCount, t = GetTime(), kbBefore = kbBefore, candidates = candidates, names = {} }
	local list = {}
	for _, c in ipairs(candidates) do
		kill.names[c.name] = true
		list[#list + 1] = ("%s %s (%s)"):format(show(c.level), c.name, c.unit)
	end
	log("PARTY_KILL #%d attacker=%s victim=%s | BG KB now %s | enemies: %s", killCount, show(attacker), show(victim),
		show(statValue(KB_STAT)), #list > 0 and table.concat(list, ", ") or "none")
	checkStats("PARTY_KILL")
	-- A rise belongs to one kill: this one, if any, so the next PARTY_KILL cannot claim it too
	last.kbRiseAt = nil
	for _, delay in ipairs(FOLLOW_UPS) do
		C_Timer.After(delay, function()
			local ok, err = pcall(followUp, kill, delay)
			if not ok then log("ERROR in follow-up: %s", show(tostring(err))) end
		end)
	end
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
function handlers.PLAYER_DEAD() log("PLAYER_DEAD"); checkScore("we died") end

-- Damage meter (C_DamageMeter) -------------------------------------------------------------------
-- Blizzard's meter keeps Deaths and EnemyDamageTaken views whose entries carry a name, class, death
-- time and death recap ID, and spell breakdowns naming the other unit, with overkill and "deadly"
-- flags. Its data is documented as secret in combat, so it is dumped when we leave combat: does it
-- name our victims, and through each death's recap, their killers?

-- A field of a table that may be secret, or nil
local function field(t, k)
	if t == nil or isSecret(t) or type(t) ~= "table" then return nil end
	local ok, v = pcall(function() return t[k] end)
	if ok then return v end
end

-- The items of an array that may be secret, as a plain list
local function items(t)
	local out = {}
	if type(t) ~= "table" or isSecret(t) then return out end
	pcall(function() for i, v in ipairs(t) do out[i] = v end end)
	return out
end

local function meterType(name, fallback)
	local enum = Enum and Enum.DamageMeterType
	return enum and enum[name] or fallback
end

local function sessionType(name, fallback)
	local enum = Enum and Enum.DamageMeterSessionType
	return enum and enum[name] or fallback
end

local function sourceLine(src)
	return ("%s class=%s total=%s local=%s display=%s deathTime=%s recapID=%s guid=%s"):format(
		show(field(src, "name")), show(field(src, "classFilename")), show(field(src, "totalAmount")),
		show(field(src, "isLocalPlayer")), show(field(src, "sourceDisplayType")), show(field(src, "deathTimeSeconds")),
		show(field(src, "deathRecapID")), show(field(src, "sourceGUID")))
end

-- What the Death Recap says about one death: the killing blow (event 1) and how many events
local function recapLine(id)
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return "no C_DeathRecap" end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
	if not ok then return "error: " .. show(tostring(events)) end
	if isSecret(events) then return "SECRET" end
	if type(events) ~= "table" then return show(events) end
	local list = items(events)
	local ev = list[1]
	return ("%d events; killing blow: source=%s spell=%s amount=%s overkill=%s hideCaster=%s"):format(#list,
		show(field(ev, "sourceName")), show(field(ev, "spellName")), show(field(ev, "amount")),
		show(field(ev, "overkill")), show(field(ev, "hideCaster")))
end

-- One view of one session. keep(src, i) decides which entries get a line; recaps adds each death's recap.
local function dumpSession(label, sType, mType, keep, recaps)
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sType, mType)
	if not ok then log("METER %s: error: %s", label, show(tostring(session))) return {} end
	if isSecret(session) or session == nil then log("METER %s: %s", label, show(session)) return {} end
	local sources = items(field(session, "combatSources"))
	log("METER %s: %d entries, total=%s duration=%s", label, #sources, show(field(session, "totalAmount")),
		show(field(session, "durationSeconds")))
	for i, src in ipairs(sources) do
		if keep(src, i) then
			log("  %s", sourceLine(src))
			local id = field(src, "deathRecapID")
			if recaps and id ~= nil and not isSecret(id) then log("    recap: %s", recapLine(id)) end
		end
	end
	return sources
end

-- Our own spell breakdown in one view: whom we hit (DamageDone) or who hit us (DamageTaken)
local function dumpOwnSpells(label, sType, mType, sources)
	local guid
	for _, src in ipairs(sources) do
		if field(src, "isLocalPlayer") == true then guid = field(src, "sourceGUID") end
	end
	if guid == nil or isSecret(guid) then guid = UnitGUID("player") end
	local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sType, mType, guid)
	if not ok then log("METER %s spells: error: %s", label, show(tostring(source))) return end
	if isSecret(source) or source == nil then log("METER %s spells: %s", label, show(source)) return end
	local spells = items(field(source, "combatSpells"))
	log("METER %s spells: %d", label, #spells)
	for i, spell in ipairs(spells) do
		if i > 8 then break end
		local details, units = field(spell, "combatSpellDetails"), {}
		-- One unit or a list of them
		local list = field(details, "unitName") ~= nil and { details } or items(details)
		for j, d in ipairs(list) do
			if j > 5 then break end
			units[#units + 1] = ("%s(%s, %s)"):format(show(field(d, "unitName")), show(field(d, "unitClassFilename")), show(field(d, "amount")))
		end
		log("    spell=%s creature=%s total=%s overkill=%s deadly=%s units: %s", show(field(spell, "spellID")),
			show(field(spell, "creatureName")), show(field(spell, "totalAmount")), show(field(spell, "overkillAmount")),
			show(field(spell, "isDeadly")), #units > 0 and table.concat(units, ", ") or "none")
	end
end

local meterDumpAt = -100
local function dumpMeter(reason)
	if type(C_DamageMeter) ~= "table" then log("METER (%s): C_DamageMeter missing", reason) return end
	if GetTime() - meterDumpAt < 3 then return end
	meterDumpAt = GetTime()
	log("METER DUMP (%s) available=%s inCombat=%s sessions=%s", reason, try(C_DamageMeter.IsDamageMeterAvailable),
		try(InCombatLockdown), try(function() return #C_DamageMeter.GetAvailableCombatSessions() end))
	local current, overall = sessionType("Current", 1), sessionType("Overall", 0)
	local all = function() return true end
	dumpSession("Deaths/current", current, meterType("Deaths", 9), all, true)
	-- The whole battleground's deaths: the last 10 entries only, without recaps
	local deaths = dumpSession("Deaths/overall", overall, meterType("Deaths", 9), function() return false end)
	for i = math.max(1, #deaths - 9), #deaths do log("  %s", sourceLine(deaths[i])) end
	dumpSession("EnemyDamageTaken/current", current, meterType("EnemyDamageTaken", 10), function(src, i)
		return i <= 10 or field(src, "deathTimeSeconds") ~= nil
	end, true)
	local done = dumpSession("DamageDone/current", current, meterType("DamageDone", 0), function(src)
		return field(src, "isLocalPlayer") == true
	end)
	dumpOwnSpells("DamageDone/current", current, meterType("DamageDone", 0), done)
	local taken = dumpSession("DamageTaken/current", current, meterType("DamageTaken", 7), function(src)
		return field(src, "isLocalPlayer") == true
	end)
	dumpOwnSpells("DamageTaken/current", current, meterType("DamageTaken", 7), taken)
end

function handlers.PLAYER_REGEN_ENABLED() dumpMeter("left combat") end

function handlers.DAMAGE_METER_COMBAT_SESSION_UPDATED(...)
	log("DAMAGE_METER_COMBAT_SESSION_UPDATED %s", try(function(...) return ... end, ...))
	if readable(InCombatLockdown) == false then dumpMeter("session updated, out of combat") end
end

-- Fires on every update while fighting: only count them, and log the count now and then
local currentUpdates, currentLoggedAt = 0, 0
function handlers.DAMAGE_METER_CURRENT_SESSION_UPDATED()
	currentUpdates = currentUpdates + 1
	if GetTime() - currentLoggedAt >= 30 then
		log("DAMAGE_METER_CURRENT_SESSION_UPDATED x%d", currentUpdates)
		currentUpdates, currentLoggedAt = 0, GetTime()
	end
end

function handlers.DAMAGE_METER_RESET() log("DAMAGE_METER_RESET") end

-- Outside battlegrounds and arenas only where we are is logged, so the log keeps room for the fights
local ALWAYS = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true }

frame:SetScript("OnEvent", function(_, event, ...)
	if not state or not state.on or not handlers[event] then return end
	if not ALWAYS[event] and not inPvPInstance() then return end
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
		meterDumpAt = -100
		dumpMeter("manual")
		say("logged the units around you, the scoreboard, the statistics and the damage meter")
	elseif cmd == "clear" then
		wipe(state.log)
		last = {}
		say("log cleared")
	else
		say(("%s, %d lines logged. Commands: on, off, snap, status, clear"):format(state.on and "on" or "off", #state.log))
	end
end
--@end-debug@
