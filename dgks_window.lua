-- The dG KillShot window: Overview, History and Settings tabs. Opened by /dgks and the minimap button.
--
-- Built from Blizzard's own templates, which every supported client shares: ButtonFrameTemplate
-- (portrait frame with title, close button and inset), PanelTabButtonTemplate (the tabs under
-- the window) and a ScrollBox list with the slim MinimalScrollBar. It looks like a game window,
-- and UI skins that restyle game windows restyle it too. Settings are the AceConfig table, drawn
-- into the Settings tab by AceConfigDialog.

local dgks = dgks
local H = dgks.History
local AceGUI = LibStub("AceGUI-3.0")

local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local SETTINGS_APP = "dG KillShot Settings"
local WIDTH, HEIGHT = 900, 610
local ROW_HEIGHT, HEADER_HEIGHT = 20, 24
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

-- Colours used across the window
local C = {
	gold = { 1, 0.82, 0 },
	kill = { 0.25, 1, 0.25 },
	death = { 1, 0.25, 0.25 },
	duel = { 0.63, 0.63, 1 },
	team = { 0.38, 0.75, 1 },
	worst = { 1, 0.5, 0.25 },
	white = { 1, 1, 1 },
	label = { 0.62, 0.62, 0.62 },
	dim = { 0.45, 0.45, 0.45 },
}
local RANK_COLORS = { { 1, 0.82, 0 }, { 0.78, 0.78, 0.81 }, { 0.85, 0.57, 0.35 }, C.label, C.label } -- gold, silver, bronze

local TAB_KEYS = { "overview", "history", "settings" }
local TAB_NAMES = { overview = "Overview", history = "History", settings = "Settings" }

local frame                 -- the window, made the first time it opens
local panels = {}           -- [tab key] = panel frame inside the inset
local current = "overview"  -- the tab showing, remembered while the window is closed

-- Helpers ---------------------------------------------------------------------------------------

local function playSound(name)
	if PlaySound and SOUNDKIT and SOUNDKIT[name] then pcall(PlaySound, SOUNDKIT[name]) end
end

local function colorTexture(tex, c, alpha)
	tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function background(f, alpha)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, alpha or 0.3)
	return bg
end

local function text(parent, font, c)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	if c then fs:SetTextColor(c[1], c[2], c[3]) end
	fs:SetWordWrap(false)
	return fs
end

local function colored(s, c)
	return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, s)
end

local function classColored(s, classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then return colored(s, { c.r, c.g, c.b }) end
	return s
end

local function plural(n, word)
	return n .. " " .. (n == 1 and word or word .. "s")
end

local function ago(t)
	local s = time() - t
	if s < 60 then return "just now" end
	if s < 3600 then return math.floor(s / 60) .. "m ago" end
	if s < 86400 then return math.floor(s / 3600) .. "h ago" end
	if s < 30 * 86400 then return math.floor(s / 86400) .. "d ago" end
	return date("%b %d", t)
end

-- A player icon texture (spec, class or question mark), for frames that are not text
local function setIcon(tex, classFile, specID)
	local file, l, r, t, b = H.ClassIconTexture(classFile, specID)
	tex:SetTexture(file)
	tex:SetTexCoord(l, r, t, b)
end

local function showTooltip(owner, fill)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = pcall(fill, GameTooltip)
	if ok and GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

-- A flat toggle button for picking a view or a filter. Selected: gold text and underline.
local function chip(parent, label, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(22)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetPoint("BOTTOMLEFT")
	b.line:SetPoint("BOTTOMRIGHT")
	b.line:SetHeight(2)
	colorTexture(b.line, C.gold)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	b.label = text(b, "GameFontHighlightSmall")
	b.label:SetPoint("CENTER", 0, 1)
	b.label:SetText(label)
	b:SetWidth(math.max(36, math.ceil(b.label:GetStringWidth()) + 20))
	function b:SetSelected(on)
		self.line:SetShown(on)
		self.bg:SetColorTexture(1, 1, 1, on and 0.12 or 0.04)
		local c = on and C.gold or { 0.85, 0.85, 0.85 }
		self.label:SetTextColor(c[1], c[2], c[3])
	end
	b:SetScript("OnClick", onClick)
	b:SetSelected(false)
	return b
end

-- A row of chips for one choice. items: { { value =, text = }, ... }
local function chipRow(parent, items, get, set)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(22)
	row.chips = {}
	local x = 0
	for _, item in ipairs(items) do
		local c = chip(row, item.text, function()
			playSound("U_CHAT_SCROLL_BUTTON")
			set(item.value)
			row:Refresh()
		end)
		c.value = item.value
		c:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + c:GetWidth() + 2
		row.chips[#row.chips + 1] = c
	end
	row:SetWidth(math.max(1, x - 2))
	function row:Refresh()
		local v = get()
		for _, c in ipairs(self.chips) do c:SetSelected(c.value == v) end
	end
	row:Refresh()
	return row
end

local function items(list, order)
	local out = {}
	for _, value in ipairs(order) do out[#out + 1] = { value = value, text = list[value] } end
	return out
end

-- History tab -----------------------------------------------------------------------------------

local filter = H.Filter
local RETAIN = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition

local function sortRows(rows, state, columns)
	for i, row in ipairs(rows) do row.index = i end
	if state and columns[state.col] then
		local c, desc = state.col, state.desc
		table.sort(rows, function(a, b)
			local va, vb = a.sort[c], b.sort[c]
			if va == vb then return a.index < b.index end
			if desc then return va > vb end
			return va < vb
		end)
	end
	for i, row in ipairs(rows) do row.stripe = i % 2 == 0 end
end

-- Column x positions and widths for the current view, from the list width
local function columnLayout(p)
	local width = p.scrollBox:GetWidth()
	if not width or width <= 0 then width = p.header:GetWidth() end
	local out, x = {}, 0
	for i, col in ipairs(H.Views[filter.tab].columns) do
		local w = width * col.width
		out[i] = { x = x, w = w, align = col.align or "LEFT" }
		x = x + w
	end
	return out
end

local function refreshHistory(resetScroll)
	local p = panels.history
	if not p or not p:IsShown() then return end
	local def = H.Views[filter.tab]
	local rows = H:ViewRows(filter.tab)
	sortRows(rows, filter.sort[filter.tab], def.columns)
	p.scrollBox:SetDataProvider(CreateDataProvider(rows), (not resetScroll) and RETAIN or nil)
	p.empty:SetShown(#rows == 0)
end

local function layoutHeaders(p)
	local layout = columnLayout(p)
	local state = filter.sort[filter.tab]
	for i, col in ipairs(H.Views[filter.tab].columns) do
		local b = p.headers[i]
		if not b then
			b = CreateFrame("Button", nil, p.header)
			b:SetHeight(HEADER_HEIGHT)
			b.label = text(b, "GameFontNormalSmall")
			b.arrow = b:CreateTexture(nil, "OVERLAY")
			b.arrow:SetTexture(SORT_ARROW)
			b.arrow:SetSize(9, 8)
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.06)
			b:SetScript("OnClick", function(self)
				local s = filter.sort[filter.tab]
				if s.col == self.col then
					s.desc = not s.desc
				else
					s.col = self.col
					s.desc = H.Views[filter.tab].columns[self.col].desc ~= false
				end
				playSound("U_CHAT_SCROLL_BUTTON")
				layoutHeaders(p)
				refreshHistory(false)
			end)
			p.headers[i] = b
		end
		local pos = layout[i]
		b.col = i
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", p.header, "TOPLEFT", pos.x, 0)
		b:SetWidth(math.max(1, pos.w))
		b.label:SetText(col.title)
		b.label:ClearAllPoints()
		b.arrow:ClearAllPoints()
		if pos.align == "RIGHT" then
			b.label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
			b.arrow:SetPoint("RIGHT", b.label, "LEFT", -3, 0)
		else
			b.label:SetPoint("LEFT", b, "LEFT", 6, 0)
			b.arrow:SetPoint("LEFT", b.label, "RIGHT", 3, 0)
		end
		local sorted = state.col == i
		b.arrow:SetShown(sorted)
		-- The arrow art points down; flipped for ascending
		if sorted and not state.desc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end
		local c = sorted and C.white or C.gold
		b.label:SetTextColor(c[1], c[2], c[3])
		b:Show()
	end
	for i = #H.Views[filter.tab].columns + 1, #p.headers do p.headers[i]:Hide() end
end

local function initRow(p, row, item)
	if not row.cells then
		row.cells = {}
		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		row.stripe:SetColorTexture(1, 1, 1, 0.035)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.1)
		row:SetScript("OnEnter", function(self)
			if self.item and self.item.tip then showTooltip(self, self.item.tip) end
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	row.item = item
	row.stripe:SetShown(item.stripe == true)
	local layout = columnLayout(p)
	for i, pos in ipairs(layout) do
		local cell = row.cells[i]
		if not cell then
			cell = text(row, "GameFontHighlightSmall")
			row.cells[i] = cell
		end
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", row, "LEFT", pos.x + 6, 0)
		cell:SetWidth(math.max(1, pos.w - 12))
		cell:SetJustifyH(pos.align)
		cell:SetText(item.cells[i] or "")
		cell:Show()
	end
	for i = #layout + 1, #row.cells do row.cells[i]:Hide() end
end

local function searchBox(parent)
	local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
	if not ok then
		box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	end
	box:SetSize(210, 20)
	box:SetAutoFocus(false)
	if box.Instructions then box.Instructions:SetText("Search names, zones, classes") end
	return box
end

local function createHistory(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()
	p.headers = {}

	-- View picker, in the space beside the portrait
	p.views = chipRow(p, H.VIEW_ORDER, function() return filter.tab end, function(v)
		filter.tab = v
		p.kinds:SetShown(not H.Views[v].noKindFilter)
		layoutHeaders(p)
		refreshHistory(true)
	end)
	p.views:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -32)

	-- Filters
	p.search = searchBox(p)
	p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -9)
	p.search:SetText(filter.search)
	p.search:HookScript("OnTextChanged", function(self)
		local s = (self:GetText() or ""):lower()
		if s ~= filter.search then
			filter.search = s
			refreshHistory(true)
		end
	end)
	p.search:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
	p.search:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)

	p.kinds = chipRow(p, items(H.KIND_FILTERS, H.KIND_ORDER), function() return filter.kind end, function(v)
		filter.kind = v
		refreshHistory(true)
	end)
	p.kinds:SetPoint("LEFT", p.search, "RIGHT", 18, 0)

	p.periods = chipRow(p, items(H.PERIODS, H.PERIOD_ORDER), function() return filter.period end, function(v)
		filter.period = v
		refreshHistory(true)
	end)
	p.periods:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -8)

	-- The list: column headers over a ScrollBox
	local list = CreateFrame("Frame", nil, p)
	list:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -38)
	list:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)
	background(list, 0.25)

	p.header = CreateFrame("Frame", nil, list)
	p.header:SetPoint("TOPLEFT")
	p.header:SetPoint("TOPRIGHT", list, "TOPRIGHT", -16, 0)
	p.header:SetHeight(HEADER_HEIGHT)
	background(p.header, 0.35)
	local rule = p.header:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	colorTexture(rule, C.gold, 0.35)

	p.scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	p.scrollBox:SetPoint("TOPLEFT", p.header, "BOTTOMLEFT", 0, -1)
	p.scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -16, 2)
	p.scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	p.scrollBar:SetPoint("TOPLEFT", p.scrollBox, "TOPRIGHT", 5, -2)
	p.scrollBar:SetPoint("BOTTOMLEFT", p.scrollBox, "BOTTOMRIGHT", 5, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", function(row, item) initRow(p, row, item) end)
	ScrollUtil.InitScrollBoxListWithScrollBar(p.scrollBox, p.scrollBar, view)

	p.empty = text(p.scrollBox, "GameFontDisable")
	p.empty:SetPoint("TOP", p.scrollBox, "TOP", 0, -30)
	p.empty:SetText("No records match these filters.")

	p:SetScript("OnShow", function()
		p.views:Refresh()
		p.kinds:Refresh()
		p.periods:Refresh()
		p.kinds:SetShown(not H.Views[filter.tab].noKindFilter)
		layoutHeaders(p)
		refreshHistory(true)
	end)
	p:SetScript("OnSizeChanged", function()
		if p:IsShown() then
			layoutHeaders(p)
			refreshHistory(false)
		end
	end)
	return p
end

-- Overview tab ----------------------------------------------------------------------------------

-- A stat card: a coloured strip, a small label and a big number
local function card(parent, label, c, big)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(big and 70 or 52)
	background(f, 0.3)
	local strip = f:CreateTexture(nil, "ARTWORK")
	strip:SetPoint("TOPLEFT")
	strip:SetPoint("BOTTOMLEFT")
	strip:SetWidth(3)
	colorTexture(strip, c)
	f.label = text(f, "GameFontNormalSmall", C.label)
	f.label:SetPoint("TOPLEFT", 14, big and -10 or -8)
	f.label:SetText(label:upper())
	f.value = text(f, big and "GameFontNormalHuge" or "GameFontNormalLarge", c)
	f.value:SetPoint("BOTTOMLEFT", 14, big and 10 or 8)
	f.note = text(f, "GameFontHighlightSmall", C.label)
	f.note:SetPoint("BOTTOMRIGHT", -10, big and 12 or 9)
	return f
end

-- A titled box for the lists along the bottom
local function box(parent, title)
	local f = CreateFrame("Frame", nil, parent)
	background(f, 0.3)
	f.title = text(f, "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetText(title)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("TOPLEFT", 12, -28)
	rule:SetPoint("TOPRIGHT", -12, -28)
	rule:SetHeight(1)
	colorTexture(rule, C.gold, 0.25)
	f.empty = text(f, "GameFontDisableSmall")
	f.empty:SetPoint("TOPLEFT", 12, -40)
	f.rows = {}
	return f
end

-- Row n of a Top 5 list: rank, icon, name, a bar sized by count, the count
local function topRow(f, n)
	local r = f.rows[n]
	if r then return r end
	r = CreateFrame("Frame", nil, f)
	r:SetHeight(22)
	r:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34 - (n - 1) * 24)
	r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34 - (n - 1) * 24)
	r.rank = text(r, "GameFontNormal", RANK_COLORS[n])
	r.rank:SetPoint("LEFT", 0, 0)
	r.rank:SetWidth(14)
	r.rank:SetText(n)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 18, 0)
	r.name = text(r, "GameFontHighlight")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetWidth(110)
	r.name:SetJustifyH("LEFT")
	r.count = text(r, "GameFontHighlight")
	r.count:SetPoint("RIGHT", 0, 0)
	r.count:SetWidth(28)
	r.count:SetJustifyH("RIGHT")
	r.track = r:CreateTexture(nil, "BACKGROUND")
	r.track:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
	r.track:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
	r.track:SetHeight(6)
	r.track:SetColorTexture(1, 1, 1, 0.06)
	r.bar = r:CreateTexture(nil, "ARTWORK")
	r.bar:SetPoint("LEFT", r.track, "LEFT")
	r.bar:SetHeight(6)
	f.rows[n] = r
	return r
end

local function fillTop(f, list, c, emptyText)
	local maxCount = list[1] and list[1].count or 1
	local trackWidth
	for n = 1, 5 do
		local o = list[n]
		local r = topRow(f, n)
		if o then
			setIcon(r.icon, o.class, o.spec)
			r.name:SetText(classColored(o.name, o.class))
			r.count:SetText(o.count)
			r.count:SetTextColor(c[1], c[2], c[3])
			trackWidth = trackWidth or r.track:GetWidth()
			if not trackWidth or trackWidth <= 0 then trackWidth = f:GetWidth() - 24 - 18 - 18 - 6 - 110 - 6 - 6 - 28 end
			r.bar:SetWidth(math.max(2, trackWidth * o.count / maxCount))
			colorTexture(r.bar, c, 0.8)
			r:Show()
		else
			r:Hide()
		end
	end
	f.empty:SetText(emptyText)
	f.empty:SetShown(#list == 0)
end

local RECENT_VERBS = {
	K = { "Killed", C.kill }, D = { "Killed by", C.death }, W = { "Won a duel against", C.duel },
	L = { "Lost a duel to", C.worst }, X = { "Team kill:", C.team },
}

local function fillRecent(f, recent)
	for n = 1, 6 do
		local rec = recent[n]
		local r = f.rows[n]
		if not r then
			r = CreateFrame("Frame", nil, f)
			r:SetHeight(20)
			r:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34 - (n - 1) * 21)
			r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34 - (n - 1) * 21)
			r.dot = r:CreateTexture(nil, "ARTWORK")
			r.dot:SetSize(3, 14)
			r.dot:SetPoint("LEFT")
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(16, 16)
			r.icon:SetPoint("LEFT", 8, 0)
			r.when = text(r, "GameFontHighlightSmall", C.label)
			r.when:SetPoint("RIGHT")
			r.what = text(r, "GameFontHighlightSmall")
			r.what:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
			r.what:SetPoint("RIGHT", r.when, "LEFT", -6, 0)
			r.what:SetJustifyH("LEFT")
			r:EnableMouse(true)
			r:SetScript("OnLeave", function() GameTooltip:Hide() end)
			f.rows[n] = r
		end
		if rec then
			local verb = RECENT_VERBS[rec.k] or { "?", C.white }
			colorTexture(r.dot, verb[2])
			local name = H.ShortName(rec.o)
			if H.IsUnknown(rec) then
				name = colored(name, C.dim)
			else
				name = classColored(name, rec.oc)
			end
			local line = colored(verb[1], verb[2]) .. " " .. name
			if rec.k == "X" and rec.kn then line = line .. colored(" by " .. H.ShortName(rec.kn), C.label) end
			setIcon(r.icon, rec.oc, rec.os)
			r.what:SetText(line)
			r.when:SetText(ago(rec.t))
			r:SetScript("OnEnter", function(self)
				showTooltip(self, function(tt)
					tt:AddLine((H.KIND_NAMES[rec.k] or "?") .. ": " .. H.ShortName(rec.o))
					tt:AddDoubleLine("When", date("%Y-%m-%d %H:%M", rec.t), 1, 1, 1, 1, 1, 1)
					local cs = H.ClassSpecText(rec.oc, rec.os)
					if cs ~= "" then tt:AddDoubleLine("Class", classColored(cs, rec.oc), 1, 1, 1, 1, 1, 1) end
					local where = H.LocationText(rec)
					if where ~= "" then tt:AddDoubleLine("Location", where, 1, 1, 1, 1, 1, 1) end
				end)
			end)
			r:Show()
		else
			r:Hide()
		end
	end
	f.empty:SetText("Nothing recorded yet")
	f.empty:SetShown(#recent == 0)
end

-- Kills and deaths per day as paired bars, with a tooltip per day
local function fillChart(f, days)
	local maxCount = 1
	for _, d in ipairs(days) do maxCount = math.max(maxCount, d.K, d.D) end
	local width = f:GetWidth() - 24
	local slot = width / #days
	local barWidth = math.max(3, math.min(14, (slot - 8) / 2))
	local chartHeight = f:GetHeight() - 34 - 18
	local any = false
	for i, d in ipairs(days) do
		local s = f.slots[i]
		if not s then
			s = CreateFrame("Frame", nil, f)
			s.kill = s:CreateTexture(nil, "ARTWORK")
			s.death = s:CreateTexture(nil, "ARTWORK")
			colorTexture(s.kill, C.kill, 0.85)
			colorTexture(s.death, C.death, 0.85)
			s.day = text(s, "GameFontHighlightSmall", C.label)
			s.day:SetPoint("BOTTOM", s, "BOTTOM", 0, 0)
			local hl = s:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.05)
			s:EnableMouse(true)
			s:SetScript("OnLeave", function() GameTooltip:Hide() end)
			f.slots[i] = s
		end
		s:ClearAllPoints()
		s:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12 + (i - 1) * slot, 8)
		s:SetSize(slot, chartHeight + 18)
		s.kill:ClearAllPoints()
		s.kill:SetPoint("BOTTOMRIGHT", s, "BOTTOM", -1, 16)
		s.kill:SetSize(barWidth, math.max(1, chartHeight * d.K / maxCount))
		s.kill:SetShown(d.K > 0)
		s.death:ClearAllPoints()
		s.death:SetPoint("BOTTOMLEFT", s, "BOTTOM", 1, 16)
		s.death:SetSize(barWidth, math.max(1, chartHeight * d.D / maxCount))
		s.death:SetShown(d.D > 0)
		s.day:SetText(i == #days and "Today" or date("%d", d.start))
		if i == #days then s.day:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
		s:SetScript("OnEnter", function(self)
			showTooltip(self, function(tt)
				tt:AddLine(date("%A, %B %d", d.start))
				tt:AddLine(plural(d.K, "kill"), C.kill[1], C.kill[2], C.kill[3])
				tt:AddLine(plural(d.D, "death"), C.death[1], C.death[2], C.death[3])
			end)
		end)
		if d.K > 0 or d.D > 0 then any = true end
	end
	f.baseline:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8 + 15)
	f.baseline:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8 + 15)
	f.empty:SetShown(not any)
end

local function createOverview(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()

	p.cards = {
		card(p, "Kills", C.kill, true),
		card(p, "Deaths", C.death, true),
		card(p, "K/D", C.gold, true),
		card(p, "Duels W-L", C.duel, true),
		card(p, "Kill streak", C.kill),
		card(p, "Best streak", C.gold),
		card(p, "Death streak", C.death),
		card(p, "Worst streak", C.worst),
	}

	p.chart = box(p, ("Last %d days"):format(H.ACTIVITY_DAYS))
	p.chart:SetHeight(140)
	p.chart.slots = {}
	p.chart.baseline = p.chart:CreateTexture(nil, "ARTWORK")
	p.chart.baseline:SetHeight(1)
	p.chart.baseline:SetColorTexture(1, 1, 1, 0.15)
	p.chart.empty:ClearAllPoints()
	p.chart.empty:SetPoint("CENTER", 0, 4)
	p.chart.empty:SetText(("No kills or deaths in the last %d days"):format(H.ACTIVITY_DAYS))
	local legend = text(p.chart, "GameFontHighlightSmall")
	legend:SetPoint("TOPRIGHT", -12, -12)
	legend:SetText(colored("Kills", C.kill) .. "     " .. colored("Deaths", C.death))

	p.prey = box(p, "Top prey")
	p.predators = box(p, "Top predators")
	p.recent = box(p, "Recent")

	p:SetScript("OnShow", function() dgks:RefreshMainWindow() end)
	return p
end

-- Place the cards and boxes for the panel's width
local function layoutOverview(p)
	local pad, gap = 12, 10
	local width = p:GetWidth() - pad * 2
	local w = (width - gap * 3) / 4
	for i, c in ipairs(p.cards) do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		c:ClearAllPoints()
		c:SetWidth(w)
		c:SetPoint("TOPLEFT", p, "TOPLEFT", pad + col * (w + gap), -pad - row * (70 + gap))
	end
	local y = -pad - 70 - gap - 52 - gap
	p.chart:ClearAllPoints()
	p.chart:SetPoint("TOPLEFT", p, "TOPLEFT", pad, y)
	p.chart:SetWidth(width)
	y = y - 140 - gap
	local w3 = (width - gap * 2) / 3
	for i, b in ipairs({ p.prey, p.predators, p.recent }) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", p, "TOPLEFT", pad + (i - 1) * (w3 + gap), y)
		b:SetSize(w3, math.max(160, p:GetHeight() + y - pad))
	end
end

local function refreshOverview()
	local p = panels.overview
	if not p or not p:IsShown() then return end
	layoutOverview(p)
	local s = H:OverviewStats(6)
	local t = s.totals
	local streak, deathstreak = dgks:GetStreaks()
	local profile = dgks.db.profile
	local cards = p.cards
	cards[1].value:SetText(t.K)
	cards[2].value:SetText(t.D)
	cards[3].value:SetText(("%.2f"):format(t.K / math.max(t.D, 1)))
	cards[4].value:SetText(t.W .. "-" .. t.L)
	cards[1].note:SetText(t.X > 0 and ("+" .. plural(t.X, "team kill")) or "")
	local duels = t.W + t.L
	cards[4].note:SetText(duels > 0 and (math.floor(t.W / duels * 100 + 0.5) .. "% won") or "")
	cards[5].value:SetText(streak)
	cards[6].value:SetText(profile.maxstreak or 0)
	cards[7].value:SetText(deathstreak)
	cards[8].value:SetText(profile.maxdeathstreak or 0)
	fillChart(p.chart, s.days)
	fillTop(p.prey, s.prey, C.kill, "No kills yet")
	fillTop(p.predators, s.predators, C.death, "No deaths yet")
	fillRecent(p.recent, s.recent)
end

-- Settings tab ----------------------------------------------------------------------------------
-- An AceGUI group inside the panel, which AceConfigDialog fills with the Settings table

-- Give the AceGUI group the panel's size and lay it out again. AceGUI's tab group sizes its tabs
-- from the width it was given; drawn into a frame the game has not measured yet, that width is 0
-- and every tab is squeezed against the left edge.
local function layoutSettings(p)
	local g = p.group
	if not g then return end
	local w, h = (p:GetWidth() or 0) - 12, (p:GetHeight() or 0) - 12
	if w <= 0 or h <= 0 then return end
	g:SetWidth(w)
	g:SetHeight(h)
	g:DoLayout()
end

local function createSettings(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints()
	p:SetScript("OnSizeChanged", function(self)
		if self:IsShown() then layoutSettings(self) end
	end)
	p:SetScript("OnShow", function(self)
		if not self.group then
			local g = AceGUI:Create("SimpleGroup")
			g:SetLayout("Fill")
			g:SetAutoAdjustHeight(false)
			g.frame:SetParent(self)
			g.frame:SetFrameStrata(self:GetFrameStrata())
			g.frame:SetFrameLevel(self:GetFrameLevel() + 2)
			g.frame:ClearAllPoints()
			g.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -6)
			g.frame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -6, 6)
			self.group = g
		end
		self.group.frame:Show()
		layoutSettings(self)
		LibStub("AceConfigDialog-3.0"):Open(SETTINGS_APP, self.group)
		-- Once more after the game has placed the window
		C_Timer.After(0, function()
			if self:IsShown() then layoutSettings(self) end
		end)
	end)
	-- Let go of the option widgets while another tab shows
	p:SetScript("OnHide", function(self)
		if self.group then self.group:ReleaseChildren() end
	end)
	return p
end

-- Window ----------------------------------------------------------------------------------------

local function updateStatus()
	if not frame then return end
	frame.status:SetText(H.StatusText())
	local name = UnitName("player") or ""
	local _, classFile = UnitClass("player")
	local guild = IsInGuild() and GetGuildInfo("player")
	frame.subtitle:SetText(classColored(name, classFile) .. (guild and colored("  <" .. guild .. ">", C.label) or ""))
end

local function selectTab(key)
	if not panels[key] then key = "overview" end
	current = key
	for i, k in ipairs(TAB_KEYS) do
		if k ~= key then panels[k]:Hide() end
		if k == key then PanelTemplates_SetTab(frame, i) end
	end
	panels[key]:Show()
	-- The history views take the space beside the portrait; the other tabs show who is playing
	frame.subtitle:SetShown(key ~= "history")
	updateStatus()
end

local function setPortrait(f)
	if f.SetPortraitToAsset then
		f:SetPortraitToAsset(ICON)
		return
	end
	local portrait = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
	if not portrait then return end
	if SetPortraitToTexture then SetPortraitToTexture(portrait, ICON) else portrait:SetTexture(ICON) end
end

local function createFrame()
	local f = CreateFrame("Frame", "dgksMainFrame", UIParent, "ButtonFrameTemplate")
	frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
	if f.SetTitle then f:SetTitle("dG KillShot") elseif title then title:SetText("dG KillShot") end
	setPortrait(f)

	-- Character name and guild beside the portrait
	f.subtitle = text(f, "GameFontHighlight")
	f.subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 72, -36)

	-- Status line and version in the bar under the inset
	f.status = text(f, "GameFontHighlightSmall", C.label)
	f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 8)
	local version = text(f, "GameFontDisableSmall")
	version:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 8)
	version:SetText(dgks.version and ("Version " .. dgks.version) or "")

	--@debug@
	local testKill = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	testKill:SetSize(110, 20)
	testKill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -150, 3)
	testKill:SetText("Simulate kill")
	testKill:SetScript("OnClick", function() dgks:Test() end)
	local testDeath = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	testDeath:SetSize(110, 20)
	testDeath:SetPoint("RIGHT", testKill, "LEFT", -4, 0)
	testDeath:SetText("Simulate death")
	testDeath:SetScript("OnClick", function() dgks:TestPlayerDeath() end)
	--@end-debug@

	local inset = f.Inset or f
	panels.overview = createOverview(inset)
	panels.history = createHistory(inset)
	panels.settings = createSettings(inset)
	for _, p in pairs(panels) do p:Hide() end

	-- Tabs under the window
	for i, key in ipairs(TAB_KEYS) do
		local tab = CreateFrame("Button", "dgksMainFrameTab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(TAB_NAMES[key])
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("TOPLEFT", _G["dgksMainFrameTab" .. (i - 1)], "TOPRIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function(self)
			playSound("IG_CHARACTER_INFO_TAB")
			selectTab(TAB_KEYS[self:GetID()])
		end)
	end
	PanelTemplates_SetNumTabs(f, #TAB_KEYS)

	f:SetScript("OnShow", function() playSound("IG_CHARACTER_INFO_OPEN") end)
	f:SetScript("OnHide", function()
		playSound("IG_CHARACTER_INFO_CLOSE")
		GameTooltip:Hide()
	end)

	-- Close with Escape
	tinsert(UISpecialFrames, "dgksMainFrame")
end

-- Open the window, on the given tab ("overview", "history" or "settings") or the last one used
function dgks:ShowMainWindow(tab)
	if not frame then createFrame() end
	frame:Show()
	selectTab(tab or current)
end

-- Toggle the window. With a tab: switch to it if the window shows another tab, close it otherwise.
function dgks:ToggleMainWindow(tab)
	if frame and frame:IsShown() and (tab == nil or tab == current) then
		frame:Hide()
		return
	end
	dgks:ShowMainWindow(tab)
end

-- Older entry point: the window on its History tab
function H:ToggleWindow()
	dgks:ToggleMainWindow("history")
end

-- Redraw what shows after history changes
function dgks:RefreshMainWindow()
	if not frame or not frame:IsShown() then return end
	updateStatus()
	if current == "overview" then
		refreshOverview()
	elseif current == "history" then
		refreshHistory(false)
	end
end

H.listeners.window = function() dgks:RefreshMainWindow() end
