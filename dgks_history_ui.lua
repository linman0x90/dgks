-- dG KillShot history window (/dgks history) and the History options page

local dgks = dgks
local H = dgks.History
local AceGUI = LibStub("AceGUI-3.0")

local ROW_HEIGHT, HEADER_HEIGHT, SCROLL_WIDTH = 18, 22, 16

-- Table widget ----------------------------------------------------------------------------------
-- A scrolling, sortable list that only creates frames for the rows that are visible, so it stays
-- fast with thousands of records.
--   SetColumns({ { title = "When", width = 0.2, align = "LEFT" }, ... })  widths are fractions
--   SetSortState({ col = 1, desc = true })  the table is kept and updated when a header is clicked
--   SetRows({ { cells = { "text", ... }, sort = { value, ... }, tip = function(tooltip) end }, ... })
do
	local Type, Version = "dgksHistoryTable", 1

	local function sortRows(self)
		local s = self.sortState
		if not s or not self.columns[s.col] then return end
		local c, desc = s.col, s.desc
		table.sort(self.rows, function(a, b)
			local va, vb = a.sort[c], b.sort[c]
			if va == vb then return a.index < b.index end
			if desc then return va > vb end
			return va < vb
		end)
	end

	local methods = {}

	function methods:OnAcquire()
		self.columns, self.rows, self.offset, self.visible = {}, {}, 0, 0
		self.sortState = { col = 1, desc = true }
		self.slider:SetMinMaxValues(0, 0)
		self.slider:SetValue(0)
		self.frame:Show()
	end

	function methods:OnRelease()
		self.columns, self.rows = {}, {}
		for _, row in ipairs(self.rowFrames) do row:Hide(); row.item = nil end
		for _, header in ipairs(self.headers) do header:Hide() end
	end

	function methods:SetColumns(columns)
		self.columns = columns
		self:Layout()
	end

	function methods:SetSortState(state)
		self.sortState = state
	end

	function methods:SetRows(rows)
		for i, row in ipairs(rows) do row.index = i end
		self.rows = rows
		sortRows(self)
		self:Layout()
	end

	function methods:GetHeader(i)
		local header = self.headers[i]
		if not header then
			header = CreateFrame("Button", nil, self.frame)
			header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			header.text:SetPoint("LEFT", 4, 0)
			header.text:SetPoint("RIGHT", -4, 0)
			header.text:SetWordWrap(false)
			local hl = header:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
			local widget = self
			header:SetScript("OnClick", function()
				local s = widget.sortState
				if s.col == i then
					s.desc = not s.desc
				else
					s.col = i
					s.desc = widget.columns[i].desc ~= false
				end
				sortRows(widget)
				widget:Layout()
			end)
			self.headers[i] = header
		end
		return header
	end

	function methods:GetRow(r)
		local row = self.rowFrames[r]
		if not row then
			row = CreateFrame("Button", nil, self.frame)
			row.cells = {}
			if r % 2 == 0 then
				local bg = row:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(1, 1, 1, 0.04)
			end
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.82, 0, 0.12)
			row:SetScript("OnEnter", function(f)
				if f.item and f.item.tip then
					GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
					local ok = pcall(f.item.tip, GameTooltip)
					if ok then GameTooltip:Show() else GameTooltip:Hide() end
				end
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			self.rowFrames[r] = row
		end
		return row
	end

	function methods:Layout()
		local frame = self.frame
		local width = frame:GetWidth() - SCROLL_WIDTH - 2
		local height = frame:GetHeight()
		if not width or width <= 0 or not height or height <= 0 then return end

		local positions, x = {}, 0
		for i, col in ipairs(self.columns) do
			local w = width * col.width
			positions[i] = { x = x, w = w }
			local header = self:GetHeader(i)
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
			header:SetSize(w, HEADER_HEIGHT)
			local arrow = ""
			if self.sortState.col == i then arrow = self.sortState.desc and " v" or " ^" end
			header.text:SetText(col.title .. arrow)
			header.text:SetJustifyH(col.align or "LEFT")
			header:Show()
			x = x + w
		end
		for i = #self.columns + 1, #self.headers do self.headers[i]:Hide() end

		local visible = math.max(0, math.floor((height - HEADER_HEIGHT) / ROW_HEIGHT))
		for r = 1, visible do
			local row = self:GetRow(r)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_HEIGHT - (r - 1) * ROW_HEIGHT)
			row:SetSize(width, ROW_HEIGHT)
			for i, col in ipairs(self.columns) do
				local cell = row.cells[i]
				if not cell then
					cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					cell:SetWordWrap(false)
					row.cells[i] = cell
				end
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", row, "LEFT", positions[i].x + 4, 0)
				cell:SetWidth(math.max(1, positions[i].w - 8))
				cell:SetJustifyH(col.align or "LEFT")
				cell:Show()
			end
			for i = #self.columns + 1, #row.cells do row.cells[i]:Hide() end
		end
		for r = visible + 1, #self.rowFrames do self.rowFrames[r]:Hide() end
		self.visible = visible

		local maxOffset = math.max(0, #self.rows - visible)
		self.slider:SetMinMaxValues(0, maxOffset)
		if self.offset > maxOffset then self.offset = maxOffset end
		self.slider:SetValue(self.offset)
		self:Refresh()
	end

	function methods:Refresh()
		for r = 1, self.visible do
			local row = self:GetRow(r)
			local item = self.rows[self.offset + r]
			row.item = item
			if item then
				for i = 1, #self.columns do row.cells[i]:SetText(item.cells[i] or "") end
				row:Show()
			else
				row:Hide()
			end
		end
		if #self.rows == 0 then self.empty:Show() else self.empty:Hide() end
	end

	local function Constructor()
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:Hide()

		local slider = CreateFrame("Slider", nil, frame)
		slider:SetOrientation("VERTICAL")
		slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_HEIGHT)
		slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		slider:SetWidth(SCROLL_WIDTH)
		slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
		slider:GetThumbTexture():SetSize(SCROLL_WIDTH, 24)
		slider:SetValueStep(1)
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetAllPoints()
		track:SetColorTexture(0, 0, 0, 0.35)

		local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		empty:SetPoint("TOP", frame, "TOP", 0, -HEADER_HEIGHT - 20)
		empty:SetText("No records match these filters.")

		local widget = {
			frame = frame, type = Type, slider = slider, empty = empty,
			headers = {}, rowFrames = {}, columns = {}, rows = {},
			offset = 0, visible = 0, sortState = { col = 1, desc = true },
		}
		for name, fn in pairs(methods) do widget[name] = fn end

		slider:SetScript("OnValueChanged", function(_, value)
			local offset = math.floor(value + 0.5)
			if offset ~= widget.offset then
				widget.offset = offset
				widget:Refresh()
			end
		end)
		frame:EnableMouseWheel(true)
		frame:SetScript("OnMouseWheel", function(_, delta)
			slider:SetValue(slider:GetValue() - delta * 3)
		end)
		frame:SetScript("OnSizeChanged", function() widget:Layout() end)

		return AceGUI:RegisterAsWidget(widget)
	end

	AceGUI:RegisterWidgetType(Type, Constructor, Version)
end

-- Formatting ------------------------------------------------------------------------------------

local KIND_COLORS = { K = "ff40ff40", D = "ffff4040", W = "ffa0ffa0", L = "ffffa040" }

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
local function opponentText(rec, name)
	if H.IsUnknown(rec) then return "|cff9d9d9d" .. name .. "|r" end
	local text = classColored(name, rec.oc)
	if rec.g then text = text .. " |cff9d9d9d(likely)|r" end
	return text
end

local function recordTip(rec)
	return function(tt)
		tt:AddLine(("%s: %s"):format(H.KIND_NAMES[rec.k] or "?", H.ShortName(rec.o)))
		tt:AddDoubleLine("When", date("%Y-%m-%d %H:%M:%S", rec.t), 1, 1, 1, 1, 1, 1)
		if rec.a then tt:AddDoubleLine("Player", H.ShortName(rec.a), 1, 1, 1, 1, 1, 1) end
		if rec.z then
			local place = rec.z
			if rec.sz then place = place .. " - " .. rec.sz end
			tt:AddDoubleLine("Where", place, 1, 1, 1, 1, 1, 1)
		end
		if rec.i and rec.i ~= "none" then tt:AddDoubleLine("Instance", rec.i, 1, 1, 1, 1, 1, 1) end
		if rec.oc or rec.orc or rec.ol then
			local parts = {}
			if rec.ol and rec.ol > 0 then parts[#parts + 1] = "Level " .. rec.ol end
			if rec.orc then parts[#parts + 1] = rec.orc end
			if rec.oc then parts[#parts + 1] = className(rec.oc) end
			tt:AddDoubleLine("Opponent", table.concat(parts, " "), 1, 1, 1, 1, 1, 1)
		end
		if rec.l then tt:AddDoubleLine("Your level", tostring(rec.l), 1, 1, 1, 1, 1, 1) end
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

local PERIODS = { [86400] = "Last 24 hours", [604800] = "Last 7 days", [2592000] = "Last 30 days",
	[7776000] = "Last 90 days", [0] = "All time" }
local PERIOD_ORDER = { 86400, 604800, 2592000, 7776000, 0 }
local KIND_FILTERS = { all = "All", K = "Kills", D = "Deaths", duel = "Duels" }
local KIND_ORDER = { "all", "K", "D", "duel" }

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
			{ title = "When", width = 0.20 },
			{ title = "Type", width = 0.11 },
			{ title = "Opponent", width = 0.24, desc = false },
			{ title = "Class", width = 0.12, desc = false },
			{ title = "Zone", width = 0.25, desc = false },
			{ title = "Streak", width = 0.08, align = "RIGHT" },
		},
		rows = function()
			local rows = {}
			for _, rec in ipairs(H:PersonalRecords()) do
				local opp = H.ShortName(rec.o)
				if passes(rec, { opp, rec.z, rec.sz }) then
					rows[#rows + 1] = {
						cells = { when(rec.t), kindText(rec.k), opponentText(rec, opp), className(rec.oc), rec.z or "", rec.st and tostring(rec.st) or "" },
						sort = { rec.t, rec.k, opp:lower(), className(rec.oc), (rec.z or ""):lower(), rec.st or 0 },
						tip = recordTip(rec),
					}
				end
			end
			return rows
		end,
	},
	guild = {
		columns = {
			{ title = "When", width = 0.20 },
			{ title = "Member", width = 0.20, desc = false },
			{ title = "Type", width = 0.11 },
			{ title = "Opponent", width = 0.24, desc = false },
			{ title = "Zone", width = 0.25, desc = false },
		},
		rows = function()
			local rows = {}
			for _, rec in ipairs(H:GuildRecords()) do
				local member, opp = H.ShortName(rec.a), H.ShortName(rec.o)
				if passes(rec, { member, opp, rec.z, rec.sz }) then
					rows[#rows + 1] = {
						cells = { when(rec.t), classColored(member, rec.c), kindText(rec.k), opponentText(rec, opp), rec.z or "" },
						sort = { rec.t, member:lower(), rec.k, opp:lower(), (rec.z or ""):lower() },
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
			{ title = "Opponent", width = 0.26, desc = false },
			{ title = "Class", width = 0.14, desc = false },
			{ title = "Kills", width = 0.10, align = "RIGHT" },
			{ title = "Deaths", width = 0.10, align = "RIGHT" },
			{ title = "Duels W-L", width = 0.14, align = "RIGHT" },
			{ title = "Last seen", width = 0.26 },
		},
		rows = function()
			local byName, list = {}, {}
			for _, rec in ipairs(H:PersonalRecords()) do
				local opp = H.ShortName(rec.o)
				if not H.IsUnknown(rec) and passes(rec, { opp }, true) then
					local o = byName[opp]
					if not o then
						o = { name = opp, K = 0, D = 0, W = 0, L = 0, last = 0 }
						byName[opp] = o
						list[#list + 1] = o
					end
					o[rec.k] = o[rec.k] + 1
					if rec.t >= o.last then o.last = rec.t end
					if rec.oc then o.class = rec.oc end
				end
			end
			local rows = {}
			for _, o in ipairs(list) do
				rows[#rows + 1] = {
					cells = { classColored(o.name, o.class), className(o.class), tostring(o.K), tostring(o.D), o.W .. "-" .. o.L, when(o.last) },
					sort = { o.name:lower(), className(o.class), o.K, o.D, o.W - o.L, o.last },
				}
			end
			return rows
		end,
	},
	guildopponents = {
		noKindFilter = true,
		columns = {
			{ title = "Opponent", width = 0.19, desc = false },
			{ title = "Class", width = 0.11, desc = false },
			{ title = "Kills", width = 0.08, align = "RIGHT" },
			{ title = "Deaths", width = 0.09, align = "RIGHT" },
			{ title = "Duels W-L", width = 0.11, align = "RIGHT" },
			{ title = "Fought by", width = 0.10, align = "RIGHT" },
			{ title = "Top killer", width = 0.16, desc = false },
			{ title = "Last seen", width = 0.16 },
		},
		rows = function()
			local byKey, list = {}, {}
			for _, rec in ipairs(H:GuildRecords()) do
				local key = H.OpponentKey(rec)
				local opp, member = H.ShortName(key), H.ShortName(rec.a)
				-- Search matches the opponent or a member, so "Zed" or "Bob" both narrow the list
				if key and not H.IsUnknown(rec) and passes(rec, { opp, member }, true) then
					local o = byKey[key]
					if not o then
						o = { name = opp, K = 0, D = 0, W = 0, L = 0, last = 0, members = {}, memberCount = 0 }
						byKey[key] = o
						list[#list + 1] = o
					end
					o[rec.k] = o[rec.k] + 1
					if rec.t >= o.last then o.last = rec.t end
					if rec.oc then o.class = rec.oc end
					local m = o.members[member]
					if not m then
						m = { name = member, class = rec.c, K = 0, D = 0, W = 0, L = 0 }
						o.members[member] = m
						o.memberCount = o.memberCount + 1
					end
					m[rec.k] = m[rec.k] + 1
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
					topText = classColored(top.name, top.class) .. " (" .. top.K .. ")"
					topSort = top.name:lower()
				end
				rows[#rows + 1] = {
					cells = { classColored(o.name, o.class), className(o.class), tostring(o.K), tostring(o.D),
						o.W .. "-" .. o.L, tostring(o.memberCount), topText, when(o.last) },
					sort = { o.name:lower(), className(o.class), o.K, o.D, o.W - o.L, o.memberCount, topSort, o.last },
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
				local member = H.ShortName(rec.a)
				if passes(rec, { member }, true) then
					local m = byName[member]
					if not m then
						m = { name = member, K = 0, D = 0, W = 0, L = 0, best = 0, last = 0 }
						byName[member] = m
						list[#list + 1] = m
					end
					m[rec.k] = m[rec.k] + 1
					if rec.c then m.class = rec.c end
					if rec.k == "K" then
						if rec.t > m.last then m.last = rec.t end
						if (rec.st or 0) > m.best then m.best = rec.st end
					end
				end
			end
			local rows = {}
			for _, m in ipairs(list) do
				local kd = m.K / math.max(m.D, 1)
				rows[#rows + 1] = {
					cells = { classColored(m.name, m.class), tostring(m.K), tostring(m.D), ("%.2f"):format(kd), tostring(m.best), m.W .. "-" .. m.L, m.last > 0 and when(m.last) or "" },
					sort = { m.name:lower(), m.K, m.D, kd, m.best, m.W - m.L, m.last },
				}
			end
			return rows
		end,
	},
}

-- Window ----------------------------------------------------------------------------------------

local window, tableWidget

local function statusText()
	local gk = H:GuildKey()
	local guildCount = #H:GuildRecords()
	local mine = #H:PersonalRecords()
	if gk then
		return ("%d personal records  |  Guild %s: %d records"):format(mine, gk, guildCount)
	end
	return ("%d personal records  |  Not in a guild"):format(mine)
end

local function refreshRows()
	if not window then return end
	window:SetStatusText(statusText())
	if tableWidget then tableWidget:SetRows(TABS[ui.tab].rows()) end
end

local function buildTab(container, tab)
	container:ReleaseChildren()
	ui.tab = tab
	local def = TABS[tab]

	local search = AceGUI:Create("EditBox")
	search:SetLabel("Search")
	search:SetText(ui.search)
	search:DisableButton(true)
	search:SetRelativeWidth(def.noKindFilter and 0.5 or 0.4)
	search:SetCallback("OnTextChanged", function(_, _, text)
		ui.search = (text or ""):lower()
		refreshRows()
	end)
	container:AddChild(search)

	if not def.noKindFilter then
		local kind = AceGUI:Create("Dropdown")
		kind:SetLabel("Type")
		kind:SetList(KIND_FILTERS, KIND_ORDER)
		kind:SetValue(ui.kind)
		kind:SetRelativeWidth(0.25)
		kind:SetCallback("OnValueChanged", function(_, _, value)
			ui.kind = value
			refreshRows()
		end)
		container:AddChild(kind)
	end

	local period = AceGUI:Create("Dropdown")
	period:SetLabel("Period")
	period:SetList(PERIODS, PERIOD_ORDER)
	period:SetValue(ui.period)
	period:SetRelativeWidth(def.noKindFilter and 0.45 or 0.3)
	period:SetCallback("OnValueChanged", function(_, _, value)
		ui.period = value
		refreshRows()
	end)
	container:AddChild(period)

	tableWidget = AceGUI:Create("dgksHistoryTable")
	tableWidget:SetFullWidth(true)
	tableWidget:SetFullHeight(true)
	tableWidget:SetSortState(ui.sort[tab])
	tableWidget:SetColumns(def.columns)
	container:AddChild(tableWidget)
	refreshRows()
end

function H:ToggleWindow()
	if window then
		window:Hide()
		return
	end
	window = AceGUI:Create("Frame")
	window:SetTitle("dG KillShot History")
	window:SetWidth(820)
	window:SetHeight(540)
	window:SetLayout("Fill")
	window:SetCallback("OnClose", function(widget)
		_G.dgksHistoryFrame = nil
		window, tableWidget = nil, nil
		AceGUI:Release(widget)
	end)
	-- Close with Escape
	_G.dgksHistoryFrame = window.frame
	local listed = false
	for _, name in ipairs(UISpecialFrames) do
		if name == "dgksHistoryFrame" then listed = true end
	end
	if not listed then tinsert(UISpecialFrames, "dgksHistoryFrame") end

	local tabs = AceGUI:Create("TabGroup")
	tabs:SetLayout("Flow")
	tabs:SetTabs({
		{ value = "mine", text = "My history" },
		{ value = "guild", text = "Guild history" },
		{ value = "opponents", text = "My opponents" },
		{ value = "guildopponents", text = "Guild opponents" },
		{ value = "leaders", text = "Guild leaderboard" },
	})
	tabs:SetCallback("OnGroupSelected", function(container, _, group) buildTab(container, group) end)
	window:AddChild(tabs)
	tabs:SelectTab(ui.tab)
end

H.listeners.window = refreshRows

-- Main options page --------------------------------------------------------------------------
-- The stats, Top 5 lists and history settings shown on the main "dG KillShot" page. dgks.lua merges
-- these into its options table; the table is rebuilt every time the page is drawn.

local GOLD, GREY, WHITE = "ffffd100", "ff9d9d9d", "ffffffff"
local RANK_COLORS = { "ffffd100", "ffc7c7cf", "ffd9915a", "ffb0b0b0", "ffb0b0b0" } -- gold, silver, bronze

local function c(color, text)
	return ("|c%s%s|r"):format(color, text)
end

-- A stat tile: small grey label over a big number
function H.Tile(order, label, value, color)
	return {
		type = "description",
		order = order,
		width = 0.85,
		fontSize = "large",
		name = c(GREY, label) .. "\n" .. c(color or WHITE, tostring(value)) .. "\n",
	}
end

-- Kills, deaths and duels of this character, from personal history
local function totals()
	local t = { K = 0, D = 0, W = 0, L = 0 }
	for _, rec in ipairs(H:PersonalRecords()) do t[rec.k] = (t[rec.k] or 0) + 1 end
	return t
end

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

local function topList(title, kind, unit, countColor)
	local lines = { c(GOLD, title), "" }
	local entries = top(kind, 5)
	if #entries == 0 then
		lines[#lines + 1] = c(GREY, "Nothing recorded yet")
	end
	for i, o in ipairs(entries) do
		lines[#lines + 1] = ("%s  %s  %s"):format(
			c(RANK_COLORS[i], i .. "."),
			classColored(o.name, o.class),
			c(countColor, o.count .. " " .. (o.count == 1 and unit or unit .. "s")))
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Option entries for the main page. order runs from base upward.
function H:MainOptionArgs(base)
	local t = totals()
	local kd = t.K / math.max(t.D, 1)
	return {
		recordHeader = { type = "header", order = base, name = "Your record" },
		kills = H.Tile(base + 1, "Kills", t.K, "ff40ff40"),
		deaths = H.Tile(base + 2, "Deaths", t.D, "ffff4040"),
		kd = H.Tile(base + 3, "K/D", ("%.2f"):format(kd), GOLD),
		duels = H.Tile(base + 4, "Duels W-L", t.W .. "-" .. t.L, WHITE),

		topHeader = { type = "header", order = base + 20, name = "Top 5" },
		prey = {
			type = "description",
			order = base + 21,
			width = 1.6,
			fontSize = "medium",
			name = function() return topList("Top prey", "K", "kill", "ff40ff40") end,
		},
		predators = {
			type = "description",
			order = base + 22,
			width = 1.6,
			fontSize = "medium",
			name = function() return topList("Top predators", "D", "death", "ffff4040") end,
		},

		historyHeader = { type = "header", order = base + 40, name = "History" },
		historyStatus = {
			type = "description",
			order = base + 41,
			fontSize = "medium",
			name = function() return statusText() .. "\n" end,
		},
		historyOpen = {
			type = "execute",
			order = base + 42,
			name = "Open history",
			desc = "Open the history window. You can also type /dgks history.",
			func = function() H:ToggleWindow() end,
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

-- Redraw the main page when history changes while it is open
H.listeners.options = function()
	LibStub("AceConfigRegistry-3.0"):NotifyChange("dG KillShot")
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
	if usableString(realm) then name = name .. "-" .. realm end

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
