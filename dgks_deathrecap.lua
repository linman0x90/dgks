-- dG KillShot death recap window: opens when you die and lists the damage you took in the last
-- WINDOW seconds, oldest first, ending with the killing blow.
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

local taken = {} -- { t = GetTime(), source, spell, spellId, env, amount, overkill, absorbed, resisted, blocked, crit, hp, hpMax }

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
		hit.amount, hit.overkill, _, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
		hit.swing = true
	elseif kind == "spell" then
		-- spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical
		hit.spellId, hit.spell, _, hit.amount, hit.overkill, _, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
	else
		-- environmentalType, amount, overkill, school, resisted, blocked, absorbed, critical
		hit.env, hit.amount, hit.overkill, _, hit.resisted, hit.blocked, hit.absorbed, hit.crit = select(12, ...)
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

-- Window -----------------------------------------------------------------------------------------

local frame, rowsFrames, lastRecap

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
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
	frame:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", 12, -10)
	frame.title:SetPoint("RIGHT", -34, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)

	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
	frame.subtitle:SetPoint("RIGHT", -12, 0)
	frame.subtitle:SetJustifyH("LEFT")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	-- Column headers
	local headers = {
		{ "Time", 12, 44, "RIGHT" }, { "Ability", 82, 160, "LEFT" }, { "Attacker", 246, 120, "LEFT" },
		{ "Damage", 370, 64, "RIGHT" }, { "Health", 442, 64, "RIGHT" },
	}
	for _, h in ipairs(headers) do
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", h[2], -52)
		fs:SetWidth(h[3])
		fs:SetJustifyH(h[4])
		fs:SetText(h[1])
	end

	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.footer:SetPoint("BOTTOMLEFT", 12, 10)
	frame.footer:SetPoint("RIGHT", -12, 0)
	frame.footer:SetJustifyH("LEFT")

	rowsFrames = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(WIDTH - 20, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 10, -66 - (i - 1) * ROW_HEIGHT)
		if i % 2 == 0 then
			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(1, 1, 1, 0.04)
		end
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
		row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.amount:SetPoint("LEFT", 360, 0)
		row.amount:SetWidth(64)
		row.amount:SetJustifyH("RIGHT")
		row.amount:SetTextColor(1, 0.3, 0.3)
		row.hp = CreateFrame("StatusBar", nil, row)
		row.hp:SetPoint("LEFT", 434, 0)
		row.hp:SetSize(62, 12)
		row.hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		row.hp:SetStatusBarColor(0.1, 0.8, 0.1)
		local hpBg = row.hp:CreateTexture(nil, "BACKGROUND")
		hpBg:SetAllPoints()
		hpBg:SetColorTexture(0.2, 0, 0, 0.8)
		row.hpText = row.hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.hpText:SetPoint("CENTER")
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if not self.data then return end
			local d = self.data
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(function()
				local text = ability(d)
				GameTooltip:AddLine(text or "Unknown ability")
				local function line(label, v, fmt)
					if v == nil then return end
					if isSecret(v) then
						GameTooltip:AddDoubleLine(label, v, 1, 1, 1, 1, 1, 1)
					elseif not num(v) or v > 0 then
						GameTooltip:AddDoubleLine(label, fmt and fmt(v) or tostring(v), 1, 1, 1, 1, 1, 1)
					end
				end
				line("Attacker", d.source)
				line("Damage", d.amount, short)
				line("Overkill", d.overkill, short)
				line("Absorbed", d.absorbed, short)
				line("Resisted", d.resisted, short)
				line("Blocked", d.blocked, short)
				if d.crit == true then GameTooltip:AddLine("Critical hit", 1, 0.82, 0) end
				if d.ago == nil then GameTooltip:AddLine("Time not available here", 0.6, 0.6, 0.6) end
			end)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rowsFrames[i] = row
	end

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

local function fillRow(row, d)
	row.data = d
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
	-- Health after the hit
	if num(d.hp) and num(d.hpMax) and d.hpMax > 0 then
		row.hp:SetMinMaxValues(0, d.hpMax)
		row.hp:SetValue(math.max(0, d.hp))
		row.hpText:SetText(("%d%%"):format(math.max(0, math.floor(d.hp / d.hpMax * 100 + 0.5))))
		row.hp:Show()
	elseif d.hp ~= nil and isSecret(d.hp) then
		pcall(row.hp.SetMinMaxValues, row.hp, 0, d.hpMax or 1)
		pcall(row.hp.SetValue, row.hp, d.hp)
		row.hpText:SetText("")
		row.hp:Show()
	else
		row.hp:Hide()
	end
	row:Show()
end

local function render(recap)
	if not frame then createWindow() end
	local rows = recap.rows
	local shown = math.min(#rows, MAX_ROWS)
	local first = #rows - shown + 1 -- keep the newest hits, ending with the killing blow
	for i = 1, MAX_ROWS do
		local d = rows[first + i - 1]
		if i <= shown and d then fillRow(rowsFrames[i], d) else rowsFrames[i]:Hide() end
	end

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

	local notes = {}
	if #rows > MAX_ROWS then notes[#notes + 1] = ("%d earlier hits not shown."):format(#rows - MAX_ROWS) end
	if recap.source == "blizzard" then notes[#notes + 1] = "From Blizzard's Death Recap, which keeps only the last few hits." end
	notes[#notes + 1] = "* critical hit. Reopen with /dgks deathrecap."
	frame.footer:SetText(table.concat(notes, " "))

	frame:SetHeight(66 + math.max(shown, 1) * ROW_HEIGHT + 28)
	place()
	frame:Show()
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
	if dgks.db.profile.deathRecap then
		local ok, err = pcall(render, lastRecap)
		--@debug@
		if not ok then dgks:Print("DEBUG: death recap window failed: " .. tostring(err)) end
		--@end-debug@
	end
end

-- /dgks deathrecap: reopen the last recap
function dgks:ToggleDeathRecap()
	if frame and frame:IsShown() then
		frame:Hide()
	elseif lastRecap then
		render(lastRecap)
	else
		dgks:Print("No death recap yet this session.")
	end
end
