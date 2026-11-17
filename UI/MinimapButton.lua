local addon = SmartLoot or {}
SmartLoot = addon

local MinimapButton = {}
addon.Minimap = MinimapButton

local ICON = "Interface\\AddOns\\SmartLoot\\Art\\SmartLoot-Icon"
local MINIMAP_ICON = "Interface\\AddOns\\SmartLoot\\Art\\SmartLoot-Minimap"

function MinimapButton:HasCompartment()
	return AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon and true or false
end

function MinimapButton:Normalize()
	local position = addon.db and addon.db.minimap
	if not position then
		return
	end
	if position.showMinimap == nil then
		position.showMinimap = not position.hide
	end
	if position.showCompartment == nil then
		position.showCompartment = true
	end
	if position.angle == nil then
		local x = position.x or 0
		local y = position.y or -1
		if x == 0 and y == 0 then
			position.angle = -math.pi / 2
		else
			position.angle = math.atan2(y, x)
		end
	end
end

function MinimapButton:Radius()
	local width = tonumber(Minimap:GetWidth()) or 140
	local height = tonumber(Minimap:GetHeight()) or width
	local mapRadius = math.min(width, height) / 2
	local button = self.button
	local buttonRadius = 15.5
	if button then
		buttonRadius = math.max(button:GetWidth() or 31, button:GetHeight() or 31) / 2
	end
	-- Same placement as FishFry: map edge + half button, then sit on the ring.
	return math.floor(mapRadius + buttonRadius - 9)
end

function MinimapButton:Place()
	if not self.button or not addon.db then
		return
	end
	local angle = addon.db.minimap.angle or 0
	local radius = self:Radius()
	self.button:ClearAllPoints()
	self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function MinimapButton:SetAngleFromCursor()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	if not mx or not cx or not scale or scale == 0 then
		return
	end
	addon.db.minimap.angle = math.atan2((cy / scale) - my, (cx / scale) - mx)
	self:Place()
end

function MinimapButton:ClickButtonName(...)
	local first, second = ...
	if first == "LeftButton" or first == "RightButton" then
		return first
	end
	if second == "LeftButton" or second == "RightButton" then
		return second
	end
	if type(second) == "table" and type(second.buttonName) == "string" then
		return second.buttonName
	end
	if type(first) == "table" and type(first.buttonName) == "string" then
		return first.buttonName
	end
	return "LeftButton"
end

function MinimapButton:OnClick(mouseButton)
	if mouseButton == "RightButton" then
		if addon.Options then
			addon.Options:Toggle()
		end
		return
	end
	if addon.DeleteList then
		addon.DeleteList:Toggle()
	end
end

function MinimapButton:CompartmentData()
	if self.compartmentData then
		return self.compartmentData
	end
	self.compartmentData = {
		smartLoot = true,
		text = "Smart Loot",
		icon = ICON,
		func = function(...)
			MinimapButton:OnClick(MinimapButton:ClickButtonName(...))
		end,
		funcOnEnter = function(button)
			GameTooltip:SetOwner(button, "ANCHOR_LEFT")
			GameTooltip:SetText("SmartLoot")
			GameTooltip:AddLine("Left-click: destroy list", 1, 1, 1)
			GameTooltip:AddLine("Right-click: options", 1, 1, 1)
			GameTooltip:Show()
		end,
		funcOnLeave = function()
			GameTooltip:Hide()
		end,
	}
	return self.compartmentData
end

function MinimapButton:RemoveCompartment()
	local frame = AddonCompartmentFrame
	local list = frame and frame.registeredAddons
	if not list then
		return
	end
	for index = #list, 1, -1 do
		if list[index] and list[index].smartLoot then
			table.remove(list, index)
		end
	end
	if frame.UpdateDisplay then
		frame:UpdateDisplay()
	end
end

function MinimapButton:SetCompartment(enabled)
	if not self:HasCompartment() then
		return
	end
	self:RemoveCompartment()
	if enabled then
		AddonCompartmentFrame:RegisterAddon(self:CompartmentData())
	end
end

function MinimapButton:Update()
	if not addon.db then
		return
	end
	self:Normalize()
	local position = addon.db.minimap
	if self.button then
		self:Place()
		self.button:SetShown(position.showMinimap and true or false)
	end
	self:SetCompartment(position.showCompartment and true or false)
end

function MinimapButton:BuildButton()
	local button = CreateFrame("Button", "SmartLootMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	-- Round SmartLoot-Minimap art is authored for a centered tracking hole.
	-- LibDBIcon's classic TOPLEFT inset is for square icons and looks off with this plate.
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(23, 23)
	background:SetPoint("CENTER", button, "CENTER", 0, 0)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MINIMAP_ICON)
	icon:SetSize(23, 23)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT", button, "TOPLEFT")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function()
			MinimapButton:SetAngleFromCursor()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		MinimapButton:SetAngleFromCursor()
		self.dragged = true
	end)
	button:SetScript("OnClick", function(self, mouseButton)
		if self.dragged then
			self.dragged = false
			return
		end
		MinimapButton:OnClick(mouseButton)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("SmartLoot")
		GameTooltip:AddLine("Left-click: destroy list", 1, 1, 1)
		GameTooltip:AddLine("Right-click: options", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this icon", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return button
end

function MinimapButton:Initialize()
	if not Minimap or not addon.db then
		return
	end
	self:Normalize()
	if not self.button then
		self.button = self:BuildButton()
		if not self.sizeHooked then
			self.sizeHooked = true
			pcall(function()
				Minimap:HookScript("OnSizeChanged", function()
					MinimapButton:Place()
				end)
			end)
		end
	end
	self:Update()
end
