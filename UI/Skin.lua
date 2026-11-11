local addon = SmartLoot or {}
SmartLoot = addon

local ICON = "Interface\\AddOns\\SmartLoot\\Art\\SmartLoot-Icon"
-- Opaque charcoal portrait; transparent Icon TGA renders badly in the round mask.
local PORTRAIT = "Interface\\AddOns\\SmartLoot\\Art\\SmartLoot-Portrait"

function addon.Print(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SmartLoot:|r " .. tostring(message))
	end
end

function addon.Trim(text)
	text = tostring(text or "")
	if strtrim then
		return strtrim(text)
	end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function addon.ParseItemID(text)
	text = addon.Trim(text)
	local id = tonumber(text)
	if id then
		return id
	end
	return tonumber(text:match("item:(%d+)"))
end

function addon.RegisterFontString(owner, fontString)
	if not owner or not fontString then
		return
	end
	owner.smartLootFonts = owner.smartLootFonts or {}
	for _, existing in ipairs(owner.smartLootFonts) do
		if existing == fontString then
			addon.ApplyFontSize(owner)
			return
		end
	end
	owner.smartLootFonts[#owner.smartLootFonts + 1] = fontString
	addon.ApplyFontSize(owner)
end

function addon.ApplyFontSize(owner, size)
	if not owner then
		return
	end
	if size then
		owner.smartLootFontSize = size
	end
	local fontSize = owner.smartLootFontSize or 12
	local fonts = owner.smartLootFonts
	if not fonts then
		return
	end
	for _, fontString in ipairs(fonts) do
		if fontString and fontString.GetFont then
			local font, _, flags = fontString:GetFont()
			if font then
				fontString:SetFont(font, fontSize, flags)
			end
		end
	end
end

function addon.QualityColor(quality)
	if C_Item and C_Item.GetItemQualityColor and quality ~= nil then
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if r then
			return r, g, b
		end
	end
	if quality == 0 then
		return 0.62, 0.62, 0.62
	elseif quality == 2 then
		return 0.12, 1, 0
	elseif quality == 3 then
		return 0, 0.44, 0.87
	elseif quality == 4 then
		return 0.64, 0.21, 0.93
	end
	return 1, 1, 1
end

function addon.FormatMoney(copper)
	copper = math.floor(tonumber(copper) or 0)
	if copper < 0 then
		copper = 0
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local remainder = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = gold .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
	end
	if gold > 0 or silver > 0 then
		parts[#parts + 1] = silver .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
	end
	parts[#parts + 1] = remainder .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
	return table.concat(parts, " ")
end

function addon.ContentRegion(frame)
	return frame.Inset or frame
end

function addon.CreateLootWindow(name, title, width, height)
	local frame
	local ok = pcall(function()
		frame = CreateFrame("Frame", name, UIParent, "DefaultPanelFlatTemplate")
	end)
	if not ok or not frame then
		ok = pcall(function()
			frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
		end)
	end
	if not ok or not frame then
		frame = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true,
				tileSize = 32,
				edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end
	end
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	if frame.SetDontSavePosition then
		pcall(frame.SetDontSavePosition, frame, true)
	end
	if frame.SetTitle then
		frame:SetTitle(title)
	elseif frame.TitleContainer and frame.TitleContainer.TitleText then
		frame.TitleContainer.TitleText:SetText(title)
	elseif frame.TitleText then
		frame.TitleText:SetText(title)
	else
		local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		titleText:SetPoint("TOP", 0, -10)
		titleText:SetText(title)
		frame.TitleText = titleText
		addon.RegisterFontString(frame, titleText)
	end
	if frame.TitleContainer and frame.TitleContainer.TitleText then
		addon.RegisterFontString(frame, frame.TitleContainer.TitleText)
	elseif frame.TitleText then
		addon.RegisterFontString(frame, frame.TitleText)
	end
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 4)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	frame.smartLootFontSize = 12
	frame:Hide()
	return frame
end

-- SetPortraitToAsset / SetPortraitToTexture wants 64x64 BLP and often fails on
-- custom TGA art. Raw portrait + padded coords keeps the logo inside the circle.
function addon.SetWindowPortrait(frame, path)
	if not frame or not path then
		return
	end
	-- In-game only: shrink (~20% pad) and nudge up ~5px via UV. Never ClearAllPoints.
	local pad = 0.2
	local up = 5 / 64
	local left, right = -pad, 1 + pad
	local top, bottom = -pad + up, 1 + pad + up
	if frame.SetPortraitTextureRaw then
		frame:SetPortraitTextureRaw(path)
		if frame.SetPortraitTexCoord then
			frame:SetPortraitTexCoord(left, right, top, bottom)
			return
		end
	end
	local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
	if not portrait and frame.GetName then
		portrait = _G[frame:GetName() .. "Portrait"]
	end
	portrait = portrait or frame.portrait
	if portrait then
		if not frame.SetPortraitTextureRaw then
			portrait:SetTexture(path)
		end
		portrait:SetTexCoord(left, right, top, bottom)
	end
end

function addon.CreateWindow(name, title, width, height)
	local frame
	local ok = pcall(function()
		frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	end)
	if not ok or not frame then
		frame = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true,
				tileSize = 32,
				edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
	end
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	if frame.SetDontSavePosition then
		pcall(frame.SetDontSavePosition, frame, true)
	end
	if frame.SetTitle then
		frame:SetTitle(title)
	elseif frame.TitleText then
		frame.TitleText:SetText(title)
	end
	addon.SetWindowPortrait(frame, PORTRAIT)
	if frame.TitleContainer and frame.TitleContainer.TitleText then
		addon.RegisterFontString(frame, frame.TitleContainer.TitleText)
	elseif frame.TitleText then
		addon.RegisterFontString(frame, frame.TitleText)
	end
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	frame.smartLootFontSize = 12
	frame:Hide()
	return frame
end

function addon.CreateOptionsSlider(name, parent)
	local slider
	local ok = pcall(function()
		slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	end)
	if not ok or not slider then
		ok = pcall(function()
			slider = CreateFrame("Slider", name, parent, "UISliderTemplate")
		end)
	end
	if not ok or not slider then
		slider = CreateFrame("Slider", name, parent)
		slider:SetOrientation("HORIZONTAL")
	end
	return slider
end

function addon.CreateButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 140, 22)
	button:SetText(text)
	if button.GetFontString then
		addon.RegisterFontString(parent, button:GetFontString())
	end
	return button
end

local function DropdownLabel(choices, value)
	for index = 1, #choices do
		if choices[index].value == value then
			return choices[index].text
		end
	end
	return choices[1] and choices[1].text or ""
end

function addon.CreateOptionsDropdown(parent, fontOwner, width, choices, getSelected, setSelected)
	local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	button:SetSize(width or 140, 24)
	if button.SetBackdrop then
		button:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	end
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -18, 0)
	label:SetJustifyH("LEFT")
	addon.RegisterFontString(fontOwner or parent, label)
	button.label = label
	local arrow = button:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -4, 0)

	local menu = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetToplevel(true)
	menu:Hide()
	if menu.SetBackdrop then
		menu:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	end
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:Hide()

	local rows = {}
	local function CloseMenu()
		menu:Hide()
		catcher:Hide()
	end

	local function RefreshRows()
		local selected = getSelected and getSelected()
		for index = 1, #rows do
			local row = rows[index]
			if row.value == selected then
				row:LockHighlight()
			else
				row:UnlockHighlight()
			end
		end
		label:SetText(DropdownLabel(choices, selected))
	end

	local rowHeight = 20
	for index = 1, #choices do
		local choice = choices[index]
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * rowHeight)
		row:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * rowHeight)
		row.value = choice.value
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", 6, 0)
		text:SetPoint("RIGHT", -6, 0)
		text:SetJustifyH("LEFT")
		text:SetText(choice.text)
		addon.RegisterFontString(fontOwner or parent, text)
		row:SetScript("OnClick", function()
			if setSelected then
				setSelected(choice.value)
			end
			CloseMenu()
			RefreshRows()
		end)
		rows[index] = row
	end
	menu:SetSize(width or 140, (#choices * rowHeight) + 8)

	local function OpenMenu()
		RefreshRows()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
		menu:SetWidth(button:GetWidth())
		catcher:SetFrameLevel(math.max((menu:GetFrameLevel() or 1) - 1, 1))
		menu:SetFrameLevel((catcher:GetFrameLevel() or 1) + 1)
		catcher:Show()
		menu:Show()
	end

	catcher:SetScript("OnClick", CloseMenu)
	button:SetScript("OnClick", function()
		if menu:IsShown() then
			CloseMenu()
		else
			OpenMenu()
		end
	end)
	button:SetScript("OnHide", CloseMenu)
	if parent then
		parent:HookScript("OnHide", CloseMenu)
	end

	function button:Refresh()
		RefreshRows()
	end

	RefreshRows()
	return button
end

function addon.CreateCheckbox(parent, name, label, fontOwner)
	local box = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	local text = box.Text or _G[name .. "Text"]
	if text then
		text:SetText(label)
		text:SetJustifyH("LEFT")
		text:SetWidth(300)
		addon.RegisterFontString(fontOwner or parent, text)
	end
	return box
end

function addon.CreateScroll(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(320, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local current = self:GetVerticalScroll()
		local maxScroll = self:GetVerticalScrollRange()
		local nextScroll = current - (delta * 28)
		if nextScroll < 0 then
			nextScroll = 0
		elseif nextScroll > maxScroll then
			nextScroll = maxScroll
		end
		self:SetVerticalScroll(nextScroll)
	end)
	scroll:SetScript("OnSizeChanged", function(self, width)
		if width and width > 0 then
			child:SetWidth(width)
		end
	end)
	scroll.child = child
	return scroll
end

function addon.ApplyFrameLayout(frame, layout)
	if not frame or not layout then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint(layout.point or "CENTER", UIParent, layout.relativePoint or "CENTER", layout.x or 0, layout.y or 0)
	frame:SetScale(layout.scale or 1)
	addon.ApplyFontSize(frame, layout.fontSize or 12)
end
