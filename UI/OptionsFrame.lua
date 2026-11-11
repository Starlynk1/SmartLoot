local addon = SmartLoot or {}
SmartLoot = addon

local Options = {}
addon.Options = Options

function Options:Initialize()
	if self.frame then
		return
	end
	local frame = addon.CreateWindow("SmartLootOptionsFrame", "SmartLoot Options", 460, 540)
	self.frame = frame
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Options:SavePosition()
	end)
	self:ApplyPosition()
	self.rows = {}
	self.checks = {}

	local content = addon.ContentRegion(frame)
	self.lootPage = CreateFrame("Frame", nil, content)
	self.lootPage:SetAllPoints(content)
	self.rollPage = CreateFrame("Frame", nil, content)
	self.rollPage:SetAllPoints(content)
	self.protectPage = CreateFrame("Frame", nil, content)
	self.protectPage:SetAllPoints(content)

	self:BuildLootPage()

	local hint = self.protectPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", self.protectPage, "TOPLEFT", 16, -8)
	hint:SetText("Shift-click a bag item, or enter an item ID.")
	addon.RegisterFontString(frame, hint)

	local scroll = addon.CreateScroll(self.protectPage)
	scroll:SetPoint("TOPLEFT", self.protectPage, "TOPLEFT", 16, -28)
	scroll:SetPoint("BOTTOMRIGHT", self.protectPage, "BOTTOMRIGHT", -16, 40)
	self.scroll = scroll

	self.empty = scroll.child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	self.empty:SetText("No protected items.")
	self.empty:SetJustifyH("LEFT")
	addon.RegisterFontString(frame, self.empty)

	self.input = CreateFrame("EditBox", "SmartLootProtectBox", self.protectPage, "InputBoxTemplate")
	self.input:SetSize(180, 22)
	self.input:SetPoint("BOTTOMLEFT", self.protectPage, "BOTTOMLEFT", 22, 8)
	self.input:SetAutoFocus(false)
	self.input:SetScript("OnEnterPressed", function(box)
		Options:AddFromText(box:GetText())
		box:SetText("")
		box:ClearFocus()
	end)
	self.input:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)

	local addButton = addon.CreateButton(self.protectPage, "Add", 80)
	addButton:SetPoint("LEFT", self.input, "RIGHT", 8, 0)
	addButton:SetScript("OnClick", function()
		Options:AddFromText(self.input:GetText())
		self.input:SetText("")
		self.input:ClearFocus()
	end)

	self:BuildRollPage()
	self:CreateTabs(frame)
	self:Refresh()
	self:HookBags()
end

-- lineParent: stretch underline across this frame (use loot page when parent is a 1px section wrapper).
local function SectionHeader(parent, frame, title, y, lineParent)
	local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
	header:SetText(title)
	addon.RegisterFontString(frame, header)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.5, 0.5, 0.5, 0.45)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	line:SetPoint("RIGHT", lineParent or parent, "RIGHT", -20, 0)
	return y - 28
end

local function PlaceCheck(parent, frame, checks, info, x, y, textWidth)
	local box = addon.CreateCheckbox(parent, info.name, info.label, frame)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	box.info = info
	box:SetScript("OnClick", function(self)
		Options:OnCheck(self)
	end)
	local text = box.Text or _G[info.name .. "Text"]
	if text and textWidth then
		text:SetWidth(textWidth)
	end
	checks[info.key] = box
	return box
end

function Options:BuildLootPage()
	local frame = self.frame
	local page = self.lootPage
	local checks = self.checks
	local y = -8

	y = SectionHeader(page, frame, "General", y)
	PlaceCheck(page, frame, checks, {
		key = "enabled",
		name = "SmartLootCheckEnabled",
		label = "Enable SmartLoot",
	}, 10, y, 380)
	y = y - 32
	PlaceCheck(page, frame, checks, {
		key = "autoDestroy",
		name = "SmartLootCheckAutoDestroy",
		label = "Auto-destroy when looting",
	}, 10, y, 200)
	local upTo = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	upTo:SetPoint("LEFT", checks.autoDestroy, "RIGHT", 210, 0)
	upTo:SetText("up to")
	addon.RegisterFontString(frame, upTo)
	self.qualityLabel = upTo
	local quality = addon.CreateButton(page, "Grey", 72)
	quality:SetPoint("LEFT", upTo, "RIGHT", 8, 0)
	quality:SetScript("OnClick", function()
		Options:CycleAutoDestroyQuality()
	end)
	self.qualityButton = quality
	y = y - 40

	local junkLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	junkLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
	junkLabel:SetText("Destroy junk from")
	addon.RegisterFontString(frame, junkLabel)
	self.junkSourceLabel = junkLabel
	local junk = addon.CreateOptionsDropdown(page, frame, 140, {
		{ value = "quality", text = "Grey items" },
		{ value = "baganator", text = "Baganator" },
		{ value = "rxpguides", text = "RestedXP" },
	}, function()
		return addon.JunkSource and addon.JunkSource() or "quality"
	end, function(value)
		Options:SetJunkSource(value)
	end)
	junk:SetPoint("LEFT", junkLabel, "RIGHT", 12, 0)
	self.junkSourceDropdown = junk
	y = y - 40

	local closeLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	closeLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
	closeLabel:SetText("Auto-close leftover loot")
	addon.RegisterFontString(frame, closeLabel)
	self.autoCloseLabel = closeLabel
	local slider = addon.CreateOptionsSlider("SmartLootAutoCloseSlider", page)
	slider:SetSize(180, 16)
	slider:SetPoint("LEFT", closeLabel, "RIGHT", 16, 0)
	slider:SetMinMaxValues(0, 15)
	slider:SetValueStep(1)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	local low = _G[slider:GetName() .. "Low"]
	local high = _G[slider:GetName() .. "High"]
	local text = _G[slider:GetName() .. "Text"]
	if low then
		low:SetText("Off")
		addon.RegisterFontString(frame, low)
	end
	if high then
		high:SetText("15s")
		addon.RegisterFontString(frame, high)
	end
	if text then
		text:SetText("")
		text:Hide()
	end
	self.autoCloseValue = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.autoCloseValue:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	addon.RegisterFontString(frame, self.autoCloseValue)
	slider:SetScript("OnValueChanged", function(_, value)
		Options:SetAutoCloseLeftover(value)
	end)
	self.autoCloseSlider = slider
	y = y - 52

	y = SectionHeader(page, frame, "Values", y)
	PlaceCheck(page, frame, checks, {
		key = "useAuctionValue",
		name = "SmartLootCheckAuction",
		label = "Use auction value when available",
	}, 10, y, 380)
	y = y - 30
	PlaceCheck(page, frame, checks, {
		key = "protectCraftingReagents",
		name = "SmartLootCheckReagents",
		label = "Protect crafting reagents",
	}, 10, y, 380)
	y = y - 36
	self.lootAfterValuesY = y

	local warlock = CreateFrame("Frame", nil, page)
	warlock:SetSize(1, 1)
	warlock:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
	self.warlockSection = warlock

	local wy = SectionHeader(warlock, frame, "Warlock", 0, page)
	local shardLabel = warlock:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	shardLabel:SetPoint("TOPLEFT", warlock, "TOPLEFT", 20, wy)
	shardLabel:SetText("Soul shards to keep")
	addon.RegisterFontString(frame, shardLabel)

	local shard = CreateFrame("EditBox", "SmartLootKeepSoulShards", warlock, "InputBoxTemplate")
	shard:SetSize(56, 22)
	shard:SetPoint("LEFT", shardLabel, "RIGHT", 12, 0)
	shard:SetAutoFocus(false)
	shard:SetNumeric(true)
	shard:SetMaxLetters(4)
	shard:SetScript("OnEnterPressed", function(box)
		Options:CommitKeepSoulShards(box)
		box:ClearFocus()
	end)
	shard:SetScript("OnEscapePressed", function(box)
		box:SetText(tostring(addon.db and addon.db.keepSoulShards or 0))
		box:ClearFocus()
	end)
	self.keepSoulShards = shard

	local ok = addon.CreateButton(warlock, "OK", 48)
	ok:SetPoint("LEFT", shard, "RIGHT", 8, 0)
	ok:SetScript("OnClick", function()
		Options:CommitKeepSoulShards(shard)
		shard:ClearFocus()
	end)

	local shardNote = warlock:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	shardNote:SetPoint("TOPLEFT", shardLabel, "BOTTOMLEFT", 0, -6)
	shardNote:SetWidth(400)
	shardNote:SetJustifyH("LEFT")
	shardNote:SetText("Overflow shards in regular bags above this floor (and soul-bag capacity) may be deleted.")
	addon.RegisterFontString(frame, shardNote)
	warlock:SetHeight(78)

	local display = CreateFrame("Frame", nil, page)
	display:SetSize(1, 1)
	self.displaySection = display
	local dy = SectionHeader(display, frame, "Display", 0, page)
	PlaceCheck(display, frame, checks, {
		key = "showMinimap",
		name = "SmartLootCheckMinimap",
		label = "Show on the minimap",
		group = "minimap",
	}, 10, dy, 180)
	PlaceCheck(display, frame, checks, {
		key = "showCompartment",
		name = "SmartLootCheckCompartment",
		label = "Show in the addon compartment",
		group = "minimap",
	}, 220, dy, 200)
	display:SetHeight(56)

	self:RefreshWarlockSection()
end

function Options:RefreshWarlockSection()
	local warlock = self.warlockSection
	local display = self.displaySection
	local page = self.lootPage
	if not warlock or not display or not page then
		return
	end
	local show = addon.IsWarlock and addon.IsWarlock()
	warlock:SetShown(show and true or false)
	warlock:ClearAllPoints()
	display:ClearAllPoints()
	local y = self.lootAfterValuesY or -120
	if show then
		warlock:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
		display:SetPoint("TOPLEFT", warlock, "BOTTOMLEFT", 0, -12)
	else
		display:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
	end
end

function Options:BuildRollPage()
	local frame = self.frame
	local page = self.rollPage
	local roll = addon.CreateCheckbox(page, "SmartLootCheckAutoRoll", "Auto-roll in a party or raid", frame)
	roll:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -4)
	roll:SetScript("OnClick", function(box)
		addon.db.autoRoll = box:GetChecked() and true or false
	end)
	self.rollCheck = roll

	local levelLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	levelLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -44)
	levelLabel:SetText("Minimum item level")
	addon.RegisterFontString(frame, levelLabel)

	local level = CreateFrame("EditBox", "SmartLootRollLevel", page, "InputBoxTemplate")
	level:SetSize(64, 22)
	level:SetPoint("LEFT", levelLabel, "RIGHT", 16, 0)
	level:SetAutoFocus(false)
	level:SetNumeric(true)
	level:SetMaxLetters(4)
	level:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
	end)
	level:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)
	level:SetScript("OnEditFocusLost", function(box)
		Options:CommitRollLevel(box)
	end)
	self.rollLevel = level

	local transmog = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	transmog:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -84)
	transmog:SetText("Missing transmog")
	addon.RegisterFontString(frame, transmog)
	self.transmogLabel = transmog

	local need = addon.CreateCheckbox(page, "SmartLootCheckTransmogNeed", "Need", frame)
	need:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -108)
	local needText = need.Text or _G["SmartLootCheckTransmogNeedText"]
	if needText then
		needText:SetWidth(70)
	end
	need:SetScript("OnClick", function()
		addon.db.transmogRoll = "need"
		Options:RefreshRolls()
	end)
	self.transmogNeed = need

	local greed = addon.CreateCheckbox(page, "SmartLootCheckTransmogGreed", "Greed", frame)
	greed:SetPoint("LEFT", need, "RIGHT", 120, 0)
	local greedText = greed.Text or _G["SmartLootCheckTransmogGreedText"]
	if greedText then
		greedText:SetWidth(70)
	end
	greed:SetScript("OnClick", function()
		addon.db.transmogRoll = "greed"
		Options:RefreshRolls()
	end)
	self.transmogGreed = greed

	local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	note:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -156)
	note:SetWidth(380)
	note:SetJustifyH("LEFT")
	note:SetText("Need when the item is usable and a higher item level than the weaker piece in that slot. Otherwise greed. Items under the minimum item level stay on the roll window. An upgrade still needs when missing transmog is set to greed.")
	addon.RegisterFontString(frame, note)
	self.rollNote = note
end

function Options:CommitRollLevel(box)
	local number = tonumber(box:GetText())
	if not number or number < 0 then
		number = addon.db.rollMinItemLevel or 1
	end
	addon.db.rollMinItemLevel = math.floor(number)
	box:SetText(tostring(addon.db.rollMinItemLevel))
end

function Options:CommitKeepSoulShards(box)
	local number = tonumber(box:GetText())
	if not number or number < 0 then
		number = addon.db.keepSoulShards or 0
	end
	addon.db.keepSoulShards = math.floor(number)
	box:SetText(tostring(addon.db.keepSoulShards))
end

function Options:RefreshRolls()
	if not self.rollCheck or not addon.db then
		return
	end
	self.rollCheck:SetChecked(addon.db.autoRoll)
	if not self.rollLevel:HasFocus() then
		self.rollLevel:SetText(tostring(addon.db.rollMinItemLevel or 1))
	end
	local hasTransmog = addon.HasTransmog and addon.HasTransmog()
	if self.transmogLabel then
		self.transmogLabel:SetShown(hasTransmog and true or false)
	end
	if self.transmogNeed then
		self.transmogNeed:SetShown(hasTransmog and true or false)
	end
	if self.transmogGreed then
		self.transmogGreed:SetShown(hasTransmog and true or false)
	end
	if self.rollNote then
		if hasTransmog then
			self.rollNote:SetPoint("TOPLEFT", self.rollPage, "TOPLEFT", 16, -156)
			self.rollNote:SetText("Need when the item is usable and a higher item level than the weaker piece in that slot. Otherwise greed. Items under the minimum item level stay on the roll window. An upgrade still needs when missing transmog is set to greed.")
		else
			self.rollNote:SetPoint("TOPLEFT", self.rollPage, "TOPLEFT", 16, -84)
			self.rollNote:SetText("Need when the item is usable and a higher item level than the weaker piece in that slot. Otherwise greed. Items under the minimum item level stay on the roll window.")
		end
	end
	if not hasTransmog then
		return
	end
	local need = addon.db.transmogRoll == "need"
	self.transmogNeed:SetChecked(need)
	self.transmogGreed:SetChecked(not need)
end

local TAB_ICONS = {
	"Interface\\AddOns\\SmartLoot\\Art\\SmartLoot-Portrait",
	"Interface\\Icons\\INV_Misc_Dice_02",
	"Interface\\Icons\\INV_Misc_Key_03",
}
local TAB_TIPS = { "Loot", "Rolls", "Protected" }
local TAB_LABELS = { "Loot", "Rolls", "Protected" }

function Options:CreateTabs(frame)
	self.tabs = {}
	if addon.UsesSideOptionsTabs and addon.UsesSideOptionsTabs() then
		self:CreateSideTabs(frame)
	else
		self:CreateBottomTabs(frame)
	end
	self:ShowPage(1)
end

function Options:CreateSideTabs(frame)
	local previous
	for index = 1, #TAB_TIPS do
		local tab = CreateFrame("CheckButton", nil, frame)
		tab:SetSize(32, 32)
		local background = tab:CreateTexture(nil, "BACKGROUND")
		background:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		background:SetSize(64, 64)
		background:SetPoint("TOPLEFT", -3, 11)
		local icon = tab:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(TAB_ICONS[index])
		icon:SetPoint("CENTER", 0, 0)
		if index == 1 then
			-- Slightly smaller draw size; art files stay untouched.
			icon:SetSize(30, 30)
			icon:SetTexCoord(0, 1, 0, 1)
		else
			icon:SetSize(30, 30)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
		local checked = tab:GetCheckedTexture()
		if checked then
			checked:SetBlendMode("ADD")
		end
		tab.tooltipText = TAB_TIPS[index]
		tab:SetScript("OnClick", function()
			Options:ShowPage(index)
		end)
		tab:SetScript("OnEnter", function(self)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.tooltipText)
				GameTooltip:Show()
			end
		end)
		tab:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		if previous then
			tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -17)
		else
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -36)
		end
		previous = tab
		self.tabs[index] = tab
	end
end

function Options:CreateBottomTabs(frame)
	local previous
	for index = 1, #TAB_LABELS do
		local name = frame:GetName() .. "Tab" .. index
		local created, tab = pcall(CreateFrame, "Button", name, frame, "PanelTabButtonTemplate")
		if not created then
			tab = CreateFrame("Button", name, frame, "UIPanelButtonTemplate")
			tab:SetSize(90, 22)
		end
		tab:SetID(index)
		tab:SetText(TAB_LABELS[index])
		if PanelTemplates_TabResize then
			PanelTemplates_TabResize(tab, 0, nil, 60)
		end
		tab:SetScript("OnClick", function(self)
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			end
			Options:ShowPage(self:GetID())
		end)
		if previous then
			tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
		else
			tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, -30)
		end
		previous = tab
		self.tabs[index] = tab
	end
	if PanelTemplates_SetNumTabs then
		PanelTemplates_SetNumTabs(frame, #TAB_LABELS)
	end
end

function Options:ShowPage(page)
	self.page = page
	self.lootPage:SetShown(page == 1)
	self.rollPage:SetShown(page == 2)
	self.protectPage:SetShown(page == 3)
	if addon.UsesSideOptionsTabs and addon.UsesSideOptionsTabs() then
		for index = 1, #self.tabs do
			self.tabs[index]:SetChecked(index == page)
		end
		return
	end
	if PanelTemplates_SetTab then
		PanelTemplates_SetTab(self.frame, page)
	end
end

local AUTO_DESTROY_QUALITY = {
	[0] = "Grey",
	[1] = "White",
	[2] = "Green",
}

function Options:SetJunkSource(value)
	if not addon.db then
		return
	end
	if value ~= "baganator" and value ~= "rxpguides" then
		value = "quality"
	end
	addon.db.junkSource = value
	self:RefreshJunkSource()
	if addon.Inventory and addon.Inventory.RefreshCache then
		addon.Inventory.RefreshCache()
	end
end

function Options:RefreshJunkSource()
	if self.junkSourceDropdown and self.junkSourceDropdown.Refresh then
		self.junkSourceDropdown:Refresh()
	end
end

function Options:CycleAutoDestroyQuality()
	if not addon.db or not addon.db.autoDestroy then
		return
	end
	local quality = (addon.db.autoDestroyMaxQuality or 0) + 1
	if quality > 2 then
		quality = 0
	end
	addon.db.autoDestroyMaxQuality = quality
	self:RefreshAutoDestroy()
	if addon.Inventory and addon.Inventory.RebuildJunk then
		addon.Inventory.RebuildJunk()
	end
end

function Options:AutoCloseText(seconds)
	seconds = math.floor((tonumber(seconds) or 0) + 0.5)
	if seconds <= 0 then
		return "Off"
	end
	return seconds .. "s"
end

function Options:SetAutoCloseLeftover(value)
	local seconds = math.floor((tonumber(value) or 0) + 0.5)
	if seconds < 0 then
		seconds = 0
	elseif seconds > 15 then
		seconds = 15
	end
	if addon.db then
		addon.db.autoCloseLeftover = seconds
	end
	if self.autoCloseValue then
		self.autoCloseValue:SetText(self:AutoCloseText(seconds))
	end
end

function Options:RefreshAutoClose()
	if not self.autoCloseSlider then
		return
	end
	local seconds = 5
	if addon.db and addon.db.autoCloseLeftover ~= nil then
		seconds = tonumber(addon.db.autoCloseLeftover) or 5
	end
	if seconds < 0 then
		seconds = 0
	elseif seconds > 15 then
		seconds = 15
	end
	self.autoCloseSlider:SetValue(seconds)
	self:SetAutoCloseLeftover(seconds)
end

function Options:RefreshAutoDestroy()
	if not self.checks.autoDestroy or not addon.db then
		return
	end
	local on = addon.db.autoDestroy and true or false
	self.checks.autoDestroy:SetChecked(on)
	local quality = addon.db.autoDestroyMaxQuality or 0
	if quality < 0 then
		quality = 0
	elseif quality > 2 then
		quality = 2
	end
	if self.qualityLabel then
		if on then
			self.qualityLabel:SetTextColor(1, 1, 1)
		else
			self.qualityLabel:SetTextColor(0.5, 0.5, 0.5)
		end
	end
	if self.qualityButton then
		self.qualityButton:SetText(AUTO_DESTROY_QUALITY[quality] or "Grey")
		local font = self.qualityButton.GetFontString and self.qualityButton:GetFontString()
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if font and color then
			font:SetTextColor(color.r, color.g, color.b)
		end
		if on then
			self.qualityButton:Enable()
		else
			self.qualityButton:Disable()
		end
	end
end

function Options:OnCheck(box)
	local info = box.info
	local checked = box:GetChecked() and true or false
	if info.key == "enabled" then
		addon:SetEnabled(checked)
		return
	end
	if info.group == "minimap" then
		addon.db.minimap[info.key] = checked
		if addon.Minimap then
			addon.Minimap:Update()
		end
		return
	end
	addon.db[info.key] = checked
	if info.key == "autoDestroy" then
		self:RefreshAutoDestroy()
		if addon.Inventory and addon.Inventory.RefreshCache then
			addon.Inventory.RefreshCache()
		end
	end
end

function Options:Refresh()
	if not self.frame or not addon.db then
		return
	end
	self.checks.enabled:SetChecked(addon.db.enabled)
	self:RefreshAutoDestroy()
	self:RefreshJunkSource()
	self:RefreshAutoClose()
	self.checks.protectCraftingReagents:SetChecked(addon.db.protectCraftingReagents)
	self.checks.useAuctionValue:SetChecked(addon.db.useAuctionValue)
	if self.keepSoulShards and not self.keepSoulShards:HasFocus() then
		self.keepSoulShards:SetText(tostring(addon.db.keepSoulShards or 0))
	end
	if addon.Minimap then
		addon.Minimap:Normalize()
	end
	self.checks.showMinimap:SetChecked(addon.db.minimap.showMinimap)
	self.checks.showCompartment:SetChecked(addon.db.minimap.showCompartment)
	local compartment = addon.Minimap and addon.Minimap:HasCompartment()
	self.checks.showCompartment:SetShown(compartment and true or false)
	self:RefreshRolls()
	self:RefreshProtected()
end

function Options:AcquireRow()
	local index = self.used + 1
	self.used = index
	local row = self.rows[index]
	if row then
		row:Show()
		return row
	end
	row = CreateFrame("Frame", nil, self.scroll.child)
	row:SetHeight(24)
	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("LEFT", 0, 0)
	name:SetJustifyH("LEFT")
	name:SetWidth(220)
	local remove = addon.CreateButton(row, "Remove", 80)
	remove:SetPoint("RIGHT", 0, 0)
	row.name = name
	row.remove = remove
	addon.RegisterFontString(self.frame, name)
	self.rows[index] = row
	return row
end

function Options:RefreshProtected()
	if not self.frame or not addon.db then
		return
	end
	self.used = 0
	for _, row in ipairs(self.rows) do
		row:Hide()
	end
	local ids = {}
	for itemID in pairs(addon.db.protected) do
		ids[#ids + 1] = itemID
	end
	table.sort(ids)

	local child = self.scroll.child
	child:SetWidth(math.max(self.scroll:GetWidth() or 0, 280))
	if #ids == 0 then
		self.empty:ClearAllPoints()
		self.empty:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
		self.empty:Show()
		child:SetHeight(20)
		return
	end
	self.empty:Hide()
	local y = 0
	for _, itemID in ipairs(ids) do
		local row = self:AcquireRow()
		local stored = addon.db.protected[itemID]
		local label = type(stored) == "string" and stored or ("Item " .. itemID)
		row.name:SetText(label)
		row.remove:SetScript("OnClick", function()
			addon:UnprotectItem(itemID)
		end)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
		y = y + 26
	end
	child:SetHeight(math.max(y, 1))
	self.scroll:SetVerticalScroll(0)
end

function Options:AddFromText(text)
	local itemID = addon.ParseItemID(text)
	if not itemID then
		addon.Print("Use an item ID, an item link, or shift-click a bag item.")
		return
	end
	local name
	if C_Item and C_Item.GetItemInfo then
		local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
		if ok then
			name = itemName
		end
	end
	addon:ProtectItem(itemID, name)
end

function Options:TryProtectFromBag(button)
	if not self.frame or not self.frame:IsShown() then
		return
	end
	if not IsModifiedClick or not IsModifiedClick("CHATLINK") then
		return
	end
	if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
		return
	end
	if not button.GetBagID or not C_Container then
		return
	end
	local bag, slot = button:GetBagID(), button:GetID()
	local itemID = C_Container.GetContainerItemID(bag, slot)
	if not itemID then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	addon:ProtectItem(itemID, info and info.itemName)
	self:ShowPage(3)
end

function Options:HookBags()
	if self.hooked or not hooksecurefunc or not ContainerFrameItemButtonMixin then
		return
	end
	self.hooked = true
	hooksecurefunc(ContainerFrameItemButtonMixin, "OnModifiedClick", function(button)
		Options:TryProtectFromBag(button)
	end)
end

function Options:Position()
	local db = addon.db
	if not db then
		return { point = "CENTER", relativePoint = "CENTER", x = 0, y = -40 }
	end
	if db.optionsPosition and db.optionsPosition.point then
		return db.optionsPosition
	end
	local migrated
	local layouts = db.layouts
	if layouts then
		local index = addon.EditMode and addon.EditMode:GetActiveLayoutIndex() or 1
		local layout = layouts[index] or layouts[1]
		if layout and layout.options then
			migrated = layout.options
		end
	end
	db.optionsPosition = {
		point = migrated and migrated.point or "CENTER",
		relativePoint = migrated and migrated.relativePoint or "CENTER",
		x = migrated and migrated.x or 0,
		y = migrated and migrated.y or -40,
	}
	return db.optionsPosition
end

function Options:ApplyPosition()
	if not self.frame then
		return
	end
	local saved = self:Position()
	self.frame:ClearAllPoints()
	self.frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 0, saved.y or -40)
	self.frame:SetScale(1)
end

function Options:SavePosition()
	if not self.frame or not addon.db then
		return
	end
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	addon.db.optionsPosition = {
		point = point or "CENTER",
		relativePoint = relativePoint or "CENTER",
		x = x or 0,
		y = y or -40,
	}
end

function Options:Toggle()
	self:Initialize()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self:ApplyPosition()
		self:Refresh()
		self.frame:Show()
	end
end
