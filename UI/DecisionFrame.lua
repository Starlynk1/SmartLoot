local addon = SmartLoot or {}
SmartLoot = addon

local Decision = {}
addon.Decision = Decision

local SAMPLE = {
	takes = {
		{ name = "Warbound Helm", quality = 3, reason = "BoA", texture = "Interface\\Icons\\INV_Helmet_03", value = 15432, itemID = 2 },
	},
	sacrifices = {
		{ name = "Broken Junk", quality = 0, reason = "Value", texture = "Interface\\Icons\\INV_Misc_Bone_01", value = 37, itemID = 3 },
	},
	steps = {
		{
			take = { name = "Warbound Helm", quality = 3, reason = "BoA", texture = "Interface\\Icons\\INV_Helmet_03", value = 15432, itemID = 2 },
			sacrifices = {
				{ name = "Broken Junk", quality = 0, reason = "Value", texture = "Interface\\Icons\\INV_Misc_Bone_01", value = 37, itemID = 3 },
			},
		},
	},
	leftBehind = {},
}

local LOCKED_ICON = "Interface\\Buttons\\LockButton-Locked-Up"
local UNLOCKED_ICON = "Interface\\Buttons\\LockButton-Unlocked-Up"
local LOCKED_PUSHED = "Interface\\Buttons\\LockButton-Locked-Down"
local UNLOCKED_PUSHED = "Interface\\Buttons\\LockButton-Unlocked-Down"

local function ReasonLabel(item, forceValue)
	if item.skipReason then
		return item.skipReason
	end
	if forceValue or not item.reason or item.reason == "Value" then
		return ""
	end
	return item.reason
end

local function TextWidth(fontString)
	local measured = fontString:GetStringWidth()
	if measured and measured > 0 then
		return measured
	end
	return math.max(8, #(fontString:GetText() or "") * 8)
end

local function CreateCoins(parent, fontOwner)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetHeight(16)
	local function AddCoin(texture)
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetJustifyH("RIGHT")
		local icon = frame:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(texture)
		icon:SetSize(13, 13)
		addon.RegisterFontString(fontOwner, text)
		return text, icon
	end
	frame.goldText, frame.goldIcon = AddCoin("Interface\\MoneyFrame\\UI-GoldIcon")
	frame.silverText, frame.silverIcon = AddCoin("Interface\\MoneyFrame\\UI-SilverIcon")
	frame.copperText, frame.copperIcon = AddCoin("Interface\\MoneyFrame\\UI-CopperIcon")

	function frame:SetCopper(amount)
		amount = math.floor(tonumber(amount) or 0)
		if amount < 0 then
			amount = 0
		end
		local gold = math.floor(amount / 10000)
		local silver = math.floor((amount % 10000) / 100)
		local copper = amount % 100
		local showGold = gold > 0
		local showSilver = showGold or silver > 0
		self.goldText:SetShown(showGold)
		self.goldIcon:SetShown(showGold)
		self.silverText:SetShown(showSilver)
		self.silverIcon:SetShown(showSilver)
		self.goldText:SetText(tostring(gold))
		self.silverText:SetText(tostring(silver))
		self.copperText:SetText(tostring(copper))

		self.copperIcon:ClearAllPoints()
		self.copperIcon:SetPoint("RIGHT", self, "RIGHT", 0, 0)
		self.copperText:ClearAllPoints()
		self.copperText:SetPoint("RIGHT", self.copperIcon, "LEFT", -1, 0)
		local width = TextWidth(self.copperText) + 14
		local left = self.copperText
		if showSilver then
			self.silverIcon:ClearAllPoints()
			self.silverIcon:SetPoint("RIGHT", left, "LEFT", -4, 0)
			self.silverText:ClearAllPoints()
			self.silverText:SetPoint("RIGHT", self.silverIcon, "LEFT", -1, 0)
			width = width + 5 + TextWidth(self.silverText) + 14
			left = self.silverText
		end
		if showGold then
			self.goldIcon:ClearAllPoints()
			self.goldIcon:SetPoint("RIGHT", left, "LEFT", -4, 0)
			self.goldText:ClearAllPoints()
			self.goldText:SetPoint("RIGHT", self.goldIcon, "LEFT", -1, 0)
			width = width + 5 + TextWidth(self.goldText) + 14
		end
		self:SetWidth(width)
	end

	frame:SetCopper(0)
	return frame
end

function Decision:Initialize()
	if self.frame then
		return
	end
	local frame = addon.CreateLootWindow("SmartLootDecisionFrame", "Loot", 340, 300)
	frame.layoutKey = "decision"
	self.frame = frame
	self.rows = {}

	local content = frame
	local scroll = addon.CreateScroll(content)
	scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -28)
	scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 40)
	self.scroll = scroll

	local child = scroll.child
	self.lootHeader = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.deleteHeader = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.leftHeader = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.lootMessage = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.lootMessage:SetJustifyH("LEFT")
	self.lootMessage:SetWordWrap(true)
	for _, fontString in ipairs({ self.lootHeader, self.deleteHeader, self.leftHeader, self.lootMessage }) do
		addon.RegisterFontString(frame, fontString)
	end
	self.leftHeader:SetTextColor(1, 0.25, 0.25)

	local info = CreateFrame("Button", nil, frame)
	info:SetSize(16, 16)
	info:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -4)
	info:SetNormalTexture("Interface\\common\\help-i")
	info:SetHighlightTexture("Interface\\common\\help-i", "ADD")
	info:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText("Loot help")
		GameTooltip:AddLine("Click the lock to keep that item and pick another.", 1, 1, 1, true)
		GameTooltip:AddLine("Click Skip to pass an openable.", 1, 1, 1, true)
		local junkSource = addon.JunkSource and addon.JunkSource() or "quality"
		if junkSource == "baganator" then
			GameTooltip:AddLine("Baganator junk is deleted first.", 1, 1, 1, true)
		elseif junkSource == "rxpguides" then
			GameTooltip:AddLine("RestedXP junk is deleted first.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Grey junk is deleted before Common or better.", 1, 1, 1, true)
		end
		GameTooltip:AddLine("Quest items remove the cheapest item of any quality.", 1, 1, 1, true)
		GameTooltip:AddLine("The Hearthstone stays.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	info:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	self.infoButton = info

	self.acceptButton = addon.CreateButton(frame, addon.DestroyActionLabel(), 160)
	self.acceptButton:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and not self.preview then
			addon.Engine:Accept()
		end
	end)
	self.acceptButton:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and not self.preview then
			addon.Engine:OnAcceptRelease()
		end
	end)

	self.cancelButton = addon.CreateButton(frame, "Cancel", 100)
	self.cancelButton:SetScript("OnClick", function()
		if addon.Engine:GetState() == "confirming" then
			addon.Engine:Cancel()
		else
			frame:Hide()
		end
	end)

	frame:SetScript("OnHide", function()
		if not addon.Engine then
			return
		end
		if addon.Engine.autoDestroying then
			return
		end
		if addon.Engine:GetState() == "confirming" or addon.Engine.deleteOnRelease then
			addon.Engine:Cancel()
		end
	end)
	self:LayoutButtons()
end

function Decision:LayoutButtons()
	local accept = self.acceptButton
	local cancel = self.cancelButton
	local frame = self.frame
	if not accept or not cancel or not frame then
		return
	end
	local gap = 10
	accept:ClearAllPoints()
	cancel:ClearAllPoints()
	local showAccept = accept:IsShown()
	local showCancel = cancel:IsShown()
	if showAccept and showCancel then
		local total = accept:GetWidth() + gap + cancel:GetWidth()
		accept:SetPoint("BOTTOMLEFT", frame, "BOTTOM", -total / 2, 8)
		cancel:SetPoint("LEFT", accept, "RIGHT", gap, 0)
	elseif showAccept then
		accept:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
	elseif showCancel then
		cancel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
	end
	local bottom = (showAccept or showCancel) and 36 or 8
	if self.scroll then
		self.scroll:ClearAllPoints()
		self.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -28)
		self.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, bottom)
	end
end

function Decision:ShowItemTooltip(owner, item)
	if not GameTooltip or not item then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local shown = false
	if item.bag ~= nil and item.slot ~= nil and GameTooltip.SetBagItem then
		shown = pcall(GameTooltip.SetBagItem, GameTooltip, item.bag, item.slot)
	end
	if not shown and item.link and GameTooltip.SetHyperlink then
		shown = pcall(GameTooltip.SetHyperlink, GameTooltip, item.link)
	end
	if not shown and item.slot and not item.bag and GameTooltip.SetLootItem then
		shown = pcall(GameTooltip.SetLootItem, GameTooltip, item.slot)
	end
	if not shown and item.itemID and GameTooltip.SetItemByID then
		shown = pcall(GameTooltip.SetItemByID, GameTooltip, item.itemID)
	end
	if not shown then
		GameTooltip:SetText(item.name or "Item")
	end
	GameTooltip:Show()
end

function Decision:AcquireRow()
	local index = self.used + 1
	self.used = index
	local row = self.rows[index]
	if row then
		row:Show()
		return row
	end

	row = CreateFrame("Frame", nil, self.scroll.child)
	row:SetHeight(40)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(entered)
		if entered.item then
			Decision:ShowItemTooltip(entered, entered.item)
		end
	end)
	row:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	local iconButton = CreateFrame("Button", nil, row)
	iconButton:SetSize(24, 24)
	iconButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	iconButton:SetScript("OnMouseDown", function(button, mouseButton)
		if mouseButton ~= "LeftButton" or Decision.preview or not button.item or not button.item.openable then
			return
		end
		addon.Engine:OpenFromRow(button.item)
	end)
	iconButton:SetScript("OnEnter", function(button)
		if button.item then
			Decision:ShowItemTooltip(button, button.item)
		end
	end)
	iconButton:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	local icon = iconButton:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(iconButton)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	local reason = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	reason:SetJustifyH("RIGHT")
	local protect = CreateFrame("Button", nil, row)
	protect:SetSize(36, 36)
	protect:SetPoint("LEFT", row, "LEFT", 0, 0)
	protect:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	protect:SetScript("OnClick", function(button)
		if Decision.preview or not button.item then
			return
		end
		addon.Engine:ProtectAndRebuild(button.item)
	end)
	protect:SetScript("OnEnter", function(button)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		if button.item and button.item.protected then
			GameTooltip:SetText("Protected")
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
	protect:Hide()
	local skip = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	skip:SetSize(46, 22)
	skip:SetText("Skip")
	skip:SetScript("OnClick", function(button)
		if Decision.preview or not button.item then
			return
		end
		addon.Engine:SkipOpenable(button.item)
	end)
	skip:SetScript("OnEnter", function(button)
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("Skip")
		GameTooltip:Show()
	end)
	skip:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	skip:Hide()
	row.iconButton = iconButton
	row.icon = icon
	row.name = name
	row.reason = reason
	row.money = CreateCoins(row, self.frame)
	row.protect = protect
	row.skip = skip
	addon.RegisterFontString(self.frame, name)
	addon.RegisterFontString(self.frame, reason)
	self.rows[index] = row
	return row
end

local function FitButtonTexture(button, getter)
	local texture = button[getter](button)
	if texture then
		texture:ClearAllPoints()
		texture:SetAllPoints(button)
	end
end

function Decision:SetLock(button, locked)
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

function Decision:FillRow(row, item, forceValue, canProtect)
	row.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.name:SetText(item.name or "Unknown item")
	local r, g, b = addon.QualityColor(item.quality)
	row.name:SetTextColor(r, g, b)
	local label = ReasonLabel(item, forceValue)
	if label == "" and item.openable then
		label = "Open"
	end
	row.reason:SetText(label)
	row.reason:SetShown(label ~= "")
	row.money:SetCopper(item.value)
	row.item = item
	row.iconButton.item = item
	local showSkip = canProtect and item.openable and not self.preview
	local showProtect = canProtect and item.itemID and not showSkip
	row.protect.item = showProtect and item or nil
	row.protect:SetShown(showProtect and true or false)
	row.skip.item = showSkip and item or nil
	row.skip:SetShown(showSkip and true or false)
	if showProtect then
		self:SetLock(row.protect, item.protected)
	end

	row.protect:ClearAllPoints()
	row.skip:ClearAllPoints()
	row.iconButton:ClearAllPoints()
	row.money:ClearAllPoints()
	row.money:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	if showProtect then
		row.protect:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.iconButton:SetPoint("LEFT", row.protect, "RIGHT", 4, 0)
	elseif showSkip then
		row.skip:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.iconButton:SetPoint("LEFT", row.skip, "RIGHT", 4, 0)
	else
		row.iconButton:SetPoint("LEFT", row, "LEFT", 0, 0)
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.iconButton, "RIGHT", 6, 0)
	if label ~= "" then
		row.reason:ClearAllPoints()
		row.reason:SetPoint("RIGHT", row.money, "LEFT", -6, 0)
		row.name:SetPoint("RIGHT", row.reason, "LEFT", -6, 0)
	else
		row.name:SetPoint("RIGHT", row.money, "LEFT", -6, 0)
	end
end

local function Place(widget, child, y, height)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
	widget:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
	widget:Show()
	return y + height
end

function Decision:AddSection(child, y, header, title, items, forceValue, canProtect)
	header:SetText(title)
	y = Place(header, child, y, 22)
	if #items == 0 then
		return y
	end
	for _, item in ipairs(items) do
		local row = self:AcquireRow()
		self:FillRow(row, item, forceValue, canProtect)
		y = Place(row, child, y, 40)
	end
	return y + 6
end

-- Show one destroy→loot pair at a time (current Engine step / delete index).
function Decision:ViewLists(plan)
	local takes = plan.takes or {}
	local sacrifices = plan.sacrifices or {}
	local stepCount = 0
	local stepIndex = 1
	if self.preview or plan.directGrant then
		return takes, sacrifices, stepCount, stepIndex
	end
	local steps = plan.steps
	local engine = addon.Engine
	if not steps or #steps == 0 or not engine then
		return takes, sacrifices, stepCount, stepIndex
	end
	stepCount = #steps
	stepIndex = engine.stepIndex or 1
	local step = steps[stepIndex]
	if not step then
		return {}, {}, stepCount, stepIndex
	end
	-- Auto-destroy handles the current pair; the window only needs leftovers.
	if engine.autoDestroying then
		return {}, {}, stepCount, stepIndex
	end
	local deleteIndex = engine.deleteIndex or 1
	local current = step.sacrifices and step.sacrifices[deleteIndex]
	takes = step.take and { step.take } or {}
	sacrifices = current and { current } or {}
	return takes, sacrifices, stepCount, stepIndex
end

function Decision:Refresh()
	local plan = self.plan or SAMPLE
	self.used = 0
	for _, row in ipairs(self.rows) do
		row:Hide()
	end

	self.lootHeader:Hide()
	self.deleteHeader:Hide()
	self.leftHeader:Hide()
	self.lootMessage:Hide()

	local child = self.scroll.child
	local width = self.scroll:GetWidth() or 0
	if width > 1 then
		child:SetWidth(width)
	end
	local y = 0
	local viewTakes, viewSacrifices, stepCount, stepIndex = self:ViewLists(plan)
	local firstSacrifice = viewSacrifices[1]
	local openInstead = firstSacrifice and firstSacrifice.openInstead and not self.preview
	if plan.openGrant and not self.preview then
		local openName = plan.openItem and plan.openItem.name or "that item"
		self.lootHeader:SetText("Opening")
		y = Place(self.lootHeader, child, y, 22)
		if #viewSacrifices > 0 or #(plan.sacrifices or {}) > 0 then
			self.lootMessage:SetText("Click " .. addon.DestroyActionLabel() .. " to open " .. openName .. " and keep what is inside.")
		else
			self.lootMessage:SetText("Click Open to open " .. openName .. ".")
		end
		y = Place(self.lootMessage, child, y, 36)
		y = y + 6
	elseif plan.directGrant and not self.preview then
		self.lootHeader:SetText("Looting")
		y = Place(self.lootHeader, child, y, 22)
		if plan.readyLoot then
			self.lootMessage:SetText("A slot is free. Click Loot to take the quest item.")
		elseif openInstead then
			self.lootMessage:SetText("Click Open to open " .. (firstSacrifice.name or "the item") .. ". Then click the quest target again.")
		else
			self.lootMessage:SetText("Click " .. addon.DestroyActionLabel() .. " to take the quest item.")
		end
		y = Place(self.lootMessage, child, y, 36)
		y = y + 6
	elseif #viewTakes > 0 or self.preview then
		local lootTitle = "Looting"
		if stepCount > 1 then
			lootTitle = string.format("Looting (%d of %d)", stepIndex, stepCount)
		end
		y = self:AddSection(child, y, self.lootHeader, lootTitle, viewTakes, false)
	end
	if #viewSacrifices > 0 or self.preview then
		local sacrificeTitle = openInstead and "Opening" or "Deleting"
		y = self:AddSection(child, y, self.deleteHeader, sacrificeTitle, viewSacrifices, true, true)
	end
	if #(plan.leftBehind or {}) > 0 then
		y = self:AddSection(child, y, self.leftHeader, "Left on the corpse", plan.leftBehind or {}, false)
	end
	child:SetHeight(math.max(y, 1))
	self.scroll:SetVerticalScroll(0)

	local sacrifices = #viewSacrifices
	local takes = #viewTakes
	local leftoverOnly = not self.preview
		and not plan.openGrant
		and not plan.directGrant
		and #(plan.leftBehind or {}) > 0
		and sacrifices == 0
		and takes == 0
	if self.preview then
		self.acceptButton:SetText(addon.DestroyActionLabel())
		self.acceptButton:Show()
		self.acceptButton:Disable()
		self.cancelButton:Show()
	elseif leftoverOnly then
		self.acceptButton:Hide()
		self.cancelButton:Hide()
	elseif sacrifices > 0 and viewSacrifices[1].openInstead then
		self.acceptButton:SetText("Open")
		self.acceptButton:Show()
		self.acceptButton:Enable()
		self.cancelButton:Show()
	elseif sacrifices > 0 then
		self.acceptButton:SetText(addon.DestroyActionLabel())
		self.acceptButton:Show()
		self.acceptButton:Enable()
		self.cancelButton:Show()
	elseif plan.readyLoot then
		self.acceptButton:SetText("Loot")
		self.acceptButton:Show()
		self.acceptButton:Enable()
		self.cancelButton:Show()
	elseif plan.openGrant then
		self.acceptButton:SetText("Open")
		self.acceptButton:Show()
		self.acceptButton:Enable()
		self.cancelButton:Show()
	elseif takes > 0 then
		self.acceptButton:SetText("Loot")
		self.acceptButton:Show()
		self.acceptButton:Enable()
		self.cancelButton:Show()
	else
		self.acceptButton:Hide()
		self.cancelButton:Show()
	end
	addon.ApplyFontSize(self.frame)
	self:LayoutButtons()
	self:FitToContents()
end

function Decision:FitToContents()
	local frame = self.frame
	local child = self.scroll and self.scroll.child
	if not frame or not child then
		return
	end
	local content = child:GetHeight() or 1
	local hasButtons = (self.acceptButton and self.acceptButton:IsShown())
		or (self.cancelButton and self.cancelButton:IsShown())
	local buttonPad = hasButtons and 36 or 8
	local chrome = 28 + buttonPad + 2
	local height = content + chrome
	local parent = UIParent
	local parentHeight = parent and parent:GetHeight() or 800
	local minH = chrome + 1
	local maxH = math.max(minH, parentHeight * 0.7)
	if height < minH then
		height = minH
	elseif height > maxH then
		height = maxH
	end
	local left = frame:GetLeft()
	local top = frame:GetTop()
	local oldBottom = frame:GetBottom()
	local oldHeight = frame:GetHeight() or height
	frame:SetHeight(height)
	if not left or not top or not oldBottom or not parent then
		return
	end
	local scale = frame:GetScale() or 1
	local span = top - oldBottom
	if oldHeight > 0 then
		span = span * (height / oldHeight)
	end
	local parentBottom = parent:GetBottom() or 0
	-- Keep the top edge. Grow up only when growing down would leave the UI.
	local pinTop = top
	if top - span < parentBottom then
		pinTop = parentBottom + span
		local parentTop = parent:GetTop() or parentHeight
		if pinTop > parentTop then
			pinTop = parentTop
		end
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -((parentHeight - (pinTop * scale)) / scale))
end

function Decision:ShowPlan(plan, preview)
	self:Initialize()
	self.preview = preview and true or false
	self.plan = plan
	self:Refresh()
	self.frame:Show()
	self:FitToContents()
end

function Decision:SetPreview(active)
	self:Initialize()
	if active then
		if addon.Engine:GetState() ~= "confirming" then
			self:ShowPlan(SAMPLE, true)
		else
			self.frame:Show()
		end
	elseif addon.Engine:GetState() ~= "confirming" then
		self.preview = false
		self.frame:Hide()
	end
end

function Decision:Hide()
	if self.frame then
		self.frame:Hide()
	end
end
