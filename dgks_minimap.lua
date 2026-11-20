-- dG KillShot minimap button, and the retail Addon Compartment entry (the addon menu on the minimap)
--   Left-click: open the history window
--   Right-click: open the options
--   Drag: move the button around the minimap

local dgks = dgks
local ICON = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

local button

-- Totals for the tooltip, from personal history
local function totals()
	local t = { K = 0, D = 0 }
	for _, rec in ipairs(dgks.History:PersonalRecords()) do
		if t[rec.k] then t[rec.k] = t[rec.k] + 1 end
	end
	return t
end

local function showTooltip(owner, anchor)
	local tt = GameTooltip
	tt:SetOwner(owner, anchor or "ANCHOR_LEFT")
	tt:AddLine("dG KillShot")
	local ok, t = pcall(totals)
	if ok then
		local streak, deathstreak = dgks:GetStreaks()
		tt:AddDoubleLine("Kills", t.K, 1, 1, 1, 0.25, 1, 0.25)
		tt:AddDoubleLine("Deaths", t.D, 1, 1, 1, 1, 0.25, 0.25)
		tt:AddDoubleLine("K/D", ("%.2f"):format(t.K / math.max(t.D, 1)), 1, 1, 1, 1, 0.82, 0)
		tt:AddDoubleLine("Kill streak", ("%d  (best %d)"):format(streak, dgks.db.profile.maxstreak), 1, 1, 1, 1, 1, 1)
		if deathstreak > 0 then
			tt:AddDoubleLine("Death streak", deathstreak, 1, 1, 1, 1, 0.25, 0.25)
		end
	end
	tt:AddLine(" ")
	tt:AddLine("Left-click: open history", 0.6, 0.6, 0.6)
	tt:AddLine("Right-click: open options", 0.6, 0.6, 0.6)
	if owner == button then tt:AddLine("Drag: move this button", 0.6, 0.6, 0.6) end
	tt:Show()
end

local function onClick(mouseButton)
	if mouseButton == "RightButton" then
		dgks:OpenOptions()
	else
		dgks.History:ToggleWindow()
	end
end

-- Place the button on the edge of the minimap at the saved angle. Square minimaps (from some UI
-- addons) report their shape through GetMinimapShape; the button then follows the square's edge.
local function updatePosition()
	local angle = math.rad(dgks.db.profile.minimap.angle or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local radius = (Minimap:GetWidth() / 2) + 5
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local scale = math.sqrt(2)
		x = math.max(-1, math.min(1, x * scale))
		y = math.max(-1, math.min(1, y * scale))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	dgks.db.profile.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	updatePosition()
end

local function createButton()
	button = CreateFrame("Button", "dgksMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton) onClick(mouseButton) end)
	button:SetScript("OnEnter", function(self) showTooltip(self) end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	-- Show the icon pressed while the mouse button is down
	button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
	button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER") end)
end

-- Show or hide the button to match the "Show minimap button" option
function dgks:UpdateMinimapButton()
	if not button then return end
	if dgks.db.profile.minimap.hide then
		button:Hide()
	else
		updatePosition()
		button:Show()
	end
end

function dgks:SetupMinimapButton()
	if button or not Minimap then return end
	createButton()
	dgks:UpdateMinimapButton()
end

-- Addon Compartment (retail): these names are listed in dgks.toc
function dgks_OnAddonCompartmentClick(_, mouseButton)
	onClick(mouseButton)
end

function dgks_OnAddonCompartmentEnter(_, menuButton)
	showTooltip(menuButton, "ANCHOR_LEFT")
end

function dgks_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
