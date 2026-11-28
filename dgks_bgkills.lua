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

-- Start counting from the current value: on entering or leaving a zone
function B:Reset()
	kbBase = statValue(KB_STAT)
end

-- The enemy player we are fighting: our target, else our soft target. Returns "Name-Realm" (on
-- Forever "First Surname-Realm"), with level and class when readable, or nil.
local function candidate()
	for _, unit in ipairs(CANDIDATE_UNITS) do
		if readable(UnitExists, unit) and readable(UnitIsPlayer, unit) and readable(UnitCanAttack, "player", unit) then
			local ok, name, realm = pcall(UnitName, unit)
			if ok and not isSecret(name) and not isSecret(realm) then
				name, realm = dgks.SplitName(name, realm) -- Forever: "First Surname", no realm
				if name then
					realm = realm or dgks.RealmName()
					local level = readable(UnitLevel, unit)
					local ok2, _, classFile = pcall(UnitClass, unit)
					if not ok2 or isSecret(classFile) or type(classFile) ~= "string" then classFile = nil end
					return {
						name = realm and (name .. "-" .. realm) or name,
						level = type(level) == "number" and level or nil,
						class = classFile,
					}
				end
			end
		end
	end
	return nil
end

-- Decides, a moment after a hidden PARTY_KILL, whether it was our killing blow on a player
local function settle(kill)
	local kb = statValue(KB_STAT)
	if not kb or not kbBase then return end
	if kb <= kbBase then
		kbBase = kb -- a groupmate's kill (and keep in step if the statistic ever went down)
		return
	end
	kbBase = kbBase + 1 -- ours: claim one rise, so a second kill in the same moment gets the next
	local hk = statValue(HK_STAT)
	if not (hk and kill.hk and hk > kill.hk) then return end -- an NPC, or a kill worth no honor
	if not kill.victim then return end -- nobody targeted: the victim cannot be named
	dgks:KillshotTX(kill.victim.name, kill.t, nil,
		{ guessed = 1, level = kill.victim.level, class = kill.victim.class })
end

-- PARTY_KILL with secret GUIDs. Takes a note now, while our target is still the victim and the
-- honorable kill has not arrived, and settles it after DELAY.
function B:OnHiddenKill()
	if not inBattleground() then return end
	if not kbBase then
		-- No starting point yet (the statistic was not readable when we zoned in): start now. This
		-- kill may already be counted in it, so it is let go.
		B:Reset()
		return
	end
	local kill = { t = GetTime(), hk = statValue(HK_STAT), victim = candidate() }
	C_Timer.After(DELAY, function()
		local ok, err = pcall(settle, kill)
		--@debug@
		if not ok then dgks:Print("DEBUG: battleground kill failed: " .. tostring(err)) end
		--@end-debug@
	end)
end
