-- dG KillShot death recap window: opens when you die and lists the damage you took in the last
-- WINDOW seconds, oldest first, ending with the killing blow (highlighted). Damage is coloured by
-- school and health bars by how much health was left. The Compact view shows only the killing blow
-- and the attackers who did the most damage.
--
-- Sources:
--   Classic: the combat log. Every hit on the player is kept for WINDOW seconds.
--   Retail/Forever: the combat log is closed to addons, so the hits come from Blizzard's Death
--   Recap (C_DeathRecap). Blizzard keeps only the last few hits, so this may cover less than
--   WINDOW seconds. Some values can be secret there: they are shown as the game hands them over
--   and never compared or calculated with.

local dgks = dgks
local WINDOW = 10   -- seconds of damage to show
local MAX_ROWS = 20
local ROW_HEIGHT = 22
local WIDTH = 520

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Readable number (not secret)
local function num(v)
	return type(v) == "number" and not isSecret(v)
end

-- Collecting hits (Classic) ----------------------------------------------------------------------

local taken = {} -- { t = GetTime(), source, spell, spellId, env, school, amount, overkill, absorbed, resisted, blocked, crit, hp, hpMax }

local DAMAGE_EVENTS = {
	SWING_DAMAGE = "swing", RANGE_DAMAGE = "spell", SPELL_DAMAGE = "spell", SPELL_PERIODIC_DAMAGE = "spell",
	SPELL_BUILDING_DAMAGE = "spell", DAMAGE_SHIELD = "spell", DAMAGE_SPLIT = "spell", ENVIRONMENTAL_DAMAGE = "env",
}

local function prune(now)
	while taken[1] and now - taken[1].t > WINDOW + 5 do table.remove(taken, 1) end
end

-- Called with CombatLogGetCurrentEventInfo() for every combat log event on Classic
function dgks:TrackDamageTaken(...)
	local _, event, _, _, sourceName, _, _, destGUID = ...
	local kind = DAMAGE_EVENTS[event]
	if not kind or destGUID ~= UnitGUID("player") then return end
	local hit = { t = GetTime(), source = sourceName }
	if kind == "swing" then
		-- amount, overkill, school, resisted, blocked, absorbed, critical
		hit.amount, hit.overkill, hit.school, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
		hit.swing = true
	elseif kind == "spell" then
		-- spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical
		local spellSchool, school
		hit.spellId, hit.spell, spellSchool, hit.amount, hit.overkill, school, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
		hit.school = school or spellSchool
	else
		-- environmentalType, amount, overkill, school, resisted, blocked, absorbed, critical
		hit.env, hit.amount, hit.overkill, hit.school, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
		hit.source = nil
	end
	hit.hp, hit.hpMax = UnitHealth("player"), UnitHealthMax("player")
	taken[#taken + 1] = hit
	prune(hit.t)
end

-- The recap, as rows oldest first: { ago, source, ability, icon, amount, overkill, absorbed, ... }
local function fromCombatLog(deathTime)
	local rows = {}
	for _, hit in ipairs(taken) do
		local ago = deathTime - hit.t
		if ago <= WINDOW and ago >= -1 then
			local row = {}
			for k, v in pairs(hit) do row[k] = v end
			row.ago = math.max(0, ago)
			rows[#rows + 1] = row
		end
	end
	wipe(taken)
	return rows
end

-- Blizzard's Death Recap (newest first), converted to rows oldest first
local function fromDeathRecap()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return {} end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok or isSecret(events) or type(events) ~= "table" then return {} end
	local maxOk, maxHealth = pcall(C_DeathRecap.GetRecapMaxHealth)
	if not maxOk then maxHealth = nil end

	local list = {}
	for i = 1, 50 do
		local ev = events[i]
		if ev == nil or isSecret(ev) or type(ev) ~= "table" then break end
		list[#list + 1] = ev
	end
	-- Death time is the newest timestamp, when timestamps are readable
	local deathTime
	for _, ev in ipairs(list) do
		if num(ev.timestamp) and (not deathTime or ev.timestamp > deathTime) then deathTime = ev.timestamp end
	end

	local rows = {}
	for i = #list, 1, -1 do
		local ev = list[i]
		local ago
		if deathTime and num(ev.timestamp) then ago = deathTime - ev.timestamp end
		if ago == nil or ago <= WINDOW then
			local source = ev.sourceName
			if not isSecret(ev.hideCaster) and ev.hideCaster == true then source = nil end
			rows[#rows + 1] = {
				ago = ago,
				source = source,
				spell = ev.spellName,
				spellId = ev.spellId,
				env = ev.environmentalType,
				school = ev.school,
				swing = (not isSecret(ev.event) and ev.event == "SWING_DAMAGE") or nil,
				amount = ev.amount,
				overkill = ev.overkill,
				absorbed = ev.absorbed,
				resisted = ev.resisted,
				blocked = ev.blocked,
				crit = ev.critical,
				hp = ev.currentHP,
				hpMax = maxHealth,
			}
		end
	end
	return rows
end

-- Display helpers ---------------------------------------------------------------------------------

local ENV_TEXT = { FALLING = "Falling", DROWNING = "Drowning", FIRE = "Fire", LAVA = "Lava", SLIME = "Slime", FATIGUE = "Fatigue" }
local ENV_ICON = { FALLING = "ability_rogue_quickrecovery", DROWNING = "spell_shadow_demonbreath", FIRE = "spell_fire_fire",
	LAVA = "spell_fire_fire", SLIME = "inv_misc_slime_01", FATIGUE = "ability_creature_cursed_05" }
local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"

local function spellIcon(spellId)
	if not num(spellId) then return nil end
	local ok, tex
	if C_Spell and C_Spell.GetSpellTexture then
		ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
	elseif GetSpellTexture then
		ok, tex = pcall(GetSpellTexture, spellId)
	end
	if ok and tex and not isSecret(tex) then return tex end
	return nil
end

-- Ability text and icon for a row. Values may be secret; those are returned untouched.
local function ability(row)
	if row.env ~= nil then
		if isSecret(row.env) then return row.env, "Interface\\Icons\\ability_creature_cursed_05" end
		local e = tostring(row.env):upper()
		return ENV_TEXT[e] or row.env, "Interface\\Icons\\" .. (ENV_ICON[e] or "ability_creature_cursed_05")
	end
	if row.swing then return "Melee", MELEE_ICON end
	return row.spell, spellIcon(row.spellId)
end

local function short(n)
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e4 then return ("%.0fK"):format(n / 1e3) end
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Put a value in a font string: formatted when readable, as handed over when secret
local function setText(fs, value, format)
	if value == nil then
		fs:SetText("")
	elseif isSecret(value) then
		if not pcall(fs.SetText, fs, value) then fs:SetText("?") end
	else
		fs:SetText(format and format(value) or tostring(value))
	end
end

-- Damage schools: bit, name, colour for the amount. Hits of several schools take the colour of the
-- first magic school in them (Shadowflame: Fire).
local SCHOOLS = {
	{ 2, "Holy", { 1, 0.9, 0.5 } },
	{ 4, "Fire", { 1, 0.5, 0 } },
	{ 8, "Nature", { 0.3, 1, 0.3 } },
	{ 16, "Frost", { 0.5, 1, 1 } },
	{ 32, "Shadow", { 0.63, 0.5, 1 } },
	{ 64, "Arcane", { 1, 0.5, 1 } },
	{ 1, "Physical", { 1, 0.35, 0.35 } },
}
local DEFAULT_DAMAGE_COLOR = { 1, 0.35, 0.35 }

local function hasBit(value, b)
	return math.floor(value / b) % 2 == 1
end

-- Colour and name of a damage school, or nil when it is unknown or secret
local function schoolInfo(school)
	if not num(school) or school <= 0 then return nil end
	local color, names = nil, {}
	for _, s in ipairs(SCHOOLS) do
		if hasBit(school, s[1]) then
			color = color or s[3]
			names[#names + 1] = s[2]
		end
	end
	if not color then return nil end
	return color, table.concat(names, "/")
end

-- Window -----------------------------------------------------------------------------------------

local HEADER_Y = -62     -- column headings, from the top of the window
local FIRST_ROW_Y = -76
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local KILL_RED = { 0.85, 0.12, 0.12 }
local TOP_SOURCES = 3

local frame, rowFrames, sourceFrames, lastRecap

local function healthColor(fraction)
	if fraction > 0.5 then return 0.2, 0.75, 0.25 end
	if fraction > 0.25 then return 0.9, 0.7, 0.1 end
	return 0.85, 0.2, 0.15
end

local function alphaAnimation(f, from, to, duration)
	local group = f:CreateAnimationGroup()
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(duration)
	if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
	return group
end

-- Close with a short fade
local function fadeOut()
	if not frame or not frame:IsShown() then return end
	frame.fadeIn:Stop()
	frame.fadeOut:Play()
end

local function rowTooltip(self)
	if not self.data then return end
	local d = self.data
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	pcall(function()
		local text = ability(d)
		GameTooltip:AddLine(text or "Unknown ability")
		if self.killingBlow then GameTooltip:AddLine("Killing blow", KILL_RED[1], KILL_RED[2], KILL_RED[3]) end
		local function line(label, v, fmt)
			if v == nil then return end
			if isSecret(v) then
				GameTooltip:AddDoubleLine(label, v, 1, 1, 1, 1, 1, 1)
			elseif not num(v) or v > 0 then
				GameTooltip:AddDoubleLine(label, fmt and fmt(v) or tostring(v), 1, 1, 1, 1, 1, 1)
			end
		end
		line("Attacker", d.source)
		local color, schoolName = schoolInfo(d.school)
		if schoolName then GameTooltip:AddDoubleLine("School", schoolName, 1, 1, 1, color[1], color[2], color[3]) end
		line("Damage", d.amount, short)
		line("Overkill", d.overkill, short)
		line("Absorbed", d.absorbed, short)
		line("Resisted", d.resisted, short)
		line("Blocked", d.blocked, short)
		if d.crit == true then GameTooltip:AddLine("Critical hit", 1, 0.82, 0) end
		if d.ago == nil then GameTooltip:AddLine("Time not available here", 0.6, 0.6, 0.6) end
	end)
	GameTooltip:Show()
end

-- One hit: time, ability, attacker, damage, health afterwards
local function createRow()
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(WIDTH - 20, ROW_HEIGHT)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.035)
	-- Killing blow: red wash, red edge and a skull
	row.kbWash = row:CreateTexture(nil, "BACKGROUND")
	row.kbWash:SetAllPoints()
	row.kbWash:SetColorTexture(KILL_RED[1], KILL_RED[2], KILL_RED[3], 0.22)
	row.kbEdge = row:CreateTexture(nil, "BORDER")
	row.kbEdge:SetPoint("TOPLEFT")
	row.kbEdge:SetPoint("BOTTOMLEFT")
	row.kbEdge:SetWidth(2)
	row.kbEdge:SetColorTexture(KILL_RED[1], KILL_RED[2], KILL_RED[3], 1)
	row.skull = row:CreateTexture(nil, "ARTWORK")
	row.skull:SetTexture(SKULL)
	row.skull:SetSize(14, 14)
	row.skull:SetPoint("LEFT", 5, 0)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)

	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.time:SetPoint("LEFT", 2, 0)
	row.time:SetWidth(44)
	row.time:SetJustifyH("RIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 52, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.ability = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.ability:SetPoint("LEFT", 74, 0)
	row.ability:SetWidth(158)
	row.ability:SetJustifyH("LEFT")
	row.ability:SetWordWrap(false)
	row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.source:SetPoint("LEFT", 236, 0)
	row.source:SetWidth(118)
	row.source:SetJustifyH("LEFT")
	row.source:SetWordWrap(false)
	row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.amount:SetPoint("LEFT", 360, 0)
	row.amount:SetWidth(64)
	row.amount:SetJustifyH("RIGHT")
	-- Health after the hit: a flat bar coloured by how much is left
	row.hp = CreateFrame("StatusBar", nil, row)
	row.hp:SetPoint("LEFT", 434, 0)
	row.hp:SetSize(64, 12)
	row.hp:SetStatusBarTexture(FLAT)
	local hpBg = row.hp:CreateTexture(nil, "BACKGROUND")
	hpBg:SetAllPoints()
	hpBg:SetColorTexture(1, 1, 1, 0.08)
	row.hpText = row.hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.hpText:SetPoint("CENTER", 0, 0)
	row:EnableMouse(true)
	row:SetScript("OnEnter", rowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

-- One attacker in the Compact view: icon of their biggest hit, name, hits, share bar, total
local function createSourceRow()
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(WIDTH - 20, 24)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 30, 0)
	row.name:SetWidth(170)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.hits = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.hits:SetPoint("LEFT", 204, 0)
	row.hits:SetWidth(54)
	row.hits:SetJustifyH("LEFT")
	row.hits:SetTextColor(0.62, 0.62, 0.62)
	row.track = row:CreateTexture(nil, "BACKGROUND")
	row.track:SetPoint("LEFT", 262, 0)
	row.track:SetSize(160, 8)
	row.track:SetColorTexture(1, 1, 1, 0.08)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("LEFT", row.track, "LEFT")
	row.bar:SetHeight(8)
	row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.total:SetPoint("RIGHT", -6, 0)
	row.total:SetWidth(70)
	row.total:SetJustifyH("RIGHT")
	return row
end

local function createWindow()
	frame = CreateFrame("Frame", "dgksDeathRecapFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 120)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		dgks.db.profile.deathRecapPos = { point, relPoint, x, y }
	end)
	-- Flat dark panel with a thin border and a red strip along the top
	frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	frame:SetBackdropColor(0.05, 0.05, 0.06, 0.94)
	frame:SetBackdropBorderColor(0, 0, 0, 1)
	local strip = frame:CreateTexture(nil, "ARTWORK")
	strip:SetPoint("TOPLEFT", 1, -1)
	strip:SetPoint("TOPRIGHT", -1, -1)
	strip:SetHeight(3)
	strip:SetColorTexture(KILL_RED[1], KILL_RED[2], KILL_RED[3], 1)

	local skull = frame:CreateTexture(nil, "ARTWORK")
	skull:SetTexture(SKULL)
	skull:SetSize(30, 30)
	skull:SetPoint("TOPLEFT", 12, -12)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", skull, "TOPRIGHT", 8, 0)
	frame.title:SetPoint("RIGHT", -110, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)

	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.subtitle:SetPoint("RIGHT", -12, 0)
	frame.subtitle:SetJustifyH("LEFT")
	frame.subtitle:SetTextColor(0.75, 0.75, 0.75)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", fadeOut)

	-- Compact / full list switch
	local mode = CreateFrame("Button", nil, frame)
	mode:SetSize(74, 20)
	mode:SetPoint("TOPRIGHT", -32, -8)
	local modeBg = mode:CreateTexture(nil, "BACKGROUND")
	modeBg:SetAllPoints()
	modeBg:SetColorTexture(1, 1, 1, 0.06)
	local modeHl = mode:CreateTexture(nil, "HIGHLIGHT")
	modeHl:SetAllPoints()
	modeHl:SetColorTexture(1, 1, 1, 0.1)
	mode.label = mode:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mode.label:SetPoint("CENTER")
	mode:SetScript("OnClick", function()
		dgks.db.profile.deathRecapCompact = not dgks.db.profile.deathRecapCompact
		if lastRecap then dgks:RenderDeathRecap(lastRecap) end
	end)
	mode:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(dgks.db.profile.deathRecapCompact and "Show every hit" or "Show the killing blow and who did the most damage")
		GameTooltip:Show()
	end)
	mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.mode = mode

	-- Column headings
	local headers = {
		{ "Time", 12, 44, "RIGHT" }, { "Ability", 82, 160, "LEFT" }, { "Attacker", 246, 120, "LEFT" },
		{ "Damage", 370, 64, "RIGHT" }, { "Health", 444, 64, "CENTER" },
	}
	for _, h in ipairs(headers) do
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", h[2], HEADER_Y)
		fs:SetWidth(h[3])
		fs:SetJustifyH(h[4])
		fs:SetText(h[1])
	end
	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("TOPLEFT", 10, HEADER_Y - 12)
	rule:SetPoint("TOPRIGHT", -10, HEADER_Y - 12)
	rule:SetHeight(1)
	rule:SetColorTexture(1, 1, 1, 0.12)

	frame.sourceTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.sourceTitle:SetJustifyH("LEFT")

	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.footer:SetPoint("BOTTOMLEFT", 12, 10)
	frame.footer:SetPoint("RIGHT", -12, 0)
	frame.footer:SetJustifyH("LEFT")

	rowFrames, sourceFrames = {}, {}
	for i = 1, MAX_ROWS do rowFrames[i] = createRow() end
	for i = 1, TOP_SOURCES do sourceFrames[i] = createSourceRow() end

	frame.fadeIn = alphaAnimation(frame, 0, 1, 0.25)
	frame.fadeOut = alphaAnimation(frame, 1, 0, 0.2)
	frame.fadeOut:SetScript("OnFinished", function() frame:Hide() end)

	-- Close with Escape
	tinsert(UISpecialFrames, "dgksDeathRecapFrame")
	frame:Hide()
end

local function place()
	frame:ClearAllPoints()
	local pos = dgks.db.profile.deathRecapPos
	if type(pos) == "table" and pos[1] then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
end

local function fillRow(row, d, y, stripe, killingBlow)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
	row.data = d
	row.killingBlow = killingBlow
	row.stripe:SetShown(stripe and not killingBlow)
	row.kbWash:SetShown(killingBlow)
	row.kbEdge:SetShown(killingBlow)
	row.skull:SetShown(killingBlow)
	if num(d.ago) then
		row.time:SetText(d.ago < 0.05 and "0.0s" or ("-%.1fs"):format(d.ago))
	else
		row.time:SetText("")
	end
	local text, icon = ability(d)
	setText(row.ability, text or "Unknown")
	row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	if d.source == nil then
		row.source:SetText(d.env ~= nil and "" or "|cff9d9d9dHidden|r")
	else
		setText(row.source, d.source)
	end
	setText(row.amount, d.amount, function(v)
		local s = "-" .. short(v)
		if d.crit == true then s = s .. "*" end
		return s
	end)
	local color = schoolInfo(d.school) or DEFAULT_DAMAGE_COLOR
	row.amount:SetTextColor(color[1], color[2], color[3])
	-- Health after the hit
	if num(d.hp) and num(d.hpMax) and d.hpMax > 0 then
		local fraction = math.max(0, d.hp) / d.hpMax
		row.hp:SetMinMaxValues(0, d.hpMax)
		row.hp:SetValue(math.max(0, d.hp))
		row.hp:SetStatusBarColor(healthColor(fraction))
		row.hpText:SetText(("%d%%"):format(math.floor(fraction * 100 + 0.5)))
		row.hp:Show()
	elseif d.hp ~= nil and isSecret(d.hp) then
		pcall(row.hp.SetMinMaxValues, row.hp, 0, d.hpMax or 1)
		pcall(row.hp.SetValue, row.hp, d.hp)
		row.hp:SetStatusBarColor(0.2, 0.75, 0.25)
		row.hpText:SetText("")
		row.hp:Show()
	else
		row.hp:Hide()
	end
	row:Show()
end

-- The attackers who did the most damage, biggest first, and the total of all damage. Nil when an
-- amount or a name is secret: secret values cannot be added up or used as keys.
local function topSources(rows)
	local byKey, list, total = {}, {}, 0
	for _, d in ipairs(rows) do
		if not num(d.amount) or isSecret(d.source) or isSecret(d.env) then return nil end
		local key, name
		if d.source ~= nil then
			key, name = "p:" .. tostring(d.source), d.source
		elseif d.env ~= nil then
			key = "e:" .. tostring(d.env)
			name = ENV_TEXT[tostring(d.env):upper()] or tostring(d.env)
		else
			key, name = "hidden", "|cff9d9d9dHidden|r"
		end
		local s = byKey[key]
		if not s then
			s = { name = name, total = 0, hits = 0, biggest = -1 }
			byKey[key] = s
			list[#list + 1] = s
		end
		s.total = s.total + d.amount
		s.hits = s.hits + 1
		if d.amount > s.biggest then s.biggest, s.hit = d.amount, d end
		total = total + d.amount
	end
	table.sort(list, function(a, b) return a.total > b.total end)
	return list, total
end

local function fillSource(row, s, y, total)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
	local _, icon = ability(s.hit)
	row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.name:SetText(s.name)
	row.hits:SetText(s.hits == 1 and "1 hit" or (s.hits .. " hits"))
	local color = schoolInfo(s.hit.school) or DEFAULT_DAMAGE_COLOR
	row.bar:SetWidth(math.max(2, 160 * s.total / math.max(total, 1)))
	row.bar:SetColorTexture(color[1], color[2], color[3], 0.85)
	row.total:SetText(short(s.total))
	row.total:SetTextColor(color[1], color[2], color[3])
	row:Show()
end

local function render(recap)
	if not frame then createWindow() end
	local rows = recap.rows
	local compact = dgks.db.profile.deathRecapCompact == true
	frame.mode.label:SetText(compact and "Full list" or "Compact")
	for _, r in ipairs(rowFrames) do r:Hide() end
	for _, r in ipairs(sourceFrames) do r:Hide() end
	frame.sourceTitle:Hide()

	local y = FIRST_ROW_Y
	local notes = {}
	if compact then
		-- The killing blow, then who did the most damage
		if rows[#rows] then
			fillRow(rowFrames[1], rows[#rows], y, false, true)
			y = y - ROW_HEIGHT
		end
		if #rows > 0 then
			y = y - 12
			frame.sourceTitle:ClearAllPoints()
			frame.sourceTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
			frame.sourceTitle:Show()
			y = y - 20
			local list, total = topSources(rows)
			if list then
				frame.sourceTitle:SetText("Most damage")
				for i = 1, math.min(TOP_SOURCES, #list) do
					fillSource(sourceFrames[i], list[i], y, total)
					y = y - 24
				end
			else
				-- Secret amounts cannot be added up: show the hits before the killing blow instead
				frame.sourceTitle:SetText("Hits before the killing blow")
				local from = math.max(1, #rows - TOP_SOURCES)
				for i = from, #rows - 1 do
					fillRow(rowFrames[i - from + 2], rows[i], y, (i - from) % 2 == 1, false)
					y = y - ROW_HEIGHT
				end
			end
		end
	else
		local shown = math.min(#rows, MAX_ROWS)
		local first = #rows - shown + 1 -- keep the newest hits, ending with the killing blow
		for i = 1, shown do
			fillRow(rowFrames[i], rows[first + i - 1], y, i % 2 == 0, first + i - 1 == #rows)
			y = y - ROW_HEIGHT
		end
		if #rows > MAX_ROWS then notes[#notes + 1] = ("%d earlier hits not shown."):format(#rows - MAX_ROWS) end
	end
	if #rows == 0 then y = y - ROW_HEIGHT end

	-- Title: who killed us, with their class and spec when known
	local title = "|cffff4040You died|r" .. (recap.killer and (" - " .. recap.killer) or "")
	local rec = recap.record
	if rec and not dgks.History.IsUnknown(rec) and (rec.oc or rec.os) then
		local cs = dgks.History.ClassSpecText(rec.oc, rec.os)
		local c = rec.oc and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.oc]
		if c then cs = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, cs) end
		if cs ~= "" then title = title .. " (" .. cs .. ")" end
	end
	frame.title:SetText(title)

	-- Total damage in the window, when every amount is readable
	local total, readable = 0, true
	for _, d in ipairs(rows) do
		if num(d.amount) then total = total + d.amount elseif d.amount ~= nil then readable = false end
	end
	local sub
	if #rows == 0 then
		sub = "No damage was recorded before this death."
	elseif readable then
		sub = ("%d %s, %s damage in the last %d seconds"):format(#rows, #rows == 1 and "hit" or "hits", short(total), WINDOW)
	else
		sub = ("%d %s in the last %d seconds"):format(#rows, #rows == 1 and "hit" or "hits", WINDOW)
	end
	-- Where it happened
	local where = rec and dgks.History.LocationText(rec) or ""
	if where ~= "" then sub = where .. "  |  " .. sub end
	frame.subtitle:SetText(sub)

	if recap.source == "blizzard" then notes[#notes + 1] = "From Blizzard's Death Recap, which keeps only the last few hits." end
	notes[#notes + 1] = "* critical hit. Reopen with /dgks deathrecap."
	frame.footer:SetText(table.concat(notes, " "))

	frame:SetHeight(-y + 30)
	place()
	if not frame:IsShown() then
		frame.fadeOut:Stop()
		frame:SetAlpha(1)
		frame:Show()
		frame.fadeIn:Play()
	end
end

function dgks:RenderDeathRecap(recap)
	local ok, err = pcall(render, recap)
	--@debug@
	if not ok then dgks:Print("DEBUG: death recap window failed: " .. tostring(err)) end
	--@end-debug@
end

-- Called when the player dies. killer is the text recorded as the killer (or nil).
-- record: the history record of this death (for the killer's class and spec, and the location)
function dgks:ShowDeathRecap(killer, record)
	local rows = fromCombatLog(GetTime())
	local source = "combatlog"
	if #rows == 0 then
		rows = fromDeathRecap()
		source = "blizzard"
	end
	lastRecap = { rows = rows, killer = killer, source = source, record = record }
	if dgks.db.profile.deathRecap then dgks:RenderDeathRecap(lastRecap) end
end

-- /dgks deathrecap: reopen the last recap
function dgks:ToggleDeathRecap()
	if frame and frame:IsShown() then
		fadeOut()
	elseif lastRecap then
		dgks:RenderDeathRecap(lastRecap)
	else
		dgks:Print("No death recap yet this session.")
	end
end

-- Close the recap when the player is alive again: a resurrection accepted, a soulstone or
-- Reincarnation, the spirit healer, or a corpse run. PLAYER_ALIVE also fires on releasing to a
-- ghost, so the recap stays open until the player is actually back.
local aliveWatcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do pcall(aliveWatcher.RegisterEvent, aliveWatcher, event) end
aliveWatcher:SetScript("OnEvent", function()
	if not UnitIsDeadOrGhost("player") then fadeOut() end
end)
