-- dG KillShot player cache: what we know about other players we have seen, so kill and death
-- records can name an opponent's class, race, level and spec.
--
-- Players are noted from the target, focus, mouseover, nameplates and arena opponents (and, on
-- Classic, from the combat log). The Death Recap only gives a killer's name, so the killer is
-- looked up here by name.
--
-- Specs: the only readable source for another player's spec is an inspect. Nearby enemy players
-- are inspected quietly, at most one every INSPECT_INTERVAL seconds, never while the Inspect
-- window is open, and each player at most once per INSPECT_RETRY seconds. Arena opponent specs are
-- secret on retail, and Classic Era has no specs.

local dgks = dgks
local P = {}
dgks.Players = P

local MAX_SEEN = 500
local SEEN_TTL = 2 * 3600          -- forget players not seen for this long
local INSPECT_INTERVAL = 2         -- seconds between inspects
local INSPECT_RETRY = 120          -- seconds before the same player is tried again

local seen = {}        -- [PlayerKey] = { guid, name, class, race, level, t }
local byShort = {}     -- [Name] = PlayerKey of the last player seen with that name
local specByGUID = {}  -- [guid] = specialization ID
local tried = {}       -- [guid] = time of the last inspect attempt
local pending          -- { unit, guid, t } inspect we are waiting for
local lastInspect = 0
local seenCount = 0

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Calls fn and returns its results, or nothing if it failed or the first result is secret
local function readable(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok or isSecret(a) then return nil end
	return a, b, c, d
end

local function str(v)
	return type(v) == "string" and not isSecret(v) and v ~= "" and v or nil
end

-- Spec ID -> localized spec name, class file, spec icon
function P.SpecInfo(specID)
	if type(specID) ~= "number" or not GetSpecializationInfoByID then return nil end
	local ok, id, name, _, icon, _, classFile = pcall(GetSpecializationInfoByID, specID)
	if not ok or isSecret(name) or type(name) ~= "string" then return nil end
	if isSecret(icon) then icon = nil end
	return name, classFile, icon
end

-- This character's spec ID, or nil (Classic Era has none)
function P.MySpec()
	if not (GetSpecialization and GetSpecializationInfo) then return nil end
	local index = readable(GetSpecialization)
	if type(index) ~= "number" or index < 1 then return nil end
	local id = readable(GetSpecializationInfo, index)
	if type(id) == "number" and id > 0 then return id end
	return nil
end

local function prune()
	local cutoff = time() - SEEN_TTL
	for key, info in pairs(seen) do
		if info.t < cutoff then
			seen[key] = nil
			seenCount = seenCount - 1
			if byShort[info.name] == key then byShort[info.name] = nil end
		end
	end
end

local function remember(fullName, guid, class, race, level)
	local key = dgks.History.PlayerKey(fullName)
	if not key then return end
	local info = seen[key]
	if not info then
		if seenCount >= MAX_SEEN then prune() end
		info = {}
		seen[key] = info
		seenCount = seenCount + 1
	end
	info.guid = guid or info.guid
	info.name = key:match("^([^%-]+)")
	info.class = class or info.class
	info.race = race or info.race
	if type(level) == "number" and level > 0 then info.level = level end
	info.t = time()
	byShort[info.name] = key
	return info
end

-- Try to inspect an enemy player for their spec
local function maybeInspect(unit, guid)
	if not dgks.db.profile.inspectSpecs or not NotifyInspect or not GetInspectSpecialization then return end
	if specByGUID[guid] or pending then return end
	local now = GetTime()
	if now - lastInspect < INSPECT_INTERVAL then return end
	if tried[guid] and now - tried[guid] < INSPECT_RETRY then return end
	if InspectFrame and InspectFrame:IsShown() then return end
	if readable(CanInspect, unit, false) ~= true then return end
	lastInspect, tried[guid] = now, now
	pending = { unit = unit, guid = guid, t = now }
	pcall(NotifyInspect, unit)
end

-- Note a unit if it is another player
function P:Note(unit)
	if type(unit) ~= "string" then return end
	if readable(UnitExists, unit) ~= true or readable(UnitIsPlayer, unit) ~= true then return end
	local guid = str(readable(UnitGUID, unit))
	if guid and guid == UnitGUID("player") then return end
	local name, realm = readable(UnitFullName, unit)
	name, realm = dgks.SplitName(str(name), str(realm)) -- Forever: "First Surname", no realm
	if not guid or not name then return end
	local _, class = readable(UnitClass, unit)
	local _, race = readable(UnitRace, unit)
	local level = readable(UnitLevel, unit)
	remember(realm and (name .. "-" .. realm) or name, guid, str(class), str(race), type(level) == "number" and level or nil)
	if readable(UnitCanAttack, "player", unit) == true then maybeInspect(unit, guid) end
end

-- Note a player from the combat log (Classic): GUID and name only
function P:NoteCombatant(guid, name)
	guid, name = str(guid), str(name)
	if not guid or not name or not guid:match("^Player%-") then return end
	remember(name, guid)
end

-- What we know about a player, by GUID or name. Returns a table or nil.
function P:Lookup(name, guid)
	local info
	if str(name) then
		local key = dgks.History.PlayerKey(name)
		info = key and seen[key]
		if not info and not name:find("-", 1, true) then
			local k = byShort[name]
			info = k and seen[k]
		end
	end
	if not info and str(guid) then
		for _, i in pairs(seen) do
			if i.guid == guid then info = i break end
		end
	end
	guid = str(guid) or (info and info.guid)
	if not info and not guid then return nil end
	return {
		guid = guid,
		class = info and info.class,
		race = info and info.race,
		level = info and info.level,
		spec = guid and specByGUID[guid],
	}
end

function P:SpecFor(guid)
	return str(guid) and specByGUID[guid] or nil
end

local function onInspectReady(guid)
	local p = pending
	if not p or guid ~= p.guid then return end
	pending = nil
	if str(readable(UnitGUID, p.unit)) == guid then
		local spec = readable(GetInspectSpecialization, p.unit)
		if type(spec) == "number" and spec > 0 then specByGUID[guid] = spec end
	end
	-- Leave the inspect data alone if the player opened the Inspect window meanwhile
	if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then pcall(ClearInspectPlayer) end
end

function P:Enable()
	local f = CreateFrame("Frame")
	local events = {
		PLAYER_TARGET_CHANGED = function() P:Note("target") end,
		PLAYER_FOCUS_CHANGED = function() P:Note("focus") end,
		UPDATE_MOUSEOVER_UNIT = function() P:Note("mouseover") end,
		NAME_PLATE_UNIT_ADDED = function(unit) P:Note(unit) end,
		ARENA_OPPONENT_UPDATE = function(unit) P:Note(unit) end,
		INSPECT_READY = function(guid) onInspectReady(guid) end,
	}
	for event in pairs(events) do pcall(f.RegisterEvent, f, event) end
	f:SetScript("OnEvent", function(_, event, ...)
		local ok, err = pcall(events[event], ...)
		--@debug@
		if not ok then dgks:Print("DEBUG: player cache " .. event .. ": " .. tostring(err)) end
		--@end-debug@
	end)
	-- An inspect that never answered (out of range) stops blocking the next one
	C_Timer.NewTicker(5, function()
		if pending and GetTime() - pending.t > 5 then pending = nil end
	end)
end
