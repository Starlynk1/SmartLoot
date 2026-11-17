local addon = SmartLoot or {}
SmartLoot = addon

local DeleteList = {}
addon.DeleteList = DeleteList

local ROW_HEIGHT = 36
local LOCKED_ICON = "Interface\\Buttons\\LockButton-Locked-Up"
local UNLOCKED_ICON = "Interface\\Buttons\\LockButton-Unlocked-Up"
local LOCKED_PUSHED = "Interface\\Buttons\\LockButton-Locked-Down"
local UNLOCKED_PUSHED = "Interface\\Buttons\\LockButton-Unlocked-Down"

local function FitButtonTexture(button, getter)
	local texture = button[getter](button)
	if texture then
		texture:ClearAllPoints()
		texture:SetAllPoints(button)
	end
end

function DeleteList:Initialize()
	if self.frame then
		return
	end
	local frame = addon.CreateWindow("SmartLootDeleteFrame", "Destroy Items", 340, 300)
	self.frame = frame
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		DeleteList:SavePosition()
	end)
	frame:SetScript("OnHide", function()
		if addon.Engine and addon.Engine.CancelManualDelete then
			addon.Engine:CancelManualDelete()
		end
	end)
	self:ApplyPosition()
	self.rows = {}

	local content = addon.ContentRegion(frame)

	local check = addon.CreateCheckbox(frame, "SmartLootShowProtectedCheck", "Show protected items", frame)
	check:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
	check:SetHitRectInsets(0, -140, 0, 0)
	local checkText = check.Text or _G["SmartLootShowProtectedCheckText"]
	if checkText then
		checkText:SetWidth(180)
	end
	if frame.TitleContainer then
		check:SetPoint("TOPLEFT", frame.TitleContainer, "BOTTOMLEFT", -4, 0)
	else
		check:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, -28)
	end
	check:SetChecked(addon.db and addon.db.showProtectedItems and true or false)
	check:SetScript("OnClick", function(box)
		if addon.db then
			addon.db.showProtectedItems = box:GetChecked() and true or false
		end
		DeleteList:Refresh()
	end)
	self.showProtected = check

	local scroll = addon.CreateScroll(content)
	scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -8, 8)
	self.scroll = scroll

	self.empty = scroll.child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	self.empty:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, 0)
	self.empty:SetText("No items can be deleted.")
	self.empty:SetJustifyH("LEFT")
	addon.RegisterFontString(frame, self.empty)
end

function DeleteList:Position()
	local db = addon.db
	if not db then
		return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 20 }
	end
	if db.deleteListPosition and db.deleteListPosition.point then
		return db.deleteListPosition
	end
	db.deleteListPosition = {
		point = "CENTER",
		relativePoint = "CENTER",
		x = 0,
		y = 20,
	}
	return db.deleteListPosition
end

function DeleteList:ApplyPosition()
	if not self.frame then
		return
	end
	local saved = self:Position()
	self.frame:ClearAllPoints()
	self.frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 0, saved.y or 20)
end

function DeleteList:SavePosition()
	if not self.frame or not addon.db then
		return
	end
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	addon.db.deleteListPosition = {
		point = point or "CENTER",
		relativePoint = relativePoint or "CENTER",
		x = x or 0,
		y = y or 20,
	}
end

function DeleteList:AcquireRow(index)
	local row = self.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, self.scroll.child)
	row:SetHeight(ROW_HEIGHT)

	local protect = CreateFrame("Button", nil, row)
	protect:SetSize(28, 28)
	protect:SetPoint("LEFT", row, "LEFT", 0, 0)
	protect:SetNormalTexture(UNLOCKED_ICON)
	protect:SetPushedTexture(UNLOCKED_PUSHED)
	protect:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	FitButtonTexture(protect, "GetNormalTexture")
	FitButtonTexture(protect, "GetPushedTexture")
	protect:SetScript("OnClick", function(button)
		local item = button.item
		if not item or not item.itemID then
			return
		end
		if item.protected then
			addon:UnprotectItem(item.itemID)
		else
			addon:ProtectItem(item.itemID, item.name)
		end
		if addon.Inventory and addon.Inventory.RefreshCache then
			addon.Inventory.RefreshCache()
		else
			DeleteList:Refresh()
		end
	end)
	protect:SetScript("OnEnter", function(button)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		if button.item and button.item.protected then
			GameTooltip:SetText("Unprotect")
		else
			GameTooltip:SetText("Protect")
		end
		GameTooltip:Show()
	end)
	protect:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	row.protect = protect

	local iconButton = CreateFrame("Button", nil, row)
	iconButton:SetSize(28, 28)
	iconButton:SetPoint("LEFT", protect, "RIGHT", 0, 0)
	iconButton:SetScript("OnEnter", function(button)
		local item = button.item
		if not item then
			return
		end
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		if item.bag ~= nil and item.slot ~= nil and GameTooltip.SetBagItem then
			GameTooltip:SetBagItem(item.bag, item.slot)
		elseif item.link then
			GameTooltip:SetHyperlink(item.link)
		else
			GameTooltip:SetText(item.name or "Item")
		end
		GameTooltip:Show()
	end)
	iconButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row.iconButton = iconButton
	row.icon = iconButton:CreateTexture(nil, "ARTWORK")
	row.icon:SetAllPoints(iconButton)

	row.count = iconButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	row.count:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", -1, 1)
	addon.RegisterFontString(self.frame, row.count)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	addon.RegisterFontString(self.frame, row.name)

	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.mark:SetJustifyH("LEFT")
	addon.RegisterFontString(self.frame, row.mark)

	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.value:SetJustifyH("RIGHT")
	addon.RegisterFontString(self.frame, row.value)

	local destroy = addon.CreateButton(row, "Destroy", 64)
	destroy:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	destroy:SetScript("OnMouseDown", function(button, mouseButton)
		if mouseButton ~= "LeftButton" or not row.item then
			return
		end
		if addon.Engine and addon.Engine.BeginManualDelete then
			addon.Engine:BeginManualDelete(row.item)
		end
	end)
	destroy:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton ~= "LeftButton" then
			return
		end
		if addon.Engine and addon.Engine.FinishManualDelete then
			addon.Engine:FinishManualDelete()
		end
	end)
	row.destroy = destroy

	row.name:SetPoint("LEFT", iconButton, "RIGHT", 8, 6)
	row.mark:SetPoint("LEFT", iconButton, "RIGHT", 8, -8)
	row.value:SetPoint("RIGHT", destroy, "LEFT", -8, 0)
	row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)

	self.rows[index] = row
	return row
end

function DeleteList:SetLock(button, locked)
	if locked then
		button:SetNormalTexture(LOCKED_ICON)
		button:SetPushedTexture(LOCKED_PUSHED)
	else
		button:SetNormalTexture(UNLOCKED_ICON)
		button:SetPushedTexture(UNLOCKED_PUSHED)
	end
	FitButtonTexture(button, "GetNormalTexture")
	FitButtonTexture(button, "GetPushedTexture")
end

function DeleteList:FillRow(row, item)
	row.item = item
	row.iconButton.item = item
	row.protect.item = item
	row.protect:SetShown(item.itemID and true or false)
	self:SetLock(row.protect, item.protected)
	row.destroy:SetShown(not item.protected)
	row.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	local count = item.count or 1
	if count > 1 then
		row.count:SetText(tostring(count))
		row.count:Show()
	else
		row.count:SetText("")
		row.count:Hide()
	end
	row.name:SetText(item.name or "Item")
	local r, g, b = addon.QualityColor(item.quality)
	row.name:SetTextColor(r, g, b)
	row.value:ClearAllPoints()
	if item.protected then
		row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	else
		row.value:SetPoint("RIGHT", row.destroy, "LEFT", -8, 0)
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
	if item.protected then
		row.mark:SetText("Protected")
		row.mark:Show()
		row.name:SetPoint("LEFT", row.iconButton, "RIGHT", 8, 6)
	elseif item.markedJunk then
		row.mark:SetText("Junk")
		row.mark:Show()
		row.name:SetPoint("LEFT", row.iconButton, "RIGHT", 8, 6)
	else
		row.mark:SetText("")
		row.mark:Hide()
		row.name:SetPoint("LEFT", row.iconButton, "RIGHT", 8, 0)
	end
	row.value:SetText(addon.FormatMoney(item.value or 0))
	row:Show()
end

function DeleteList:Candidates()
	local inventory = addon.Inventory
	local items = inventory and inventory.items or {}
	local freeSlots = inventory and inventory.freeSlots or {}
	local db = addon.db or {}
	return addon.ManualDeleteCandidates(items, freeSlots, {
		protectReagents = db.protectCraftingReagents and true or false,
		keepSoulShards = db.keepSoulShards or 0,
		includeProtected = db.showProtectedItems and true or false,
	})
end

function DeleteList:Refresh()
	if not self.frame then
		return
	end
	if self.showProtected then
		self.showProtected:SetChecked(addon.db and addon.db.showProtectedItems and true or false)
	end
	local list = addon.ManualDeleteCandidates and self:Candidates() or {}
	for index = 1, #self.rows do
		self.rows[index]:Hide()
		self.rows[index].item = nil
		self.rows[index].iconButton.item = nil
		if self.rows[index].protect then
			self.rows[index].protect.item = nil
		end
	end
	if #list == 0 then
		self.empty:Show()
		self.scroll.child:SetHeight(24)
		return
	end
	self.empty:Hide()
	local y = 0
	for index = 1, #list do
		local row = self:AcquireRow(index)
		self:FillRow(row, list[index])
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.scroll.child, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", self.scroll.child, "TOPRIGHT", 0, -y)
		y = y + ROW_HEIGHT
	end
	self.scroll.child:SetHeight(math.max(y, 1))
end

function DeleteList:RefreshIfShown()
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
end

function DeleteList:Toggle()
	self:Initialize()
	if self.frame:IsShown() then
		self.frame:Hide()
		return
	end
	self.frame:Show()
	if addon.Inventory and addon.Inventory.RefreshCache then
		addon.Inventory.RefreshCache()
	else
		self:Refresh()
	end
end
