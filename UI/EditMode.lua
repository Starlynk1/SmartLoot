local addon = SmartLoot or {}
SmartLoot = addon

local EditMode = {}
addon.EditMode = EditMode

local SNAP_METHODS = {
	"IsToTheLeftOfFrame", "IsToTheRightOfFrame", "IsAboveFrame", "IsBelowFrame",
	"IsVerticallyAlignedWithFrame", "IsHorizontallyAlignedWithFrame",
	"GetScaledSelectionCenter", "GetScaledCenter", "GetScaledSelectionSides",
	"GetLeftOffset", "GetRightOffset", "GetTopOffset", "GetBottomOffset",
	"GetSelectionOffset", "GetCombinedSelectionOffset",
	"GetCombinedCenterOffset", "GetSnapOffsets", "AddSnappedFrame",
	"RemoveSnappedFrame", "BreakSnappedFrames", "SetSnappedToFrame",
	"ClearFrameSnap", "SnapToFrame", "IsFrameAnchoredToMe",
	"GetFrameMagneticEligibility", "HasValidSelectionRect",
}

local function CopyEntry(entry)
	return {
		point = entry.point,
		relativePoint = entry.relativePoint,
		x = entry.x,
		y = entry.y,
		scale = entry.scale,
		fontSize = entry.fontSize,
	}
end

local function Near(left, right)
	return math.abs((left or 0) - (right or 0)) < 0.05
end

local function SameLayout(left, right)
	if not left or not right then
		return false
	end
	return left.point == right.point
		and left.relativePoint == right.relativePoint
		and Near(left.x, right.x)
		and Near(left.y, right.y)
		and Near(left.scale, right.scale)
		and left.fontSize == right.fontSize
end

local function OnNudgeKey(self, key)
	local arrow = key == "UP" or key == "DOWN" or key == "LEFT" or key == "RIGHT"
	local handle = EditMode.selected and EditMode:IsActive() and arrow
	if self.SetPropagateKeyboardInput then
		pcall(self.SetPropagateKeyboardInput, self, not handle)
	end
	if handle then
		EditMode:Nudge(key)
	end
end

function EditMode:IsActive()
	return self.active and true or false
end

function EditMode:Frame()
	return addon.Decision and addon.Decision.frame
end

function EditMode:GetActiveLayoutIndex()
	local ok, info = pcall(function()
		if C_EditMode and C_EditMode.GetLayouts then
			return C_EditMode.GetLayouts()
		end
	end)
	local index = ok and info and tonumber(info.activeLayout)
	if index and index > 0 then
		return index
	end
	return 1
end

function EditMode:EnsureLayouts()
	if not addon.db then
		return nil
	end
	if type(addon.db.layouts) ~= "table" then
		addon.db.layouts = {}
	end
	return addon.db.layouts
end

function EditMode:Saved(index)
	local layouts = self:EnsureLayouts()
	if not layouts then
		return nil
	end
	index = tonumber(index) or 1
	layouts[index] = layouts[index] or {}
	if not layouts[index].decision then
		if addon.db.decision then
			layouts[index].decision = CopyEntry(addon.db.decision)
		else
			layouts[index].decision = addon.DefaultFrameLayout("decision")
		end
	end
	return layouts[index].decision
end

function EditMode:ApplyWorking()
	if self.working then
		addon.ApplyFrameLayout(self:Frame(), self.working)
	end
end

function EditMode:ApplySaved()
	if not addon.db then
		return
	end
	addon.ApplyFrameLayout(self:Frame(), self:Saved(self:GetActiveLayoutIndex()))
end

function EditMode:Load(index)
	index = index or self:GetActiveLayoutIndex()
	if self.working and self.index and self.index ~= index then
		self:Capture()
	end
	self.index = index
	local saved = self:Saved(self.index)
	if not saved then
		return
	end
	self.working = CopyEntry(saved)
	self:ApplyWorking()
	if self.selected then
		self:ShowPanel()
	end
	self:RefreshRevert()
end

function EditMode:Commit()
	self:Store()
end

function EditMode:Store()
	if not self.working or not addon.db then
		return
	end
	local index = tonumber(self.index) or self:GetActiveLayoutIndex()
	local layouts = self:EnsureLayouts()
	if not layouts then
		return
	end
	layouts[index] = layouts[index] or {}
	local entry = CopyEntry(self.working)
	layouts[index].decision = entry
	addon.db.decision = CopyEntry(entry)
	self:RefreshRevert()
end

function EditMode:Capture()
	local frame = self:Frame()
	if not frame or not self.working then
		return
	end
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local left = frame:GetLeft()
	local top = frame:GetTop()
	local scale = frame:GetScale() or self.working.scale or 1
	local parentHeight = UIParent:GetHeight()
	if left and top and parentHeight and parentHeight > 0 then
		self.working.point = "TOPLEFT"
		self.working.relativePoint = "TOPLEFT"
		self.working.x = left
		self.working.y = -((parentHeight - (top * scale)) / scale)
	else
		self.working.point = point or "CENTER"
		self.working.relativePoint = relativePoint or "CENTER"
		self.working.x = x or 0
		self.working.y = y or 0
	end
	self.working.scale = scale
	self.working.fontSize = frame.smartLootFontSize or self.working.fontSize or 12
	self:Store()
end

function EditMode:AttachSnap(frame)
	if not frame or frame.smartLootSnap then
		return
	end
	frame.snappedFrames = frame.snappedFrames or {}
	frame.smartLootSnap = true
	if EditModeMagnetismManager and EditModeSystemMixin then
		for index = 1, #SNAP_METHODS do
			local name = SNAP_METHODS[index]
			if EditModeSystemMixin[name] then
				frame[name] = EditModeSystemMixin[name]
			end
		end
	end
	function frame:GetScaledSelectionSides()
		local left, bottom, width, height = self:GetRect()
		if not left then
			return 0, 0, 0, 0
		end
		local scale = self:GetScale() or 1
		return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
	end
end

local function HighestFrameLevel(root, ignore)
	local highest = root:GetFrameLevel() or 0
	local children = { root:GetChildren() }
	for index = 1, #children do
		local child = children[index]
		if child ~= ignore then
			local nested = HighestFrameLevel(child, ignore)
			if nested > highest then
				highest = nested
			end
		end
	end
	return highest
end

local HIGHLIGHT_TEXTURE = "Interface\\AddOns\\SmartLoot\\Art\\EditModeHighlighted"
local SELECTED_TEXTURE = "Interface\\AddOns\\SmartLoot\\Art\\EditModeSelected"

function EditMode:EnsureSelection()
	local frame = self:Frame()
	if not frame or frame.Selection then
		return
	end
	local selection = CreateFrame("Frame", nil, frame)
	local function MatchFrameSize()
		local width = frame:GetWidth() or 0
		local height = frame:GetHeight() or 0
		-- Left stays on the frame edge. Top, right, and bottom keep the
		-- original 8px highlight overflow.
		local top, right, bottom = 8, 8, 8
		local highlightWidth = width + right
		local highlightHeight = height + top + bottom
		selection:ClearAllPoints()
		selection:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
		selection:SetSize(highlightWidth, highlightHeight)
		if selection.Background then
			selection.Background:ClearAllPoints()
			selection.Background:SetPoint("TOPLEFT", selection, "TOPLEFT", 0, 0)
			selection.Background:SetSize(highlightWidth, highlightHeight)
		end
	end
	MatchFrameSize()
	frame:HookScript("OnSizeChanged", MatchFrameSize)
	if frame.SetClipsChildren then
		frame:SetClipsChildren(false)
	end
	selection:EnableMouse(true)
	selection:RegisterForDrag("LeftButton")

	local background = selection:CreateTexture(nil, "OVERLAY")
	background:SetTexture(HIGHLIGHT_TEXTURE)
	if background.SetTextureSliceMargins then
		pcall(background.SetTextureSliceMargins, background, 16, 16, 16, 16)
	end
	if background.SetTextureSliceMode then
		pcall(background.SetTextureSliceMode, background, 0)
	end
	background:SetPoint("TOPLEFT", selection, "TOPLEFT", 0, 0)
	background:SetSize(frame:GetWidth() or 0, frame:GetHeight() or 0)
	background:SetAlpha(0.62)
	selection.Background = background
	MatchFrameSize()

	local hint = selection:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	hint:SetPoint("CENTER", selection, "CENTER", 0, 0)
	hint:SetWidth(176)
	hint:SetJustifyH("CENTER")
	hint:SetWordWrap(false)
	local hintFont = select(1, hint:GetFont())
	hint:SetFont(hintFont or "Fonts\\FRIZQT__.TTF", 26, nil)
	hint:SetText(HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT or "Click to Edit")
	hint:SetTextColor(1, 1, 1, 1)
	hint:Hide()
	selection.EditHint = hint

	function selection:RaiseOverFrame()
		self:SetFrameLevel(HighestFrameLevel(frame, self) + 5)
	end

	function selection:ShowHighlighted()
		self.isSelected = false
		self.hovered = false
		self.Background:SetTexture(HIGHLIGHT_TEXTURE)
		self.Background:SetAlpha(0.62)
		self.EditHint:Hide()
		self:Show()
		self:RaiseOverFrame()
	end

	function selection:ShowSelected()
		self.isSelected = true
		self.hovered = false
		self.Background:SetTexture(SELECTED_TEXTURE)
		self.Background:SetAlpha(1)
		self.EditHint:Hide()
		self:Show()
		self:RaiseOverFrame()
	end

	function selection:IsSelected()
		return self.isSelected
	end

	selection:SetScript("OnEnter", function(self)
		if not EditMode:IsActive() or self.isSelected then
			return
		end
		self.hovered = true
		self.Background:SetTexture(HIGHLIGHT_TEXTURE)
		self.Background:SetAlpha(1)
		self.EditHint:Show()
	end)
	selection:SetScript("OnLeave", function(self)
		if not EditMode:IsActive() or self.isSelected then
			return
		end
		self.hovered = false
		self.Background:SetAlpha(0.62)
		self.EditHint:Hide()
	end)
	selection:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and EditMode:IsActive() then
			EditMode:Select()
		end
	end)
	selection:SetScript("OnDragStart", function()
		if EditMode:IsActive() then
			EditMode:BeginDrag()
		end
	end)
	selection:SetScript("OnDragStop", function()
		EditMode:EndDrag()
	end)
	selection:SetScript("OnKeyDown", OnNudgeKey)
	selection:EnableKeyboard(false)
	selection:Hide()
	frame.Selection = selection

	frame:SetScript("OnDragStart", function(self)
		if EditMode:IsActive() then
			EditMode:BeginDrag()
		end
	end)
	frame:SetScript("OnDragStop", function()
		if EditMode:IsActive() then
			EditMode:EndDrag()
		end
	end)
	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and EditMode:IsActive() then
			EditMode:Select()
		end
	end)
	if not frame.smartLootEditHide then
		frame.smartLootEditHide = true
		frame:HookScript("OnHide", function()
			if frame.Selection then
				frame.Selection:Hide()
			end
			if not EditMode:IsActive() or not EditMode:ShouldShowFrame() then
				return
			end
			local state = addon.Engine and addon.Engine.GetState and addon.Engine:GetState()
			if state == "confirming" or state == "deleting" or state == "working" then
				return
			end
			if addon.Decision then
				addon.Decision:SetPreview(true)
			end
		end)
	end
end

function EditMode:UpdateKeyboard()
	local frame = self:Frame()
	local enabled = self.selected and true or false
	if frame then
		frame:EnableKeyboard(enabled)
		if frame.Selection then
			frame.Selection:EnableKeyboard(enabled)
		end
	end
	if self.panel then
		self.panel:EnableKeyboard(enabled)
	end
end

function EditMode:MouseOverUI()
	local frame = self:Frame()
	if frame and frame:IsVisible() and frame:IsMouseOver() then
		return true
	end
	if frame and frame.Selection and frame.Selection:IsShown() and frame.Selection:IsMouseOver() then
		return true
	end
	if self.panel and self.panel:IsShown() and self.panel:IsMouseOver() then
		return true
	end
	return false
end

function EditMode:BeginDrag()
	local frame = self:Frame()
	if not frame or not self.active then
		return
	end
	self:Select()
	self:AttachSnap(frame)
	if frame.BreakSnappedFrames then
		frame:BreakSnappedFrames()
	end
	if frame.ClearFrameSnap then
		frame:ClearFrameSnap()
	end
	frame:StartMoving()
	if frame.GetFrameMagneticEligibility and EditModeManagerFrame and EditModeManagerFrame.SetSnapPreviewFrame then
		EditModeManagerFrame:SetSnapPreviewFrame(frame)
	end
end

function EditMode:EndDrag()
	local frame = self:Frame()
	if not frame then
		return
	end
	if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
		EditModeManagerFrame:ClearSnapPreviewFrame()
	end
	frame:StopMovingOrSizing()
	if frame.GetFrameMagneticEligibility and EditModeMagnetismManager and EditModeManagerFrame and EditModeManagerFrame.IsSnapEnabled and EditModeManagerFrame:IsSnapEnabled() then
		pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, frame)
	end
	if frame.SetDontSavePosition then
		pcall(frame.SetDontSavePosition, frame, true)
	end
	self:Capture()
end

function EditMode:Nudge(key)
	local frame = self:Frame()
	if not frame or not self.selected then
		return
	end
	local amount = IsShiftKeyDown() and 10 or 1
	local dx, dy = 0, 0
	if key == "UP" then
		dy = amount
	elseif key == "DOWN" then
		dy = -amount
	elseif key == "LEFT" then
		dx = -amount
	elseif key == "RIGHT" then
		dx = amount
	else
		return
	end
	if frame.BreakSnappedFrames then
		frame:BreakSnappedFrames()
	end
	if frame.ClearFrameSnap then
		frame:ClearFrameSnap()
	end
	local ok, applied = pcall(function()
		local top = tonumber(frame:GetTop())
		local left = tonumber(frame:GetLeft())
		local scale = tonumber(frame:GetScale()) or 1
		local parentHeight = tonumber(UIParent:GetHeight()) or 0
		if not top or not left then
			return false
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left + dx, -((parentHeight - top * scale) / scale) + dy)
		return true
	end)
	if not ok or not applied then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
		frame:ClearAllPoints()
		frame:SetPoint(point or "CENTER", relativeTo or UIParent, relativePoint or "CENTER", (x or 0) + dx, (y or 0) + dy)
	end
	self:Capture()
end

function EditMode:AnchorPanel()
	local panel = self.panel
	if not panel then
		return
	end
	panel:ClearAllPoints()
	local saved = addon.db and addon.db.editModePanel
	if saved and saved.hasCustomPosition then
		panel:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or saved.point or "CENTER", saved.x or 0, saved.y or 0)
		return
	end
	if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
		panel:SetPoint("TOPRIGHT", EditModeManagerFrame, "TOPLEFT", -12, -8)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
	end
end

function EditMode:SavePanelPosition()
	if not self.panel or not addon.db then
		return
	end
	local point, _, relativePoint, x, y = self.panel:GetPoint(1)
	addon.db.editModePanel = {
		point = point or "CENTER",
		relativePoint = relativePoint or "CENTER",
		x = x or 0,
		y = y or 0,
		hasCustomPosition = true,
	}
end

function EditMode:RefreshRevert()
	if not self.revertButton then
		return
	end
	local saved = self.working and self:Saved(self.index or self:GetActiveLayoutIndex())
	self.revertButton:SetEnabled(saved and not SameLayout(saved, self.working) or false)
end

function EditMode:EnsurePanel()
	if self.panel then
		return
	end
	local panel = CreateFrame("Frame", "SmartLootEditModePanel", UIParent, "BackdropTemplate")
	panel:SetSize(390, 188)
	panel:SetFrameStrata("DIALOG")
	panel:SetFrameLevel(500)
	panel:SetToplevel(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetClampedToScreen(true)
	panel:SetScale(1)
	if panel.SetDontSavePosition then
		pcall(panel.SetDontSavePosition, panel, true)
	end
	local borderOk, border = pcall(CreateFrame, "Frame", nil, panel, "DialogBorderTranslucentTemplate")
	if borderOk and border then
		border:SetAllPoints(panel)
	else
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText("Smart Loot")
	panel.title = title

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT")
	close:SetScript("OnClick", function()
		EditMode:Deselect()
	end)

	local function AddSlider(name, label, y)
		local row = CreateFrame("Frame", nil, panel)
		row:SetSize(350, 32)
		row:SetPoint("TOPLEFT", 20, y)
		local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
		text:SetSize(100, 32)
		text:SetPoint("LEFT")
		text:SetJustifyH("LEFT")
		text:SetText(label)
		local slider = CreateFrame("Slider", name, row, "MinimalSliderWithSteppersTemplate")
		slider:SetSize(200, 32)
		slider:SetPoint("LEFT", text, "RIGHT", 5, 0)
		row.slider = slider
		return row
	end

	self.scaleRow = AddSlider("SmartLootScaleSlider", "Scale", -48)
	self.fontRow = AddSlider("SmartLootFontSlider", "Font Size", -84)
	self.scaleSlider = self.scaleRow.slider
	self.fontSlider = self.fontRow.slider

	local revert = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	revert:SetSize(170, 28)
	revert:SetPoint("BOTTOMLEFT", 20, 16)
	revert:SetText(HUD_EDIT_MODE_REVERT_CHANGES or "Revert Changes")
	revert:SetScript("OnClick", function()
		EditMode:Revert()
	end)
	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(170, 28)
	reset:SetPoint("BOTTOMRIGHT", -20, 16)
	reset:SetText(HUD_EDIT_MODE_RESET_POSITION or "Reset Position")
	reset:SetScript("OnClick", function()
		EditMode:Reset()
	end)

	panel:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		EditMode:SavePanelPosition()
	end)
	panel:SetScript("OnKeyDown", OnNudgeKey)
	panel:EnableKeyboard(false)
	panel:Hide()

	self.panel = panel
	self.revertButton = revert
	local ok = pcall(function()
		self:BindSliders()
	end)
	if not ok then
		self.slidersReady = false
	end
end

function EditMode:BindSliders()
	local label = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
	local event = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event
	if not label or not event then
		return
	end
	self.suppress = true
	self.scaleSlider:Init(1, 0.5, 1.5, 20, {
		[label.Right] = function(value)
			return string.format("%d%%", math.floor((value * 100) + 0.5))
		end,
	})
	self.fontSlider:Init(12, 8, 20, 12, {
		[label.Right] = function(value)
			return tostring(math.floor(value + 0.5))
		end,
	})
	self.suppress = false
	self.scaleSlider:RegisterCallback(event.OnValueChanged, function(_, value)
		EditMode:OnScale(value)
	end)
	self.fontSlider:RegisterCallback(event.OnValueChanged, function(_, value)
		EditMode:OnFont(value)
	end)
	self.slidersReady = true
end

function EditMode:OnScale(value)
	if self.suppress or not self.working or not self.panel or not self.panel:IsShown() then
		return
	end
	local frame = self:Frame()
	if not frame then
		return
	end
	self.working.scale = value
	frame:SetScale(value)
	self:Store()
end

function EditMode:OnFont(value)
	if self.suppress or not self.working or not self.panel or not self.panel:IsShown() then
		return
	end
	local frame = self:Frame()
	if not frame then
		return
	end
	local size = math.floor(value + 0.5)
	self.working.fontSize = size
	addon.ApplyFontSize(frame, size)
	self:Store()
end

function EditMode:ShowPanel()
	self:EnsurePanel()
	if not self.working then
		return
	end
	self:AnchorPanel()
	if self.slidersReady then
		self.suppress = true
		self.scaleSlider:Init(self.working.scale or 1, 0.5, 1.5, 20, self.scaleSlider.formatters)
		self.fontSlider:Init(self.working.fontSize or 12, 8, 20, 12, self.fontSlider.formatters)
		self.suppress = false
	end
	self.panel:Show()
	self:RefreshRevert()
end

function EditMode:Select()
	if not self.active then
		return
	end
	local frame = self:Frame()
	if not frame then
		return
	end
	local already = self.selected
	self.selected = true
	if frame.Selection and frame.Selection.ShowSelected then
		frame.Selection:ShowSelected()
	end
	if not already then
		if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
			pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
		end
		self:ShowPanel()
	end
	self:UpdateKeyboard()
end

function EditMode:HidePanel()
	self.suppress = true
	if self.panel then
		self.panel:Hide()
	end
	self.suppress = false
end

function EditMode:Deselect()
	self.selected = false
	local frame = self:Frame()
	if frame and frame.Selection and self.active and frame.Selection.ShowHighlighted then
		frame.Selection:ShowHighlighted()
	elseif frame and frame.Selection then
		frame.Selection:Hide()
	end
	self:HidePanel()
	self:UpdateKeyboard()
end

function EditMode:Revert()
	local saved = self:Saved(self.index or self:GetActiveLayoutIndex())
	if not saved then
		return
	end
	self.working = CopyEntry(self.baseline or saved)
	self:ApplyWorking()
	self:Store()
	if self.selected then
		self:ShowPanel()
	end
end

function EditMode:Reset()
	if not self.working then
		return
	end
	self.working = addon.DefaultFrameLayout("decision")
	self:ApplyWorking()
	self:Store()
	if self.selected then
		self:ShowPanel()
	end
end

function EditMode:ShouldShowFrame()
	return not addon.db or addon.db.editModeShowFrame ~= false
end

function EditMode:RegisterManagerTab(tab)
	local registry = _G.EditModeAddonSideTabs
	if type(registry) ~= "table" then
		registry = {}
		_G.EditModeAddonSideTabs = registry
	end
	for index = 1, #registry do
		if registry[index] and registry[index].frame == tab then
			return
		end
	end
	registry[#registry + 1] = {
		addon = "SmartLoot",
		frame = tab,
	}
end

function EditMode:IsManagerSideTab(frame, parent)
	if not frame or frame == self.managerTab or not frame.GetPoint then
		return false
	end
	if frame.isEditModeSideTab then
		return true
	end
	local points = frame.GetNumPoints and frame:GetNumPoints() or 1
	for index = 1, points do
		local point, relative, relativePoint = frame:GetPoint(index)
		if relative == parent and (relativePoint == "TOPRIGHT" or relativePoint == "RIGHT" or relativePoint == "BOTTOMRIGHT") then
			if point == "TOPLEFT" or point == "LEFT" or point == "BOTTOMLEFT" then
				return true
			end
		end
	end
	return false
end

function EditMode:FindLowestManagerSideTab(parent, ignore)
	local lowest
	local lowestBottom
	local function Consider(frame)
		if not frame or frame == ignore or not frame.IsShown or not frame:IsShown() then
			return
		end
		if not self:IsManagerSideTab(frame, parent) then
			return
		end
		local bottom = frame.GetBottom and frame:GetBottom()
		if not bottom then
			return
		end
		if not lowestBottom or bottom < lowestBottom then
			lowest = frame
			lowestBottom = bottom
		end
	end
	local registry = _G.EditModeAddonSideTabs
	if type(registry) == "table" then
		for index = 1, #registry do
			Consider(registry[index] and registry[index].frame)
		end
	end
	if parent.GetChildren then
		local children = { parent:GetChildren() }
		for index = 1, #children do
			Consider(children[index])
		end
	end
	return lowest
end

function EditMode:PlaceManagerTab()
	local tab = self.managerTab
	local parent = EditModeManagerFrame
	if not tab or not parent then
		return
	end
	tab:ClearAllPoints()
	local previous = self:FindLowestManagerSideTab(parent, tab)
	if previous then
		tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
	else
		tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -36)
	end
end

function EditMode:ApplyFrameVisibility()
	if not self.active then
		return
	end
	if self:ShouldShowFrame() then
		if addon.Decision then
			addon.Decision:SetPreview(true)
		end
		local frame = self:Frame()
		if self.selected then
			self:Select()
		elseif frame and frame.Selection and frame.Selection.ShowHighlighted then
			frame.Selection:ShowHighlighted()
		end
		return
	end
	self.selected = false
	self:HidePanel()
	self:UpdateKeyboard()
	local frame = self:Frame()
	if frame and frame.Selection then
		frame.Selection:Hide()
	end
	if addon.Decision then
		addon.Decision:SetPreview(false)
	end
end

function EditMode:SetShowFrame(show)
	show = show and true or false
	if addon.db then
		addon.db.editModeShowFrame = show
	end
	if self.showCheck then
		self.showCheck:SetChecked(show)
	end
	self:ApplyFrameVisibility()
end

function EditMode:EnsureManagerTab()
	if self.managerTab or not EditModeManagerFrame then
		return
	end
	local parent = EditModeManagerFrame
	local tab = CreateFrame("Frame", "SmartLootEditModeManagerTab", parent)
	tab:SetSize(132, 32)
	tab.isEditModeSideTab = true
	tab.editModeAddonTab = "SmartLoot"
	tab:SetFrameStrata(parent.GetFrameStrata and parent:GetFrameStrata() or "DIALOG")
	if tab.SetFrameLevel and parent.GetFrameLevel then
		tab:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	end
	local notch = tab:CreateTexture(nil, "BACKGROUND")
	notch:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
	notch:SetSize(64, 64)
	notch:SetPoint("TOPLEFT", -3, 11)
	local plate = CreateFrame("Frame", nil, tab, BackdropTemplateMixin and "BackdropTemplate" or nil)
	plate:SetPoint("TOPLEFT", 26, 0)
	plate:SetPoint("BOTTOMRIGHT", 0, 0)
	if plate.SetBackdrop then
		plate:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
	end
	local check = CreateFrame("CheckButton", "SmartLootEditModeShowCheck", plate, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("LEFT", 2, 0)
	check:SetHitRectInsets(0, -86, 0, 0)
	local checkText = check.Text or _G["SmartLootEditModeShowCheckText"]
	if checkText then
		checkText:SetText("Smart Loot")
		checkText:SetJustifyH("LEFT")
		checkText:SetWidth(90)
		if addon.RegisterFontString then
			addon.RegisterFontString(tab, checkText)
		end
	end
	check:SetChecked(self:ShouldShowFrame())
	check:SetScript("OnClick", function(box)
		EditMode:SetShowFrame(box:GetChecked() and true or false)
	end)
	local function ShowTip(owner)
		if GameTooltip then
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			GameTooltip:SetText("Smart Loot")
			GameTooltip:AddLine("Show the loot frame while Edit Mode is open.", 1, 1, 1, true)
			GameTooltip:Show()
		end
	end
	check:SetScript("OnEnter", function(self)
		ShowTip(self)
	end)
	check:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	self.managerTab = tab
	self.showCheck = check
	self:RegisterManagerTab(tab)
	if not parent.smartLootTabHooked and parent.HookScript then
		parent.smartLootTabHooked = true
		parent:HookScript("OnShow", function()
			EditMode:PlaceManagerTab()
		end)
	end
	self:PlaceManagerTab()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			EditMode:PlaceManagerTab()
		end)
	end
end

function EditMode:Enter()
	if not addon.db then
		return
	end
	self.active = true
	self:Load(self:GetActiveLayoutIndex())
	if not self.working then
		self.working = addon.DefaultFrameLayout("decision")
	end
	self.baseline = CopyEntry(self.working)
	self:EnsureSelection()
	self:EnsureManagerTab()
	self:PlaceManagerTab()
	local frame = self:Frame()
	if frame then
		self:AttachSnap(frame)
		frame:SetScript("OnKeyDown", OnNudgeKey)
	end
	self:Deselect()
	self:ApplyFrameVisibility()
end

function EditMode:Exit()
	if self.working then
		self:Capture()
	end
	self.active = false
	self.selected = false
	self:HidePanel()
	local frame = self:Frame()
	if frame and frame.Selection then
		frame.Selection:Hide()
	end
	self.working = nil
	self.baseline = nil
	self:UpdateKeyboard()
	self:ApplySaved()
	if addon.Decision then
		addon.Decision:SetPreview(false)
	end
end

function EditMode:TryHook()
	if self.hooked or not EventRegistry or not EditModeManagerFrame or not hooksecurefunc then
		return
	end
	self.hooked = true
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		EditMode:Enter()
	end, addon)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		EditMode:Exit()
	end, addon)
	local saveLayoutChanges = EditModeManagerFrame.SaveLayoutChanges
	EditModeManagerFrame.SaveLayoutChanges = function(manager, ...)
		EditMode.saving = true
		local ok, result = pcall(saveLayoutChanges, manager, ...)
		EditMode.saving = false
		if EditMode.working then
			EditMode:Commit()
		end
		if not ok then
			error(result)
		end
		return result
	end
	hooksecurefunc(EditModeManagerFrame, "SelectLayout", function(_, layoutIndex)
		if EditMode:IsActive() then
			EditMode:Load(type(layoutIndex) == "number" and layoutIndex or nil)
		end
	end)
	if EditModeManagerFrame.SelectSystem then
		hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
			if EditMode.selected then
				EditMode:Deselect()
			end
		end)
	end
	if EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
		self:Enter()
	end
end

function EditMode:Initialize()
	-- Classic Era has no Edit Mode manager; keep decision-frame drag via options only.
	if not (addon.HasEditMode and addon.HasEditMode()) then
		return
	end
	self:TryHook()
	if self.watcher then
		return
	end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	watcher:RegisterEvent("PLAYER_LOGIN")
	pcall(watcher.RegisterEvent, watcher, "EDIT_MODE_LAYOUTS_UPDATED")
	watcher:SetScript("OnEvent", function(_, event)
		if event == "GLOBAL_MOUSE_DOWN" then
			if EditMode:IsActive() and EditMode.selected and not EditMode:MouseOverUI() then
				EditMode:Deselect()
			end
			return
		end
		if not EditMode:IsActive() then
			EditMode:ApplySaved()
		end
	end)
	self.watcher = watcher
end
