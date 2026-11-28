-- Our kills in battlegrounds, where the game hides the killer and the victim (retail and Forever).
--
-- Inside a battleground PARTY_KILL hands addons secret GUIDs: we cannot tell whose kill it was or
-- who died. Two statistics stay readable there, and a probe in Alterac Valley (Forever) showed how
-- they move:
--   * Battleground Killing Blows rises in the same instant as PARTY_KILL when the killing blow is
--     ours, on players and on NPCs alike. A groupmate's kill does not move it.
--   * Total Honorable Kills rises about 0.1 seconds later when the one we killed was a player
--     worth honor. An NPC kill does not move it.
-- The victim's GUID is secret too, but the name and level of our target are readable, and on every
-- player kill in the probe our target was the only enemy player around. So a killing blow on a
-- player is recorded as a kill of our target (or soft target), marked as likely.
--
-- Not covered: a groupmate's kill (both names stay hidden), a kill with no enemy player targeted, a
-- kill worth no honor (a player far below our level), and arenas (other statistics, not probed).

local B = {}
dgks.BGKills = B

local KB_STAT = 1491 -- Battleground Killing Blows
local HK_STAT = 588  -- Total Honorable Kills
local DELAY = 0.6    -- seconds: the honorable kill arrives about 0.1 s after PARTY_KILL
local CANDIDATE_UNITS = { "target", "softenemy" }

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- The first result of fn when it is readable, else nil
local function readable(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or isSecret(v) then return nil end
	return v
end

-- A statistic as a number. GetStatistic returns text: "--" before the first one, "0" style after.
local function statValue(id)
	local v = readable(GetStatistic, id)
	if type(v) == "string" then return tonumber(v:match("^%d+")) or 0 end
	if type(v) == "number" then return v end
	return nil
end

local function inBattleground()
	local ok, _, instanceType = pcall(IsInInstance)
	return ok and not isSecret(instanceType) and instanceType == "pvp"
end

-- Killing blows counted so far: each rise of the statistic is one of our kills, claimed once
local kbBase
-- Enemy players whose nameplate went away dead (see onPlateRemoved)
local deadPlates = {}

-- Start counting from the current value: on entering or leaving a zone
function B:Reset()
	kbBase = statValue(KB_STAT)
	deadPlates = {}
end

-- Step-by-step notes for the battleground probe (dgks_bgprobe.lua sets B.trace while it logs)
local function trace(fmt, ...)
	if B.trace then pcall(B.trace, fmt:format(...)) end
end

-- An enemy player unit as { unit, name = "Name-Realm" (Forever: "First Surname-Realm"), level,
-- class }, or nil and why not. Names and levels stay readable in battlegrounds; GUIDs do not.
-- leaving: the unit's nameplate is going away. The probe read name, player, enemy and dead state
-- then, but never asked whether the unit still exists, so that is not required.
local function enemyPlayer(unit, leaving)
	if not leaving and readable(UnitExists, unit) ~= true then return nil, "no unit" end
	if readable(UnitIsPlayer, unit) ~= true then return nil, "not a player" end
	if readable(UnitCanAttack, "player", unit) ~= true then return nil, "not an enemy" end
	local ok, name, realm = pcall(UnitName, unit)
	if not ok or isSecret(name) or isSecret(realm) then return nil, "name hidden" end
	name, realm = dgks.SplitName(name, realm) -- Forever: "First Surname", no realm
	if not name then return nil, "no name" end
	realm = realm or dgks.RealmName()
	local level = readable(UnitLevel, unit)
	local ok2, _, classFile = pcall(UnitClass, unit)
	if not ok2 or isSecret(classFile) or type(classFile) ~= "string" then classFile = nil end
	return {
		unit = unit,
		name = realm and (name .. "-" .. realm) or name,
		level = type(level) == "number" and level or nil,
		class = classFile,
	}
end

-- The enemy player we are fighting: our target, else our soft target
local function candidate()
	for _, unit in ipairs(CANDIDATE_UNITS) do
		local p = enemyPlayer(unit)
		if p then return p end
	end
	return nil
end

-- Is this candidate still alive and on the same unit? A victim drops off our target as they die
-- (the probe saw that within a quarter of a second), so a candidate still there and alive was not
-- killed: the kill was someone else's, or an NPC's.
local function stillAlive(c)
	local ok, name, realm = pcall(UnitName, c.unit)
	if not ok or isSecret(name) or isSecret(realm) then return false end
	name, realm = dgks.SplitName(name, realm)
	if not name then return false end
	realm = realm or dgks.RealmName()
	if (realm and (name .. "-" .. realm) or name) ~= c.name then return false end
	return readable(UnitIsDeadOrGhost, c.unit) == false
end

-- Enemy players whose nameplate went away while they were dead: { t, name, level, class }, newest
-- last. A probe in Alterac Valley (Forever) saw the victim's plate vanish 0.1-0.3 s after each of
-- our kills with UnitIsDeadOrGhost readable and true; plates of players who only walked out of
-- view read false. Each one is claimed by one kill at most.
local PLATE_BEFORE, PLATE_AFTER = 0.3, DELAY -- the window around a kill, in seconds

local function onPlateRemoved(unit)
	if isSecret(unit) or type(unit) ~= "string" or not inBattleground() then return end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if ok and isPlayer == false then return end -- NPC plates: many, and never a victim we want
	local dead = readable(UnitIsDeadOrGhost, unit)
	local p, why = enemyPlayer(unit, true)
	if not p then
		trace("plate %s gone: ignored (%s)", unit, why)
		return
	end
	if dead ~= true then
		trace("plate %s gone: %s, alive (%s)", unit, p.name, dead == nil and "dead state hidden" or "left view")
		return
	end
	p.t = GetTime()
	deadPlates[#deadPlates + 1] = p
	while #deadPlates > 40 do table.remove(deadPlates, 1) end
	trace("plate %s gone: %s, DEAD, kept", unit, p.name)
end

local plateFrame = CreateFrame("Frame")
pcall(plateFrame.RegisterEvent, plateFrame, "NAME_PLATE_UNIT_REMOVED")
plateFrame:SetScript("OnEvent", function(_, _, unit) pcall(onPlateRemoved, unit) end)
B.OnPlateRemoved = onPlateRemoved -- for tests

-- The dead plates in a kill's window, oldest first, not yet claimed by another kill
local function platesAround(t)
	local found = {}
	for _, p in ipairs(deadPlates) do
		if not p.claimed and p.t >= t - PLATE_BEFORE and p.t <= t + PLATE_AFTER then found[#found + 1] = p end
	end
	return found
end

-- Decides, a moment after a hidden PARTY_KILL, whether it was our killing blow on a player, and who died
local function settle(kill)
	local kb = statValue(KB_STAT)
	if not kb or not kbBase then trace("kill #%d: killing blows not readable", kill.n) return end
	if kb <= kbBase then
		kbBase = kb -- a groupmate's kill (and keep in step if the statistic ever went down)
		trace("kill #%d: not ours (killing blows still %d)", kill.n, kb)
		return
	end
	kbBase = kbBase + 1 -- ours: claim one rise, so a second kill in the same moment gets the next
	local plates = platesAround(kill.t)
	local hk = statValue(HK_STAT)
	local honor = hk and kill.hk and hk > kill.hk
	local names = {}
	for _, p in ipairs(plates) do names[#names + 1] = ("%s(%+.2fs)"):format(p.name, p.t - kill.t) end
	local target = kill.victim
	local targetAlive = target and stillAlive(target)
	trace("kill #%d: ours; honor %s; dead plates: %s; target: %s", kill.n, honor and "yes" or "no",
		#names > 0 and table.concat(names, ", ") or "none",
		target and (target.name .. (targetAlive and " (still alive)" or " (gone or dead)")) or "none")
	-- The victim: our target if their plate vanished dead (confirmed); else the first enemy whose
	-- plate vanished dead; else, with an honorable kill, our target if they are no longer there alive.
	-- An honorable kill alone is not enough: a groupmate's player kill nearby gives us honor too, at
	-- the same moment as our own kill of an NPC.
	local victim, confirmed
	if target then
		for _, p in ipairs(plates) do
			if p.name == target.name then victim, confirmed = p, true break end
		end
	end
	if not victim then victim = plates[1] end
	if not victim and honor and target and not targetAlive then victim = target end
	if not victim then
		trace("kill #%d: not recorded (%s)", kill.n, honor and (target and "target still alive" or "nobody to name")
			or "no honor and no dead plate: an NPC")
		return
	end
	victim.claimed = true
	local sameAsTarget = target and target.name == victim.name
	local flags = { level = victim.level or (sameAsTarget and target.level) or nil,
		class = victim.class or (sameAsTarget and target.class) or nil }
	if not confirmed then flags.guessed = 1 end
	trace("kill #%d: recorded %s%s", kill.n, victim.name, confirmed and " (confirmed)" or " (likely)")
	dgks:KillshotTX(victim.name, kill.t, nil, flags)
end

-- PARTY_KILL with secret GUIDs. Takes a note now, while our target is still the victim and the
-- honorable kill has not arrived, and settles it after DELAY.
local killCount = 0
function B:OnHiddenKill()
	if not inBattleground() then return end
	if not kbBase then
		-- No starting point yet (the statistic was not readable when we zoned in): start now. This
		-- kill may already be counted in it, so it is let go.
		B:Reset()
		trace("hidden kill: no killing-blow count to compare with yet; starting from now")
		return
	end
	killCount = killCount + 1
	local kill = { n = killCount, t = GetTime(), hk = statValue(HK_STAT), victim = candidate() }
	trace("kill #%d: hidden kill; target %s", kill.n, kill.victim and kill.victim.name or "none")
	C_Timer.After(DELAY, function()
		local ok, err = pcall(settle, kill)
		if not ok then trace("kill #%d failed: %s", kill.n, tostring(err)) end
		--@debug@
		if not ok then dgks:Print("DEBUG: battleground kill failed: " .. tostring(err)) end
		--@end-debug@
	end)
end

-- Our own deaths -----------------------------------------------------------------------------------
-- In a battleground the Death Recap of our death is secret when we die. Blizzard's damage meter keeps
-- a Deaths view of our side's deaths, readable once we are out of combat (and dying takes us out of
-- it), and each entry has a recap ID whose recap names the killing blow: the probe read "Nop Deathgrab,
-- killed by Sirgoonie Dotsalot, Corruption, 359" this way.

local DEATHS_TYPE = 9 -- Enum.DamageMeterType.Deaths
local FRESH = 15      -- seconds: how recent our entry must be, by the session's clock
local usedRecaps = {} -- recap IDs already turned into a death, so a death is never recorded twice

local function field(t, k)
	if t == nil or isSecret(t) or type(t) ~= "table" then return nil end
	local ok, v = pcall(function() return t[k] end)
	if ok and not isSecret(v) then return v end
end

local function meterEnum(enum, name, fallback)
	local e = Enum and Enum[enum]
	local v = e and field(e, name)
	return type(v) == "number" and v or fallback
end

-- Our newest death in one meter session, if it is fresh and not used yet: its recap ID, or nil.
-- Returns false when the session cannot be read yet.
local function ourFreshDeath(sessionType)
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterEnum("DamageMeterType", "Deaths", DEATHS_TYPE))
	if not ok or session == nil or isSecret(session) then return false end
	local duration = field(session, "durationSeconds")
	local best, bestTime
	local sources = field(session, "combatSources")
	if type(sources) ~= "table" then return nil end
	for i = 1, 200 do
		local src = sources[i]
		if src == nil then break end
		local id, when = field(src, "deathRecapID"), field(src, "deathTimeSeconds")
		if field(src, "isLocalPlayer") == true and type(id) == "number" and id > 0 and not usedRecaps[id]
			and type(when) == "number" and when >= 0 and (not bestTime or when > bestTime) then
			best, bestTime = id, when
		end
	end
	if not best then return nil end
	if type(duration) == "number" and duration - bestTime > FRESH then return nil end
	return best
end

-- Who killed us, from the damage meter, when the Death Recap is hidden: killer name, the killing blow
-- ({ ability, spellId, amount }) and "found"; or nil, nil, "pending" (worth asking again shortly), or
-- nil, nil, "none". Battlegrounds only: that is where the probe saw it work.
function B:MeterDeath()
	if not inBattleground() then return nil, nil, "none" end
	if type(C_DamageMeter) ~= "table" or type(C_DamageMeter.GetCombatSessionFromType) ~= "function" then return nil, nil, "none" end
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, nil, "none" end
	for _, st in ipairs({ meterEnum("DamageMeterSessionType", "Current", 1), meterEnum("DamageMeterSessionType", "Overall", 0) }) do
		local id = ourFreshDeath(st)
		if id then
			usedRecaps[id] = true
			local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
			local ev = ok and type(events) == "table" and not isSecret(events) and events[1] or nil
			if type(ev) ~= "table" or isSecret(ev) then trace("our death: recap %d hidden", id) return nil, nil, "none" end
			local name = field(ev, "sourceName")
			if field(ev, "hideCaster") == true or type(name) ~= "string" or name == "" then name = nil end
			-- The killing blow, named the way the death recap window names it
			local row = { spell = field(ev, "spellName"), spellId = field(ev, "spellId"), env = field(ev, "environmentalType"),
				swing = field(ev, "event") == "SWING_DAMAGE" or nil, amount = field(ev, "amount") }
			local hit
			if dgks.KillingBlowOf then
				local ok2, h = pcall(dgks.KillingBlowOf, dgks, { rows = { row } })
				if ok2 then hit = h end
			end
			if not name then trace("our death: recap %d has no killer name", id) return nil, hit, "none" end
			trace("our death: killed by %s (%s)", name, hit and hit.ability or "no ability")
			return name, hit, "found"
		end
	end
	-- Not readable yet, or our entry not listed yet: both may change in a moment
	trace("our death: not in the damage meter yet")
	return nil, nil, "pending"
end
