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
						cells = { when(rec.t), kindText(rec.k), classColored(opp, rec.oc), className(rec.oc), rec.z or "", rec.st and tostring(rec.st) or "" },
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
						cells = { when(rec.t), classColored(member, rec.c), kindText(rec.k), classColored(opp, rec.oc), rec.z or "" },
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
				if passes(rec, { opp }, true) then
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
		{ value = "leaders", text = "Guild leaderboard" },
	})
	tabs:SetCallback("OnGroupSelected", function(container, _, group) buildTab(container, group) end)
	window:AddChild(tabs)
	tabs:SelectTab(ui.tab)
end

H.listeners.window = refreshRows

-- Options page ----------------------------------------------------------------------------------

local function options()
	return {
		type = "group",
		name = "History",
		args = {
			status = {
				type = "description",
				order = 1,
				name = function() return statusText() .. "\n" end,
			},
			open = {
				type = "execute",
				order = 2,
				name = "Open history",
				desc = "Open the history window. You can also type /dgks history.",
				func = function() H:ToggleWindow() end,
			},
			share = {
				type = "toggle",
				order = 10,
				width = "full",
				name = "Share my kills and deaths with my guild",
				desc = "Send your kills, deaths and duels to guild members running dG KillShot, and keep a copy of theirs. Turning this off also stops receiving guild history.",
				get = function() return dgks.db.profile.historyShare end,
				set = function(_, v)
					dgks.db.profile.historyShare = v
					if v then H:SyncNow() end
				end,
			},
			retention = {
				type = "range",
				order = 11,
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
			sync = {
				type = "execute",
				order = 20,
				name = "Sync now",
				desc = "Ask guild members for history you are missing.",
				func = function() H:SyncNow() end,
			},
			clearGuild = {
				type = "execute",
				order = 30,
				name = "Clear guild history",
				desc = "Delete your copy of this guild's history. It is synced again from guild members.",
				confirm = true,
				confirmText = "Delete your copy of the guild history? It will be synced again from guild members.",
				func = function() H:ClearGuild() end,
			},
			clearMine = {
				type = "execute",
				order = 31,
				name = "Clear my history",
				desc = "Delete this character's personal history. Records already shared with the guild stay there.",
				confirm = true,
				confirmText = "Delete this character's personal kill and death history? This cannot be undone.",
				func = function()
					wipe(dgks.db.char.history.records)
					H:NotifyChanged()
				end,
			},
		},
	}
end

function H:RegisterOptions()
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("dG KillShot History", options)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("dG KillShot History", "History", "dG KillShot")
end
