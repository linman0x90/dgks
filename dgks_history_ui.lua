-- dG KillShot history data for the window (dgks_window.lua): the history views and their rows,
-- the Overview numbers, the Settings > History options and the player tooltip lines.

local dgks = dgks
local H = dgks.History

-- Formatting ------------------------------------------------------------------------------------

local KIND_COLORS = { K = "ff40ff40", D = "ffff4040", W = "ffa0ffa0", L = "ffffa040", X = "ff60c0ff" }

local function kindText(kind)
	return ("|c%s%s|r"):format(KIND_COLORS[kind] or "ffffffff", H.KIND_NAMES[kind] or "?")
end

local function classColored(text, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then
		return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text)
	end
	return text
end

local function className(classFile)
	if not classFile then return "" end
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
end

local function when(t)
	return date("%Y-%m-%d %H:%M", t)
end

-- The opponent cell: grey for an unknown killer, "(likely)" after a guessed one
-- "Fire Mage" when the spec is known, otherwise "Mage"
local function classSpec(classFile, specID)
	local cls = className(classFile)
	local spec = specID and dgks.Players and dgks.Players.SpecInfo(specID)
	if spec then return cls ~= "" and (spec .. " " .. cls) or spec end
	return cls
end
H.ClassSpecText = classSpec

-- "Refuge Pointe, Arathi Highlands", or just the zone
local function location(rec)
	if rec.sz and rec.z and rec.sz ~= rec.z then return rec.sz .. ", " .. rec.z end
	return rec.z or rec.sz or ""
end
H.LocationText = location

local RACE_NAMES = { Scourge = "Undead", HighmountainTauren = "Highmountain Tauren", LightforgedDraenei = "Lightforged Draenei",
	DarkIronDwarf = "Dark Iron Dwarf", MagharOrc = "Mag'har Orc", KulTiran = "Kul Tiran", ZandalariTroll = "Zandalari Troll",
	VoidElf = "Void Elf", Nightborne = "Nightborne", EarthenDwarf = "Earthen", Dracthyr = "Dracthyr", Vulpera = "Vulpera" }

-- "Level 80 Human Fire Mage"
local function describe(level, raceFile, classFile, specID)
	local parts = {}
	if level and level > 0 then parts[#parts + 1] = "Level " .. level
	elseif level == -1 then parts[#parts + 1] = "Level ??" end
	if raceFile then parts[#parts + 1] = RACE_NAMES[raceFile] or raceFile end
	local cs = classSpec(classFile, specID)
	if cs ~= "" then parts[#parts + 1] = cs end
	return table.concat(parts, " ")
end

-- Class icons: one texture with every class, the same file on every client
local CLASS_ICON_FILE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_ICON_COORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 },
	DRUID = { 0.75, 1, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
	PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
	DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 }, MONK = { 0.5, 0.75, 0.5, 0.75 }, DEMONHUNTER = { 0.75, 1, 0.5, 0.75 },
	EVOKER = { 0, 0.25, 0.75, 1 },
}
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Texture, left, right, top, bottom for a player: their spec icon when known, else the class
-- icon, else a question mark
function H.ClassIconTexture(classFile, specID)
	local icon = specID and dgks.Players and select(3, dgks.Players.SpecInfo(specID))
	if icon then return icon, 0.08, 0.92, 0.08, 0.92 end
	local c = classFile and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]) or CLASS_ICON_COORDS[classFile])
	if c then return CLASS_ICON_FILE, c[1], c[2], c[3], c[4] end
	return UNKNOWN_ICON, 0.08, 0.92, 0.08, 0.92
end

-- The same icon as inline text, followed by a space
local function icon(classFile, specID, size)
	size = size or 14
	local tex, l, r, t, b = H.ClassIconTexture(classFile, specID)
	if tex == CLASS_ICON_FILE then
		local px = function(v) return math.floor(v * 256 + 0.5) end
		return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(tex, size, size, px(l), px(r), px(t), px(b))
	end
	return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(tex, size, size)
end
H.ClassIcon = icon

-- A level for a table cell, and its sort value ("??" sorts above every number)
local function levelText(level)
	if level == -1 then return "??", 10000 end
	if level and level > 0 then return tostring(level), level end
	return "", 0
end
H.LevelText = levelText

local function opponentText(rec, name)
	if H.IsUnknown(rec) then return icon() .. "|cff9d9d9d" .. name .. "|r" end
	local text = icon(rec.oc, rec.os) .. classColored(name, rec.oc)
	if rec.g then text = text .. " |cff9d9d9d(likely)|r" end
	return text
end

-- For guild views: whose record this is and what it counts as. A team kill (X) counts as a kill
-- by the member who landed it, not by whoever saw it.
local function memberOf(rec)
	if rec.k == "X" then return H.CanonicalMember(H.ShortName(rec.kn)), rec.kc, "K" end
	return H.CanonicalMember(H.ShortName(rec.a)), rec.c, rec.k
end

local function recordTip(rec)
	return function(tt)
		tt:AddLine(("%s: %s"):format(H.KIND_NAMES[rec.k] or "?", H.ShortName(rec.o)))
		tt:AddDoubleLine("When", date("%Y-%m-%d %H:%M:%S", rec.t), 1, 1, 1, 1, 1, 1)
		if rec.oc or rec.orc or rec.ol or rec.os then
			-- Kills: the opponent is the victim. Deaths: the killer. Duels: the other duelist.
			local role = (rec.k == "K" or rec.k == "X") and "Victim" or rec.k == "D" and "Killer" or "Opponent"
			tt:AddDoubleLine(role, classColored(describe(rec.ol, rec.orc, rec.oc, rec.os), rec.oc), 1, 1, 1, 1, 1, 1)
		end
		if rec.k == "X" and rec.kn then
			local killer = H.ShortName(rec.kn)
			local detail = describe(rec.kl, nil, rec.kc, rec.ks)
			if detail ~= "" then killer = killer .. ", " .. detail end
			tt:AddDoubleLine("Killing blow", classColored(killer, rec.kc), 1, 1, 1, 1, 1, 1)
		end
		if rec.a then
			local who = H.ShortName(rec.a)
			local detail = describe(rec.l, nil, rec.c, rec.cs)
			if detail ~= "" then who = who .. ", " .. detail end
			tt:AddDoubleLine(rec.k == "X" and "Seen by" or "Player", classColored(who, rec.c), 1, 1, 1, 1, 1, 1)
		end
		local place = location(rec)
		if place ~= "" then tt:AddDoubleLine("Location", place, 1, 1, 1, 1, 1, 1) end
		if rec.i and rec.i ~= "none" then
			local kinds = { pvp = "Battleground", arena = "Arena", party = "Dungeon", raid = "Raid", scenario = "Scenario" }
			tt:AddDoubleLine("Instance", kinds[rec.i] or rec.i, 1, 1, 1, 1, 1, 1)
		end
		if rec.st and rec.st > 0 then tt:AddDoubleLine("Streak", tostring(rec.st), 1, 1, 1, 1, 1, 1) end
		if rec.mk then tt:AddDoubleLine("Multikill", tostring(rec.mk + 1) .. " kills", 1, 1, 1, 1, 1, 1) end
		if rec.lg then tt:AddLine("Imported from the old kill and death lists", 0.6, 0.6, 0.6) end
		if H.IsUnknown(rec) then
			tt:AddLine("The game did not say who the killer was.", 0.6, 0.6, 0.6, true)
		elseif rec.g then
			local others = (rec.gn or 1) > 1 and (" (one of %d enemies targeting you)"):format(rec.gn) or ""
			tt:AddLine("Likely killer: targeting you when you died" .. others .. ". The game did not name the killer.", 0.6, 0.6, 0.6, true)
		end
	end
end

-- Filters ---------------------------------------------------------------------------------------

local PERIODS = { [86400] = "24 hours", [604800] = "7 days", [2592000] = "30 days",
	[7776000] = "90 days", [0] = "All time" }
local PERIOD_ORDER = { 86400, 604800, 2592000, 7776000, 0 }
local KIND_FILTERS = { all = "All", K = "Kills", D = "Deaths", duel = "Duels", X = "Team kills" }
local KIND_ORDER = { "all", "K", "D", "duel", "X" }

local ui = {
	tab = "mine",
	search = "",
	kind = "all",
	period = 0,
	sort = {
		mine = { col = 1, desc = true },
		guild = { col = 1, desc = true },
		opponents = { col = 3, desc = true },
		guildopponents = { col = 3, desc = true },
		leaders = { col = 2, desc = true },
	},
}

-- ignoreKind: the tab has no Type filter (the totals tabs count every kind)
local function passes(rec, fields, ignoreKind)
	if ui.period > 0 and rec.t < time() - ui.period then return false end
	if ignoreKind then
		-- no Type filter on this tab
	elseif ui.kind == "duel" then
		if rec.k ~= "W" and rec.k ~= "L" then return false end
	elseif ui.kind ~= "all" and rec.k ~= ui.kind then
		return false
	end
	if ui.search ~= "" then
		for _, f in ipairs(fields) do
			if type(f) == "string" and f:lower():find(ui.search, 1, true) then return true end
		end
		return false
	end
	return true
end

-- Tabs ------------------------------------------------------------------------------------------

local TABS = {
	mine = {
		columns = {
			{ title = "When", width = 0.17 },
			{ title = "Type", width = 0.10 },
			{ title = "Opponent", width = 0.21, desc = false },
			{ title = "Level", width = 0.06, align = "RIGHT" },
			{ title = "Class", width = 0.17, desc = false },
			{ title = "Location", width = 0.22, desc = false },
			{ title = "Streak", width = 0.07, align = "RIGHT" },
		},
		rows = function()
			local rows = {}
			for _, rec in ipairs(H:PersonalRecords()) do
				local opp = H.ShortName(rec.o)
				local cls, place = classSpec(rec.oc, rec.os), location(rec)
				local lvl, lvlSort = levelText(rec.ol)
				if passes(rec, { opp, rec.z, rec.sz, cls, rec.kn }) then
					rows[#rows + 1] = {
						cells = { when(rec.t), kindText(rec.k), opponentText(rec, opp) .. (rec.kn and (" |cff9d9d9d(by " .. H.ShortName(rec.kn) .. ")|r") or ""),
							lvl, classColored(cls, rec.oc), place, rec.st and tostring(rec.st) or "" },
						sort = { rec.t, rec.k, opp:lower(), lvlSort, cls, place:lower(), rec.st or 0 },
						tip = recordTip(rec),
					}
				end
			end
			return rows
		end,
	},
	guild = {
		columns = {
			{ title = "When", width = 0.16 },
			{ title = "Member", width = 0.15, desc = false },
			{ title = "Type", width = 0.09 },
			{ title = "Opponent", width = 0.18, desc = false },
			{ title = "Level", width = 0.06, align = "RIGHT" },
			{ title = "Class", width = 0.16, desc = false },
			{ title = "Location", width = 0.20, desc = false },
		},
		rows = function()
			local rows = {}
			for _, rec in ipairs(H:GuildRecords()) do
				local member, memberClass = memberOf(rec)
				local opp = H.ShortName(rec.o)
				local cls, place = classSpec(rec.oc, rec.os), location(rec)
				local lvl, lvlSort = levelText(rec.ol)
				if passes(rec, { member, opp, rec.z, rec.sz, cls }) then
					rows[#rows + 1] = {
						cells = { when(rec.t), icon(memberClass) .. classColored(member, memberClass), kindText(rec.k), opponentText(rec, opp), lvl, classColored(cls, rec.oc), place },
						sort = { rec.t, member:lower(), rec.k, opp:lower(), lvlSort, cls, place:lower() },
						tip = recordTip(rec),
					}
				end
			end
			return rows
		end,
	},
	opponents = {
		noKindFilter = true,
		columns = {
			{ title = "Opponent", width = 0.23, desc = false },
			{ title = "Class", width = 0.22, desc = false },
			{ title = "Kills", width = 0.09, align = "RIGHT" },
			{ title = "Deaths", width = 0.09, align = "RIGHT" },
			{ title = "Duels W-L", width = 0.12, align = "RIGHT" },
			{ title = "Last seen", width = 0.25 },
		},
		rows = function()
			local byName, list = {}, {}
			for _, rec in ipairs(H:PersonalRecords()) do
				local opp = H.ShortName(rec.o)
				if rec.k ~= "X" and not H.IsUnknown(rec) and passes(rec, { opp }, true) then
					local o = byName[opp]
					if not o then
						o = { name = opp, K = 0, D = 0, W = 0, L = 0, last = 0 }
						byName[opp] = o
						list[#list + 1] = o
					end
					o[rec.k] = o[rec.k] + 1
					if rec.t >= o.last then o.last = rec.t end
					if rec.oc then o.class = rec.oc end
					if rec.os then o.spec = rec.os end
				end
			end
			local rows = {}
			for _, o in ipairs(list) do
				rows[#rows + 1] = {
					cells = { icon(o.class, o.spec) .. classColored(o.name, o.class), classColored(classSpec(o.class, o.spec), o.class), tostring(o.K), tostring(o.D), o.W .. "-" .. o.L, when(o.last) },
					sort = { o.name:lower(), classSpec(o.class, o.spec), o.K, o.D, o.W - o.L, o.last },
				}
			end
			return rows
		end,
	},
	guildopponents = {
		noKindFilter = true,
		columns = {
			{ title = "Opponent", width = 0.16, desc = false },
			{ title = "Class", width = 0.17, desc = false },
			{ title = "Kills", width = 0.07, align = "RIGHT" },
			{ title = "Deaths", width = 0.08, align = "RIGHT" },
			{ title = "Duels W-L", width = 0.10, align = "RIGHT" },
			{ title = "Fought by", width = 0.09, align = "RIGHT" },
			{ title = "Top killer", width = 0.15, desc = false },
			{ title = "Last seen", width = 0.18 },
		},
		rows = function()
			local byKey, list = {}, {}
			for _, rec in ipairs(H:GuildRecords()) do
				local key = H.OpponentKey(rec)
				local member, memberClass, kind = memberOf(rec)
				local opp = H.ShortName(key)
				-- Search matches the opponent or a member, so "Zed" or "Bob" both narrow the list
				if key and not H.IsUnknown(rec) and passes(rec, { opp, member }, true) then
					local o = byKey[key]
					if not o then
						o = { name = opp, K = 0, D = 0, W = 0, L = 0, last = 0, members = {}, memberCount = 0 }
						byKey[key] = o
						list[#list + 1] = o
					end
					o[kind] = o[kind] + 1
					if rec.t >= o.last then o.last = rec.t end
					if rec.oc then o.class = rec.oc end
					if rec.os then o.spec = rec.os end
					local m = o.members[member]
					if not m then
						m = { name = member, class = memberClass, K = 0, D = 0, W = 0, L = 0 }
						o.members[member] = m
						o.memberCount = o.memberCount + 1
					end
					m[kind] = m[kind] + 1
				end
			end
			local rows = {}
			for _, o in ipairs(list) do
				-- Members sorted by kills on this opponent, then fewest deaths
				local members = {}
				for _, m in pairs(o.members) do members[#members + 1] = m end
				table.sort(members, function(a, b)
					if a.K ~= b.K then return a.K > b.K end
					if a.D ~= b.D then return a.D < b.D end
					return a.name < b.name
				end)
				local top = members[1]
				local topText, topSort = "", ""
				if top and top.K > 0 then
					topText = icon(top.class) .. classColored(top.name, top.class) .. " (" .. top.K .. ")"
					topSort = top.name:lower()
				end
				rows[#rows + 1] = {
					cells = { icon(o.class, o.spec) .. classColored(o.name, o.class), classColored(classSpec(o.class, o.spec), o.class), tostring(o.K), tostring(o.D),
						o.W .. "-" .. o.L, tostring(o.memberCount), topText, when(o.last) },
					sort = { o.name:lower(), classSpec(o.class, o.spec), o.K, o.D, o.W - o.L, o.memberCount, topSort, o.last },
					tip = function(tt)
						tt:AddLine(classColored(o.name, o.class))
						tt:AddLine(("Guild: %d kills, %d deaths, duels %d-%d"):format(o.K, o.D, o.W, o.L), 1, 1, 1)
						tt:AddLine(" ")
						for i = 1, math.min(10, #members) do
							local m = members[i]
							local duels = (m.W + m.L > 0) and ("   duels " .. m.W .. "-" .. m.L) or ""
							tt:AddDoubleLine(classColored(m.name, m.class),
								("|cff40ff40%d|r / |cffff4040%d|r%s"):format(m.K, m.D, duels))
						end
						if #members > 10 then
							tt:AddLine(("and %d more"):format(#members - 10), 0.6, 0.6, 0.6)
						end
					end,
				}
			end
			return rows
		end,
	},
	leaders = {
		noKindFilter = true,
		columns = {
			{ title = "Member", width = 0.24, desc = false },
			{ title = "Kills", width = 0.11, align = "RIGHT" },
			{ title = "Deaths", width = 0.11, align = "RIGHT" },
			{ title = "K/D", width = 0.10, align = "RIGHT" },
			{ title = "Best streak", width = 0.14, align = "RIGHT" },
			{ title = "Duels W-L", width = 0.12, align = "RIGHT" },
			{ title = "Last kill", width = 0.18 },
		},
		rows = function()
			local byName, list = {}, {}
			for _, rec in ipairs(H:GuildRecords()) do
				local member, memberClass, kind = memberOf(rec)
				if passes(rec, { member }, true) then
					local m = byName[member]
					if not m then
						m = { name = member, K = 0, D = 0, W = 0, L = 0, best = 0, last = 0 }
						byName[member] = m
						list[#list + 1] = m
					end
					m[kind] = m[kind] + 1
					if memberClass then m.class = memberClass end
					if kind == "K" then
						if rec.t > m.last then m.last = rec.t end
						if (rec.st or 0) > m.best then m.best = rec.st end
					end
				end
			end
			local rows = {}
			for _, m in ipairs(list) do
				local kd = m.K / math.max(m.D, 1)
				rows[#rows + 1] = {
					cells = { icon(m.class) .. classColored(m.name, m.class), tostring(m.K), tostring(m.D), ("%.2f"):format(kd), tostring(m.best), m.W .. "-" .. m.L, m.last > 0 and when(m.last) or "" },
					sort = { m.name:lower(), m.K, m.D, kd, m.best, m.W - m.L, m.last },
				}
			end
			return rows
		end,
	},
}


H.VIEW_ORDER = {
	{ value = "mine", text = "My history" },
	{ value = "guild", text = "Guild history" },
	{ value = "opponents", text = "My opponents" },
	{ value = "guildopponents", text = "Guild opponents" },
	{ value = "leaders", text = "Guild leaderboard" },
}
H.Views = TABS
H.Filter = ui
H.KIND_FILTERS, H.KIND_ORDER = KIND_FILTERS, KIND_ORDER
H.PERIODS, H.PERIOD_ORDER = PERIODS, PERIOD_ORDER

-- Rows of a history view (default: the current one) with the current filters, unsorted
function H:ViewRows(view)
	return TABS[view or ui.tab].rows()
end

local function statusText()
	local gk = H:GuildKey()
	local mine = #H:PersonalRecords()
	if gk then
		return ("%d personal records  |  Guild %s: %d records"):format(mine, gk, #H:GuildRecords())
	end
	return ("%d personal records  |  Not in a guild"):format(mine)
end
H.StatusText = statusText

-- Overview numbers ------------------------------------------------------------------------------

H.ACTIVITY_DAYS = 14

-- The n opponents this character has the most records of the given kind against
local function top(kind, n)
	local byName, list = {}, {}
	for _, rec in ipairs(H:PersonalRecords()) do
		if rec.k == kind and not H.IsUnknown(rec) then
			local name = H.ShortName(rec.o)
			local o = byName[name]
			if not o then
				o = { name = name, count = 0, last = 0 }
				byName[name] = o
				list[#list + 1] = o
			end
			o.count = o.count + 1
			if rec.oc then o.class = rec.oc end
			if rec.os then o.spec = rec.os end
			if rec.t > o.last then o.last = rec.t end
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.last > b.last
	end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = list[i] end
	return out
end

-- Everything the Overview shows, from this character's personal history:
--   totals   { K, D, W, L, X }
--   prey, predators   top 5 { name, count, class, spec, last }
--   days     ACTIVITY_DAYS entries, oldest first: { start, K, D } (kills and deaths per calendar day)
--   recent   the newest records, newest first
function H:OverviewStats(recentCount)
	local totals = { K = 0, D = 0, W = 0, L = 0, X = 0 }
	local today = date("*t", time())
	local days = {}
	for i = 1, H.ACTIVITY_DAYS do
		local d = { year = today.year, month = today.month, day = today.day - (H.ACTIVITY_DAYS - i), hour = 0, min = 0, sec = 0 }
		days[i] = { start = time(d), K = 0, D = 0 }
	end
	local first = days[1].start
	local records = H:PersonalRecords()
	for _, rec in ipairs(records) do
		totals[rec.k] = (totals[rec.k] or 0) + 1
		if (rec.k == "K" or rec.k == "D") and rec.t >= first then
			for i = H.ACTIVITY_DAYS, 1, -1 do
				if rec.t >= days[i].start then
					days[i][rec.k] = days[i][rec.k] + 1
					break
				end
			end
		end
	end
	local recent = {}
	for i = #records, 1, -1 do recent[#recent + 1] = records[i] end
	table.sort(recent, function(a, b) return a.t > b.t end)
	for i = #recent, (recentCount or 6) + 1, -1 do recent[i] = nil end
	return {
		totals = totals,
		prey = top("K", 5),
		predators = top("D", 5),
		days = days,
		recent = recent,
	}
end

-- Option entries for Settings > History. order runs from base upward.
function H:SettingsArgs(base)
	base = base - 41
	return {
		historyStatus = {
			type = "description",
			order = base + 41,
			fontSize = "medium",
			name = function() return statusText() .. "\n" end,
		},
		historySync = {
			type = "execute",
			order = base + 43,
			name = "Sync now",
			desc = "Ask guild members for history you are missing.",
			func = function() H:SyncNow() end,
		},
		historyShare = {
			type = "toggle",
			order = base + 44,
			width = "full",
			name = "Share my kills and deaths with my guild",
			desc = "Send your kills, deaths and duels to guild members running dG KillShot, and keep a copy of theirs. Turning this off also stops receiving guild history.",
			get = function() return dgks.db.profile.historyShare end,
			set = function(_, v)
				dgks.db.profile.historyShare = v
				if v then H:SyncNow() end
			end,
		},
		historyTooltip = {
			type = "toggle",
			order = base + 44.5,
			width = "full",
			name = "Show kills and deaths in player tooltips",
			desc = "When you mouse over a player, show how often you and your guild have killed them and been killed by them.",
			get = function() return dgks.db.profile.historyTooltip end,
			set = function(_, v) dgks.db.profile.historyTooltip = v end,
		},
		historyGuess = {
			type = "toggle",
			order = base + 44.7,
			width = "full",
			name = "Record the likely killer when the game hides it",
			desc = "On retail the Death Recap sometimes cannot name your killer. Record an enemy player who was targeting you when you died instead, marked \"likely\". Right in a 1v1, a guess in group fights.",
			get = function() return dgks.db.profile.guessKiller end,
			set = function(_, v) dgks.db.profile.guessKiller = v end,
		},
		historyTeamKills = {
			type = "toggle",
			order = base + 44.75,
			width = "full",
			name = "Record teammates' killing blows",
			desc = "Record kills by party and raid members on other players (in battlegrounds, for example) as team kills. Team kills by guild members are shared with the guild and count as their kills there; they never count toward your own stats.",
			get = function() return dgks.db.profile.recordTeamKills end,
			set = function(_, v) dgks.db.profile.recordTeamKills = v end,
		},
		historyPve = {
			type = "toggle",
			order = base + 44.77,
			width = "full",
			name = "Also log PvE kills and deaths",
			desc = "History records kills of other players and deaths to other players. Turn this on to also record kills of NPCs and deaths to NPCs, falling and the like. PvE records are shared with your guild like any other.",
			get = function() return dgks.db.profile.historyPve end,
			set = function(_, v) dgks.db.profile.historyPve = v end,
		},
		historyInspect = {
			type = "toggle",
			order = base + 44.8,
			width = "full",
			name = "Look up enemy specs",
			desc = "Quietly inspect enemy players near you (at most one every 2 seconds) so kills and deaths can record their spec. Turn off if it interferes with other addons that inspect.",
			hidden = function() return not GetInspectSpecialization end,
			get = function() return dgks.db.profile.inspectSpecs end,
			set = function(_, v) dgks.db.profile.inspectSpecs = v end,
		},
		historyRetention = {
			type = "range",
			order = base + 45,
			width = "double",
			name = "Keep guild history for (days)",
			desc = "Guild records older than this are deleted and not synced. Your personal history is always kept.",
			min = 7, max = 365, step = 1, bigStep = 7,
			get = function() return dgks.db.profile.historyRetentionDays end,
			set = function(_, v)
				dgks.db.profile.historyRetentionDays = v
				H:Prune()
				H:NotifyChanged()
			end,
		},
		historyClearGuild = {
			type = "execute",
			order = base + 46,
			name = "Clear guild history",
			desc = "Delete your copy of this guild's history. It is synced again from guild members.",
			confirm = true,
			confirmText = "Delete your copy of the guild history? It will be synced again from guild members.",
			func = function() H:ClearGuild() end,
		},
		historyClearMine = {
			type = "execute",
			order = base + 47,
			name = "Clear my history",
			desc = "Delete this character's personal history. Records already shared with the guild stay there.",
			confirm = true,
			confirmText = "Delete this character's personal kill and death history? This cannot be undone.",
			func = function()
				wipe(dgks.db.char.history.records)
				H:NotifyChanged()
			end,
		},
	}
end

-- Unit tooltips ---------------------------------------------------------------------------------
-- Mousing over a player adds how often you, and your guild, killed them and were killed by them.

local function usableString(v)
	return v ~= nil and not (issecretvalue and issecretvalue(v)) and type(v) == "string" and v ~= ""
end

local function countText(counts)
	return ("|cff40ff40Killed %d|r   |cffff4040Killed by %d|r"):format(counts.K, counts.D)
end

local function addTooltipLines(tooltip, unit)
	if not dgks.db.profile.historyTooltip or not usableString(unit) then return end
	local isPlayer = UnitIsPlayer(unit)
	if isPlayer ~= true or UnitIsUnit(unit, "player") == true then return end
	local name, realm = UnitFullName(unit)
	if not usableString(name) then return end
	name, realm = dgks.SplitName(name, usableString(realm) and realm or nil) -- Forever: "First Surname"
	if not name then return end
	if realm then name = name .. "-" .. realm end

	local mine, guild = H:CountsFor(H.PlayerKey(name))
	local guildAny = guild and (guild.K > 0 or guild.D > 0)
	if mine.K == 0 and mine.D == 0 and not guildAny then return end

	tooltip:AddDoubleLine("KillShot - you", countText(mine), 1, 0.82, 0)
	if guild then
		tooltip:AddDoubleLine("KillShot - guild", countText(guild), 1, 0.82, 0)
	end
end

local function onUnitTooltip(tooltip)
	if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
	-- A tooltip must never break because of us
	pcall(function()
		local _, unit = tooltip:GetUnit()
		addTooltipLines(tooltip, unit)
	end)
end

local tooltipInstalled = false
function H:InstallTooltip()
	if tooltipInstalled then return end
	tooltipInstalled = true
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
	else
		GameTooltip:HookScript("OnTooltipSetUnit", onUnitTooltip)
	end
end
