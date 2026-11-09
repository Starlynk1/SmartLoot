local addon = SmartLoot or {}
SmartLoot = addon

local Engine = {}
addon.Engine = Engine

local EVENTS = {
	"LOOT_OPENED",
	"LOOT_CLOSED",
	"LOOT_SLOT_CLEARED",
	"LOOT_BIND_CONFIRM",
	"BAG_UPDATE_DELAYED",
	"QUEST_DETAIL",
	"QUEST_PROGRESS",
	"QUEST_COMPLETE",
	"QUEST_ITEM_UPDATE",
	"UI_ERROR_MESSAGE",
}

function Engine:Initialize()
	if self.frame then
		return
	end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		self:OnEvent(event, ...)
	end)
	self.frame = frame
	self.state = "idle"
	self.token = 0
	self:InstallAutoDestroyHooks()
end

function Engine:Enable()
	self:Initialize()
	if self.enabled then
		return
	end
	self.enabled = true
	for _, event in ipairs(EVENTS) do
		self.frame:RegisterEvent(event)
	end
	if addon.Inventory and addon.Inventory.RefreshCache then
		addon.Inventory.RefreshCache()
	end
	if UIErrorsFrame and UIErrorsFrame.AddMessage and hooksecurefunc and not self.errorHooked then
		self.errorHooked = true
		hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, text)
			if Engine:IsInventoryFull(nil, text) then
				Engine:OnInventoryFull()
			end
		end)
	end
end

function Engine:Disable()
	self.enabled = false
	if self.frame then
		for _, event in ipairs(EVENTS) do
			self.frame:UnregisterEvent(event)
		end
	end
	self:Abort(nil)
end

function Engine:GetState()
	return self.state or "idle"
end

function Engine:Disarm()
	self.token = (self.token or 0) + 1
end

function Engine:ArmWatchdog()
	self:Disarm()
	local token = self.token
	if not C_Timer then
		return
	end
	C_Timer.After(1.5, function()
		if self.token ~= token then
			return
		end
		if self.state == "deleting" then
			self:Abort("Looting stopped because the bag did not update.")
			return
		end
		if self.state == "looting" then
			self:OnLootStuck()
		end
	end)
end

function Engine:ForDialog(which, visitor)
	local count = STATICPOPUP_NUMDIALOGS or 4
	for index = 1, count do
		local dialog = _G["StaticPopup" .. index]
		if dialog and dialog:IsShown() and dialog.which == which then
			visitor(dialog)
		end
	end
end

function Engine:DialogShown(which)
	local shown = false
	self:ForDialog(which, function()
		shown = true
	end)
	return shown
end

function Engine:AcceptDialog(which)
	local info = StaticPopupDialogs and StaticPopupDialogs[which]
	if not info or not info.OnAccept then
		return
	end
	self:ForDialog(which, function(dialog)
		info.OnAccept(dialog, dialog.data)
		dialog:Hide()
	end)
end

function Engine:HideDialog(which)
	if StaticPopup_Hide then
		StaticPopup_Hide(which)
	end
end

function Engine:OnEvent(event, ...)
	if not self.enabled then
		return
	end
	if event == "LOOT_OPENED" then
		self:OnLootOpened(...)
	elseif event == "LOOT_CLOSED" then
		self:OnLootClosed()
	elseif event == "LOOT_SLOT_CLEARED" then
		self:OnSlotCleared(...)
	elseif event == "LOOT_BIND_CONFIRM" then
		self:OnBindConfirm(...)
	elseif event == "BAG_UPDATE_DELAYED" then
		self:OnBagUpdate()
	elseif event == "QUEST_DETAIL" then
		self:OnQuestDetail(...)
	elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "QUEST_ITEM_UPDATE" then
		self:QueueQuestDialog()
	elseif event == "UI_ERROR_MESSAGE" then
		self:OnUIError(...)
	end
end

function Engine:LootHasItems()
	if not GetNumLootItems or not GetLootSlotInfo then
		return false
	end
	local count = GetNumLootItems() or 0
	for slot = 1, count do
		local _, name, _, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
		if isCoin or (currencyID and currencyID > 0) or (name and name ~= "") then
			return true
		end
	end
	return false
end

function Engine:CloseLootWindow()
	if not CloseLoot then
		return
	end
	local shown = LootFrame and LootFrame.IsShown and LootFrame:IsShown()
	local count = GetNumLootItems and GetNumLootItems() or 0
	if not shown and count == 0 then
		return
	end
	CloseLoot()
end

function Engine:CloseLootIfEmpty()
	if not self:LootHasItems() then
		self:CloseLootWindow()
	end
end

function Engine:IsClassicEraClient()
	return addon.IsClassicEra and addon.IsClassicEra()
end

function Engine:FreezeBagScan()
	self.bagScanFrozen = true
	if addon.Inventory then
		addon.Inventory.scanLocked = true
	end
end

function Engine:ThawBagScan()
	self.bagScanFrozen = nil
	if addon.Inventory then
		addon.Inventory.scanLocked = nil
	end
end

function Engine:CloseLootForDelete()
	if not self:IsClassicEraClient() then
		return
	end
	self.ignoreLootClosed = true
	self:CloseLootWindow()
end

-- Classic Era crashes if DeleteCursorItem runs against an open loot session
-- or if LootSlot follows that delete. Close loot, delete, then stop. The
-- player clicks the corpse again to loot.
function Engine:FinishEraDelete()
	self.ignoreLootClosed = nil
	self:ThawBagScan()
	self.autoDestroying = nil
	self:ClearDeletion()
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.stepIndex = nil
	self.questGrant = nil
	self.skippedOpen = nil
	if addon.Decision then
		addon.Decision:Hide()
	end
	if not self.clickLive then
		addon.Print("Destroyed junk. Click the corpse to loot.")
	end
end

function Engine:Rescan()
	self.scanToken = (self.scanToken or 0) + 1
	local token = self.scanToken
	self.state = "loading"
	self.plan = nil
	self.phase = nil
	addon.Scanner.Scan(function(loot)
		if self.scanToken ~= token or self.state ~= "loading" then
			return
		end
		if #loot == 0 then
			self.state = "idle"
			self.phase = nil
			if addon.Decision then
				addon.Decision:Hide()
			end
			self:CloseLootIfEmpty()
			self:Settle()
			return
		end
		addon.Inventory.Scan(function(bagItems, freeSlots)
			if self.scanToken ~= token or self.state ~= "loading" then
				return
			end
			local slots = freeSlots
			if self.forceSacrifice then
				slots = {}
			end
			self.forceSacrifice = nil
			local plan = addon.BuildPlan(loot, bagItems, slots, self:PlanOptions())
			self:ApplyPlan(plan)
		end)
	end)
end

function Engine:RestoreAutoLoot()
	if self.savedAutoLoot == nil or not SetCVar then
		self.savedAutoLoot = nil
		return
	end
	SetCVar("autoLootDefault", self.savedAutoLoot)
	self.savedAutoLoot = nil
end

function Engine:LootContainerNow()
	if not GetNumLootItems or not LootSlot then
		return false
	end
	local count = GetNumLootItems()
	if type(count) ~= "number" or count < 1 then
		return false
	end
	for slot = count, 1, -1 do
		LootSlot(slot)
	end
	return true
end

function Engine:OnLootOpened(autoLoot)
	if not addon.db or not addon.db.enabled then
		return
	end
	if self.openingItem then
		self:LootContainerNow()
		return
	end
	if self.state ~= "idle" then
		return
	end
	self.containerLoot = nil
	self.skipImmediate = autoLoot and true or false
	self:Rescan()
end

local function SameError(message, expected)
	if message == nil or expected == nil then
		return false
	end
	local ok, same = pcall(function()
		return message == expected
	end)
	return ok and same or false
end

function Engine:IsInventoryFull(errorType, message)
	if type(errorType) == "number" and GetGameMessageInfo then
		local ok, name = pcall(GetGameMessageInfo, errorType)
		if ok and type(name) == "string" and name:find("INV_FULL", 1, true) then
			return true
		end
	end
	if LE_GAME_ERR_INV_FULL then
		local ok, same = pcall(function()
			return errorType == LE_GAME_ERR_INV_FULL
		end)
		if ok and same then
			return true
		end
	end
	local gameError = Enum and Enum.GameError and Enum.GameError.InventoryFull
	if gameError then
		local ok, same = pcall(function()
			return errorType == gameError
		end)
		if ok and same then
			return true
		end
	end
	if SameError(message, ERR_INV_FULL) then
		return true
	end
	return type(message) == "string" and message:find("Inventory is full", 1, true) ~= nil
end

function Engine:OnUIError(first, second)
	if self:IsInventoryFull(first, second) or self:IsInventoryFull(second, first) then
		self:OnInventoryFull()
	end
end

function Engine:MerchantOpen()
	return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() and true or false
end

function Engine:OnInventoryFull()
	if not addon.db or not addon.db.enabled then
		return
	end
	-- Never destroy bag items to make space for a vendor purchase.
	if self:MerchantOpen() then
		return
	end
	if self.openingItem then
		local now = GetTime and GetTime() or 0
		local item = self.openingItem
		self.openingItem = nil
		self.openToken = (self.openToken or 0) + 1
		if self.fullAt and (now - self.fullAt) < 0.5 then
			return
		end
		self.fullAt = now
		self:OfferOpenProcess(item)
		return
	end
	-- RestedXP: INVENTORY_FULL while the loot window is open arms junk and
	-- shows the pass-through click frame. Do this even during an active plan.
	if addon.db.autoDestroy then
		self:FindJunk()
		self:ShowClickFrameIfReady()
		if self.state == "confirming" or self.state == "deleting" or self.state == "looting" or self.state == "working" then
			return
		end
	elseif self.state == "confirming" or self.state == "deleting" or self.state == "looting" or self.state == "working" then
		return
	end
	local now = GetTime and GetTime() or 0
	if self.fullAt and (now - self.fullAt) < 0.5 then
		return
	end
	self.fullAt = now
	if self:LootHasItems() then
		self.skipImmediate = true
		self.forceSacrifice = true
		self.questGrant = nil
		self:Rescan()
		return
	end
	local entries = self:QuestGrantEntries()
	if #entries == 0 then
		entries[1] = self:FallbackQuestEntry()
	end
	self.forceSacrifice = true
	self:OfferQuestGrants(entries)
end

function Engine:QuestGrantEntries()
	local list = {}
	local function Add(kind, index)
		if not GetQuestItemInfo then
			return
		end
		local name, texture, numItems, quality, _, itemID = GetQuestItemInfo(kind, index)
		local link = GetQuestItemLink and GetQuestItemLink(kind, index) or nil
		if (not itemID or itemID == 0) and type(link) == "string" then
			itemID = tonumber(link:match("item:(%d+)"))
		end
		if not itemID or itemID == 0 then
			return
		end
		list[#list + 1] = {
			lootType = "item",
			itemID = itemID,
			name = name,
			texture = texture,
			quality = quality,
			count = numItems or 1,
			link = link,
			neededForQuest = true,
			isQuest = true,
			needsItemData = true,
			questGrant = true,
		}
	end
	local rewards = GetNumQuestRewards and GetNumQuestRewards() or 0
	for index = 1, rewards do
		Add("reward", index)
	end
	local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
	if choices > 0 then
		local index = 1
		if QuestInfoFrame and QuestInfoFrame.itemChoice and QuestInfoFrame.itemChoice > 0 then
			index = QuestInfoFrame.itemChoice
		end
		if index > choices then
			index = 1
		end
		Add("choice", index)
	end
	return list
end

function Engine:FallbackQuestEntry()
	local title = GetTitleText and GetTitleText() or nil
	return {
		lootType = "item",
		name = title or "Quest item",
		count = 1,
		maxStack = 1,
		neededForQuest = true,
		isQuest = true,
		questGrant = true,
		texture = "Interface\\Icons\\INV_Misc_QuestionMark",
	}
end

function Engine:PlanOptions(extra)
	local options = {
		protectReagents = addon.db and addon.db.protectCraftingReagents and true or false,
		keepSoulShards = addon.db and addon.db.keepSoulShards or 0,
		keepConjured = addon.db and addon.db.keepConjured or 0,
		keepAmmo = addon.db and addon.db.keepAmmo or 0,
		skipSlots = self.skippedOpen,
	}
	if extra then
		for key, value in pairs(extra) do
			options[key] = value
		end
	end
	return options
end

function Engine:OfferQuestGrants(entries)
	if not entries or #entries == 0 then
		return
	end
	if self.state == "confirming" or self.state == "deleting" or self.state == "looting" or self.state == "working" then
		return
	end
	self.scanToken = (self.scanToken or 0) + 1
	local token = self.scanToken
	self.state = "loading"
	self.questGrant = true
	self.questEntries = entries
	local force = self.forceSacrifice
	self.forceSacrifice = nil
	addon.ResolveItems(entries, function(loot)
		if self.scanToken ~= token or self.state ~= "loading" then
			return
		end
		addon.Inventory.Scan(function(bagItems, freeSlots)
			if self.scanToken ~= token or self.state ~= "loading" then
				return
			end
			local slots = freeSlots
			if force then
				slots = {}
			end
			local plan = addon.BuildPlan(loot, bagItems, slots, self:PlanOptions({ preferOpenable = true }))
			if not force and #(plan.immediate or {}) > 0 and #(plan.takes or {}) == 0 then
				self.state = "idle"
				self.plan = nil
				self.questGrant = nil
				return
			end
			plan.directGrant = true
			self:ApplyPlan(plan)
		end)
	end)
end

function Engine:OfferQuestItem(itemID)
	if not itemID or itemID == 0 then
		return
	end
	self:OfferQuestGrants({
		{
			lootType = "item",
			itemID = itemID,
			count = 1,
			neededForQuest = true,
			isQuest = true,
			needsItemData = true,
			questGrant = true,
		},
	})
end

function Engine:QueueQuestDialog()
	if not addon.db or not addon.db.enabled then
		return
	end
	if not C_Timer then
		self:ConsiderQuestDialog()
		return
	end
	C_Timer.After(0, function()
		self:ConsiderQuestDialog()
	end)
end

function Engine:ConsiderQuestDialog()
	if self.state ~= "idle" then
		return
	end
	if not QuestFrame or not QuestFrame.IsShown or not QuestFrame:IsShown() then
		return
	end
	local entries = self:QuestGrantEntries()
	if #entries == 0 then
		return
	end
	self:OfferQuestGrants(entries)
end

function Engine:OnQuestDetail(questStartItemID)
	if not addon.db or not addon.db.enabled then
		return
	end
	if type(questStartItemID) == "number" and questStartItemID ~= 0 then
		self:OfferQuestItem(questStartItemID)
		return
	end
	self:QueueQuestDialog()
end

function Engine:QuestRewardChoice()
	local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
	if type(choices) ~= "number" or choices < 1 then
		return 0, true
	end
	local choice = 0
	if QuestInfoFrame and type(QuestInfoFrame.itemChoice) == "number" then
		choice = QuestInfoFrame.itemChoice
	end
	if choice < 1 or choice > choices then
		return nil, false
	end
	return choice, true
end

function Engine:FinishQuestGrant(item)
	local finished = false
	if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then
		if QuestFrameRewardPanel and QuestFrameRewardPanel.IsShown and QuestFrameRewardPanel:IsShown() and GetQuestReward then
			local choice, ok = self:QuestRewardChoice()
			if not ok then
				addon.Print("Choose a quest reward, then complete the quest.")
			else
				pcall(GetQuestReward, choice)
				finished = true
			end
		elseif QuestFrameProgressPanel and QuestFrameProgressPanel.IsShown and QuestFrameProgressPanel:IsShown() and CompleteQuest then
			pcall(CompleteQuest)
			finished = true
		elseif AcceptQuest then
			pcall(AcceptQuest)
			finished = true
		end
	end
	if not finished then
		local name = item and item.name or "the quest item"
		addon.Print("Bag space is free. Click the quest target again to take " .. name .. ".")
	end
end

function Engine:ApplyPlan(plan)
	if self.state ~= "loading" then
		return
	end
	self.plan = plan
	self.deleteIndex = 1
	self.stepIndex = 1
	self.phase = nil
	if self.skipImmediate then
		self.skipImmediate = nil
		if #(plan.takes or {}) == 0 and #(plan.leftBehind or {}) == 0 then
			self.state = "idle"
			self.plan = nil
			self:Settle()
			return
		end
		plan.immediate = {}
	end
	if plan.immediate and #plan.immediate > 0 then
		if addon.Decision and addon.Decision.frame and addon.Decision.frame:IsShown() then
			addon.Decision:Hide()
		end
		self.phase = "immediate"
		self:BeginLoot()
		return
	end
	self:OfferDecision()
end

function Engine:OfferDecision()
	local plan = self.plan
	local takes = plan and #(plan.takes or {}) or 0
	local left = plan and #(plan.leftBehind or {}) or 0
	local sacrifices = plan and #(plan.sacrifices or {}) or 0
	if not plan or (takes == 0 and left == 0 and sacrifices == 0 and not (plan.openGrant and plan.openItem)) then
		self.state = "idle"
		self.plan = nil
		self.phase = nil
		self.stepIndex = nil
		if addon.Decision then
			addon.Decision:Hide()
		end
		self.autoDestroying = nil
		self:ClearDeletion()
		self:CloseLootIfEmpty()
		self:Settle()
		return
	end
	self.phase = nil
	self.state = "confirming"
	self.stepIndex = self.stepIndex or 1
	self.deleteIndex = 1
	if self:TryAutoDestroyCurrent() then
		return
	end
	addon.Decision:ShowPlan(plan)
	self:ArmLeftoverClose()
end

function Engine:LeftoverOnly()
	local plan = self.plan
	if not plan or plan.openGrant or plan.directGrant then
		return false
	end
	if #(plan.leftBehind or {}) == 0 then
		return false
	end
	if self:CurrentSacrifice() then
		return false
	end
	local step = self:CurrentStep()
	if step and step.take then
		return false
	end
	return true
end

function Engine:CancelLeftoverClose()
	self.leftoverCloseToken = (self.leftoverCloseToken or 0) + 1
end

function Engine:ArmLeftoverClose()
	self:CancelLeftoverClose()
	if not self:LeftoverOnly() then
		return
	end
	local seconds = tonumber(addon.db and addon.db.autoCloseLeftover) or 0
	if seconds <= 0 or not C_Timer then
		return
	end
	local token = self.leftoverCloseToken
	C_Timer.After(seconds, function()
		if Engine.leftoverCloseToken ~= token then
			return
		end
		if not Engine:LeftoverOnly() then
			return
		end
		Engine:Cancel()
	end)
end

function Engine:ShowLeftovers()
	local plan = self.plan
	if not plan or not addon.Decision then
		return false
	end
	if #(plan.leftBehind or {}) == 0 then
		return false
	end
	self.state = "confirming"
	self.autoDestroying = nil
	self:ClearDeletion()
	self.stepIndex = #(plan.steps or {}) + 1
	addon.Decision:ShowPlan(plan)
	self:ArmLeftoverClose()
	return true
end

-- One destroy→loot pair at a time when BuildPlan emitted steps.
function Engine:CurrentStep()
	local steps = self.plan and self.plan.steps
	if not steps or #steps == 0 then
		return nil
	end
	return steps[self.stepIndex or 1]
end

function Engine:CurrentSacrifice()
	local step = self:CurrentStep()
	local index = self.deleteIndex or 1
	if step then
		return step.sacrifices[index]
	end
	return self.plan and self.plan.sacrifices and self.plan.sacrifices[index]
end

function Engine:RemainingDestroyValue()
	local index = self.deleteIndex or 1
	local total = 0
	local step = self:CurrentStep()
	local list = step and step.sacrifices
	if not list then
		list = self.plan and self.plan.sacrifices
	end
	if not list then
		return 0
	end
	for i = index, #list do
		total = total + (list[i].value or 0)
	end
	return total
end

function Engine:AutoLootValue()
	local step = self:CurrentStep()
	if step and step.take then
		return step.take.value or 0
	end
	local takes = self.plan and self.plan.takes
	if takes and takes[1] then
		return takes[1].value or 0
	end
	return 0
end

function Engine:CanAutoDestroy(sacrifice)
	if not addon.db or not addon.db.autoDestroy then
		return false
	end
	if not sacrifice or sacrifice.openInstead then
		return false
	end
	local maxQuality = addon.db.autoDestroyMaxQuality or 0
	if (sacrifice.quality or 0) > maxQuality then
		return false
	end
	-- Quality never overrides coin: loot must still be worth more than the junk.
	return self:AutoLootValue() > self:RemainingDestroyValue()
end

function Engine:ShowConfirm()
	self.state = "confirming"
	if addon.Decision then
		addon.Decision:ShowPlan(self.plan)
	end
end

function Engine:LootNameForAuto()
	local step = self:CurrentStep()
	if step and step.take and step.take.name then
		return step.take.name
	end
	local takes = self.plan and self.plan.takes
	if takes and takes[1] and takes[1].name then
		return takes[1].name
	end
	return "loot"
end

function Engine:ClearDeletion()
	self.deletion = { bag = nil, slot = nil, item = nil }
	if self.clickFrame then
		self.clickFrame:Hide()
	end
end

function Engine:ShowClickFrameIfReady()
	local clickFrame = self.clickFrame
	if not clickFrame then
		return
	end
	if self.deletion and self.deletion.bag ~= nil and LootFrame and LootFrame.IsShown and LootFrame:IsShown() then
		clickFrame:Show()
	else
		clickFrame:Hide()
	end
end

-- RestedXP InventoryManager.FindJunk: arm bag/slot only. Never delete here.
function Engine:FindJunk()
	self.deletion = { bag = nil, slot = nil, item = nil }
	if not addon.db or not addon.db.autoDestroy or not self.autoDestroying then
		if self.clickFrame then
			self.clickFrame:Hide()
		end
		return
	end
	local item = self:CurrentSacrifice()
	if not self:CanAutoDestroy(item) or item.bag == nil or not item.slot then
		if self.clickFrame then
			self.clickFrame:Hide()
		end
		return
	end
	self.deletion.bag = item.bag
	self.deletion.slot = item.slot
	self.deletion.item = item
end

function Engine:WantedLootSlots()
	local seen = {}
	local slots = {}
	local function Add(item)
		local slot = item and item.slot
		if not slot or seen[slot] then
			return
		end
		seen[slot] = true
		slots[#slots + 1] = slot
	end
	if not self.plan then
		return slots
	end
	for _, item in ipairs(self.plan.immediate or {}) do
		Add(item)
	end
	for _, item in ipairs(self.plan.takes or {}) do
		Add(item)
	end
	for _, step in ipairs(self.plan.steps or {}) do
		Add(step.take)
	end
	return slots
end

function Engine:SlotStillHasLoot(slot)
	if not slot or not GetLootSlotInfo then
		return false
	end
	local _, name, _, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
	return isCoin or (currencyID and currencyID > 0) or (name and name ~= "")
end

function Engine:WantedStillOnCorpse()
	for _, slot in ipairs(self:WantedLootSlots()) do
		if self:SlotStillHasLoot(slot) then
			return true
		end
	end
	return false
end

-- This addon turns autoLootDefault off, so after a hardware delete we loot the
-- planned takes the same way RestedXP autoloots remaining slots on clickFrame.
function Engine:LootRemainingWanted()
	if not LootSlot or not GetNumLootItems then
		return
	end
	local wanted = {}
	for _, slot in ipairs(self:WantedLootSlots()) do
		wanted[slot] = true
	end
	local count = GetNumLootItems() or 0
	for slot = count, 1, -1 do
		if wanted[slot] then
			LootSlot(slot)
		end
	end
	if C_Timer then
		C_Timer.After(0, function()
			Engine:AfterAutoLoot()
		end)
	else
		self:AfterAutoLoot()
	end
end

function Engine:AfterAutoLoot()
	if not self.plan or not self.autoDestroying then
		return
	end
	if self:WantedStillOnCorpse() then
		self:FindJunk()
		self:ShowClickFrameIfReady()
		if #(self.plan.leftBehind or {}) > 0 and addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		return
	end
	self.autoDestroying = nil
	self:ClearDeletion()
	if self:ShowLeftovers() then
		return
	end
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.stepIndex = nil
	if addon.Decision then
		addon.Decision:Hide()
	end
	self:CloseLootIfEmpty()
	self:Settle()
end

function Engine:AdvanceDeleteCursor()
	self.deleteIndex = (self.deleteIndex or 1) + 1
	if self:CurrentSacrifice() then
		return
	end
	self.stepIndex = (self.stepIndex or 1) + 1
	self.deleteIndex = 1
end

-- RestedXP InventoryManager.DeleteItems: PickupContainerItem + DeleteCursorItem
-- on the hardware click that already has a FindJunk candidate.
function Engine:DeleteItems()
	if self:IsClassicEraClient() and self.bagScanFrozen then
		return
	end
	if not addon.db or not addon.db.autoDestroy or not self.autoDestroying then
		return
	end
	if UnitIsDead and UnitIsDead("player") then
		return
	end
	if GetCursorInfo and GetCursorInfo() then
		return
	end
	local item = self.deletion and self.deletion.item
	local bag = self.deletion and self.deletion.bag
	local slot = self.deletion and self.deletion.slot
	if not item or bag == nil or not slot then
		return
	end
	if addon.IsHearthstone(item) then
		self:Abort("Refused to delete the Hearthstone.")
		return
	end
	if addon.IsProfessionTool(item) then
		self:Abort("Refused to delete a profession tool.")
		return
	end
	if addon.IsSummonedKeep(item) then
		self:Abort("Refused to delete a summoned item.")
		return
	end
	if addon.IsSpellReagent(item) then
		self:Abort("Refused to delete a spell reagent.")
		return
	end
	if not self:CanAutoDestroy(item) then
		self:ClearDeletion()
		self.autoDestroying = nil
		self:ShowConfirm()
		return
	end
	if self:IsClassicEraClient() then
		self:FreezeBagScan()
		self:CloseLootForDelete()
	end
	local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
	pickup(bag, slot)
	if not CursorHasItem or not CursorHasItem() then
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self:FindJunk()
		return
	end
	DeleteCursorItem()
	if self:DialogShown("DELETE_GOOD_ITEM") or self:DialogShown("DELETE_GOOD_QUEST_ITEM") then
		self:HideDialog("DELETE_GOOD_ITEM")
		self:HideDialog("DELETE_GOOD_QUEST_ITEM")
		self:ClearCursorItem()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.autoDestroying = nil
		self:ClearDeletion()
		self:ShowConfirm()
		return
	end
	if self:DialogShown("DELETE_QUEST_ITEM") then
		self:HideDialog("DELETE_QUEST_ITEM")
		self:ClearCursorItem()
		self:Abort("Refused to delete a quest item.")
		return
	end
	if self:DialogShown("DELETE_ITEM") and not self:IsClassicEraClient() then
		self:AcceptDialog("DELETE_ITEM")
	end
	if CursorHasItem and CursorHasItem() then
		self:ClearCursorItem()
		self:HideDialog("DELETE_ITEM")
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self:FindJunk()
		return
	end
	local count = item.count or 1
	addon.Print("Inventory is full, deleting " .. (item.name or "an item") .. "x" .. count .. ".")
	self.deleteIndex = (self.deleteIndex or 1) + 1
	self.deletion = { bag = nil, slot = nil, item = nil }
	if self:CurrentSacrifice() then
		if self:CanAutoDestroy(self:CurrentSacrifice()) then
			if self:IsClassicEraClient() then
				self:ThawBagScan()
			end
			self:FindJunk()
			return
		end
		self.autoDestroying = nil
		self:ClearDeletion()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self:ShowConfirm()
		addon.Print("Click " .. addon.DestroyActionLabel() .. " again for the next item.")
		return
	end
	self.autoDestroying = nil
	self:ClearDeletion()
	if self:IsClassicEraClient() then
		self:FinishEraDelete()
		return
	end
	if self.plan.openGrant then
		self:OpenGrantDuringClick()
		return
	end
	self.autoHardware = true
	self.state = "working"
	self:BeginStepLoot()
	self.autoHardware = nil
end

function Engine:OnWorldClick()
	if self:MerchantOpen() then
		return
	end
	if self.autoDestroying then
		self:FindJunk()
		self:DeleteItems()
	end
end

function Engine:WorldFrameHook()
	self:OnWorldClick()
end

-- Loot rows stay Blizzard loot. Wrapping them to delete junk made leftover
-- clicks destroy a bag item; the destroy button and world click handle deletes.
function Engine:InstallAutoDestroyHooks()
	if self.autoHooks then
		return
	end
	self.autoHooks = true
	if WorldFrame then
		if self:IsClassicEraClient() and not self.eraWorldWrapped then
			self.eraWorldWrapped = true
			local origDown = WorldFrame:GetScript("OnMouseDown")
			local origUp = WorldFrame:GetScript("OnMouseUp")
			WorldFrame:SetScript("OnMouseDown", function(world, button, ...)
				if Engine.autoDestroying then
					Engine.clickLive = true
					Engine:OnWorldClick()
				end
				if origDown then
					origDown(world, button, ...)
				end
			end)
			WorldFrame:SetScript("OnMouseUp", function(world, button, ...)
				if origUp then
					origUp(world, button, ...)
				end
				Engine.clickLive = nil
			end)
		else
			WorldFrame:HookScript("OnMouseDown", function()
				Engine.clickLive = true
				Engine:OnWorldClick()
			end)
			WorldFrame:HookScript("OnMouseUp", function()
				Engine:OnWorldClick()
				Engine.clickLive = nil
			end)
		end
	end
	local probe = CreateFrame("Frame", nil, UIParent)
	if probe.SetMouseClickEnabled and not self:IsClassicEraClient() then
		local clickFrame = CreateFrame("Frame", "SmartLootJunkHandler", UIParent)
		clickFrame:SetAllPoints(UIParent)
		clickFrame:SetScript("OnMouseDown", function()
			Engine:WorldFrameHook()
			clickFrame:Hide()
		end)
		clickFrame:EnableMouse(false)
		clickFrame:SetMouseClickEnabled(true)
		if clickFrame.EnableMouseMotion then
			clickFrame:EnableMouseMotion(false)
		end
		clickFrame:EnableMouseWheel(false)
		clickFrame:SetFrameStrata("BACKGROUND")
		clickFrame:SetFrameLevel(0)
		clickFrame:Hide()
		self.clickFrame = clickFrame
	end
	probe:Hide()
end

function Engine:TryAutoDestroyCurrent()
	self:CancelLeftoverClose()
	if self:MerchantOpen() then
		self.autoDestroying = nil
		self:ClearDeletion()
		return false
	end
	-- Several items that need space use the loot window one pair at a time.
	local steps = self.plan and self.plan.steps
	if steps and #steps > 1 then
		self.autoDestroying = nil
		self:ClearDeletion()
		return false
	end
	if not self.plan or (self.plan.openGrant or self.plan.directGrant) then
		self.autoDestroying = nil
		self:ClearDeletion()
		return false
	end
	if not self:CanAutoDestroy(self:CurrentSacrifice()) then
		self.autoDestroying = nil
		self:ClearDeletion()
		return false
	end
	self.state = "confirming"
	self.deleteIndex = self.deleteIndex or 1
	self.autoDestroying = true
	self:InstallAutoDestroyHooks()
	self:FindJunk()
	if #(self.plan.leftBehind or {}) > 0 and addon.Decision then
		addon.Decision:ShowPlan(self.plan)
	elseif addon.Decision then
		addon.Decision:Hide()
	end
	self:ShowClickFrameIfReady()
	if (not LootFrame or not LootFrame.IsShown or not LootFrame:IsShown()) and self.clickFrame and self.deletion and self.deletion.bag ~= nil then
		self.clickFrame:Show()
	end
	return true
end

function Engine:ClearStepSacrifices()
	local plan = self.plan
	if not plan then
		return
	end
	plan.sacrifices = {}
	for _, step in ipairs(plan.steps or {}) do
		step.sacrifices = {}
	end
end

function Engine:ActiveLootList()
	if not self.plan then
		return nil
	end
	if self.phase == "immediate" then
		return self.plan.immediate
	end
	if self.phase == "step" then
		local step = self:CurrentStep()
		if step and step.take then
			return { step.take }
		end
		return {}
	end
	return self.plan.takes
end

function Engine:BeginLoot()
	self.lootIndex = 1
	self.state = "looting"
	self:LootNext()
end

function Engine:BeginStepLoot()
	if self:CurrentStep() then
		self.phase = "step"
	else
		self.phase = nil
	end
	self:BeginLoot()
end

function Engine:CompleteIfQuestGrant()
	if not (self.questGrant or (self.plan and self.plan.directGrant)) then
		return false
	end
	local grant = self.plan and ((self.plan.takes and self.plan.takes[1]) or (self.plan.immediate and self.plan.immediate[1]))
	self:FinishQuestGrant(grant)
	self.state = "idle"
	self.plan = nil
	self.questGrant = nil
	self.stepIndex = nil
	self.phase = nil
	if addon.Decision then
		addon.Decision:Hide()
	end
	return true
end

function Engine:AdvanceAfterStepLoot()
	local steps = self.plan and self.plan.steps
	if not steps or #steps == 0 then
		if self:ShowLeftovers() then
			return
		end
		if self:CompleteIfQuestGrant() then
			return
		end
		self.state = "idle"
		self.plan = nil
		self.phase = nil
		self.stepIndex = nil
		self:CloseLootIfEmpty()
		self:Settle()
		return
	end
	self.stepIndex = (self.stepIndex or 1) + 1
	if steps[self.stepIndex] then
		self.deleteIndex = 1
		self.phase = nil
		self.state = "confirming"
		if self:TryAutoDestroyCurrent() then
			return
		end
		if addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		addon.Print("Click " .. addon.DestroyActionLabel() .. " for the next item.")
		return
	end
	if self:ShowLeftovers() then
		return
	end
	if self:CompleteIfQuestGrant() then
		return
	end
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.stepIndex = nil
	self:CloseLootIfEmpty()
	self:Settle()
end

function Engine:CopyOpenItem(item)
	return {
		bag = item.bag,
		slot = item.slot,
		itemID = item.itemID,
		name = item.name,
		texture = item.texture,
		quality = item.quality,
		link = item.link,
		count = item.count or 1,
		openable = true,
	}
end

function Engine:RememberOpenable(item)
	if not item or not item.itemID then
		return
	end
	if not self.openLater then
		self.openLater = {}
	end
	self.openLater[item.itemID] = self:CopyOpenItem(item)
end

function Engine:BagStillHolds(item)
	if not item or item.bag == nil or not item.slot or not C_Container or not C_Container.GetContainerItemID then
		return false
	end
	local id = C_Container.GetContainerItemID(item.bag, item.slot)
	if item.itemID then
		return id == item.itemID
	end
	return id ~= nil
end

function Engine:FindOpenable(item)
	if not item then
		return nil
	end
	if self:BagStillHolds(item) then
		return item
	end
	if not item.itemID or not C_Container or not C_Container.GetContainerItemInfo or not addon.Inventory then
		return nil
	end
	for _, bag in ipairs(addon.Inventory.BagList()) do
		local count = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, count do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == item.itemID and (info.hasLoot or info.lootable or item.openable) then
				return {
					bag = bag,
					slot = slot,
					itemID = info.itemID,
					name = info.itemName or item.name,
					texture = info.iconFileID or item.texture,
					quality = info.quality or item.quality,
					link = info.hyperlink or item.link,
					openable = true,
				}
			end
		end
	end
	return nil
end

function Engine:SuspendPlan()
	if self.suspended then
		return
	end
	if self.state == "confirming" and self.plan and not self.plan.openGrant then
		self.suspended = {
			plan = self.plan,
			questGrant = self.questGrant,
		}
	end
end

function Engine:ResumeSuspended()
	local saved = self.suspended
	self.suspended = nil
	if not saved or not saved.plan or self.state ~= "idle" then
		return
	end
	self.plan = saved.plan
	self.questGrant = saved.questGrant
	self.state = "confirming"
	self.deleteIndex = 1
	if addon.Decision then
		addon.Decision:ShowPlan(saved.plan)
	end
end

function Engine:Settle()
	if self.state ~= "idle" then
		return
	end
	if self.containerLoot then
		self.containerLoot = nil
		self:ResumeSuspended()
		return
	end
	self:OfferWatchedOpens()
end

function Engine:UseOpenable(item)
	if not item or item.bag == nil or not item.slot or not C_Container or not C_Container.UseContainerItem then
		return
	end
	self.openFinished = false
	self.openingItem = self:CopyOpenItem(item)
	self.openQuest = (self.questGrant or (self.plan and self.plan.directGrant) or (self.suspended and self.suspended.questGrant)) and true or false
	self.openToken = (self.openToken or 0) + 1
	if GetCVar and SetCVar and self.savedAutoLoot == nil then
		self.savedAutoLoot = GetCVar("autoLootDefault")
		SetCVar("autoLootDefault", "1")
	end
	C_Container.UseContainerItem(item.bag, item.slot)
	if not self.openingItem then
		self:RestoreAutoLoot()
		return
	end
	self:LootContainerNow()
	if not self.openingItem then
		self:RestoreAutoLoot()
		return
	end
	local quest = self.openQuest
	self.openingItem = nil
	self.openQuest = nil
	self.openToken = (self.openToken or 0) + 1
	self:RestoreAutoLoot()
	if quest then
		self:FinishOpenedQuest()
		return
	end
	if self.state == "confirming" then
		self:Rescan()
	end
end

function Engine:FinishOpenedQuest()
	self.suspended = nil
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.questGrant = nil
	self.skippedOpen = nil
	self.containerLoot = nil
	self:CloseLootWindow()
	if addon.Decision then
		addon.Decision:Hide()
	end
	addon.Print("The item is open. Click the quest target again to take the quest item.")
end

function Engine:OfferOpenProcess(item)
	if not item or item.bag == nil or not item.slot then
		return
	end
	if self.state == "deleting" or self.state == "looting" or self.state == "working" then
		return
	end
	self:SuspendPlan()
	self.openingItem = nil
	local entry = {
		lootType = "item",
		name = item.name or "Openable item",
		texture = item.texture,
		quality = item.quality,
		count = 1,
		maxStack = 1,
		itemFamily = 0,
		equipLoc = "",
		neededForQuest = true,
		openGrant = true,
		unitPrice = 0,
	}
	self.forceSacrifice = nil
	self.questGrant = nil
	self.scanToken = (self.scanToken or 0) + 1
	local token = self.scanToken
	self.state = "loading"
	addon.Inventory.Scan(function(bagItems, _)
		if self.scanToken ~= token or self.state ~= "loading" then
			return
		end
		local plan = addon.BuildPlan({ entry }, bagItems, {}, self:PlanOptions({
			skipBag = item.bag,
			skipSlot = item.slot,
			avoidOpenable = true,
		}))
		plan.openGrant = true
		plan.openItem = self:CopyOpenItem(item)
		if #(plan.sacrifices or {}) == 0 then
			if self.openLater and item.itemID then
				self.openLater[item.itemID] = nil
			end
			self.state = "idle"
			self.plan = nil
			self.phase = nil
			addon.Print("No other item can be removed to open " .. (item.name or "that item") .. ".")
			if addon.Decision then
				addon.Decision:Hide()
			end
			self:ResumeSuspended()
			return
		end
		self.plan = plan
		self:ApplyPlan(plan)
	end)
end

function Engine:OfferWatchedOpens()
	if self.state ~= "idle" or not self.openLater or self.openingItem then
		return
	end
	local pending
	for _, watched in pairs(self.openLater) do
		local found = self:FindOpenable(watched)
		if found then
			pending = found
			break
		end
	end
	if not pending then
		return
	end
	self.plan = {
		openGrant = true,
		openItem = self:CopyOpenItem(pending),
		takes = {},
		sacrifices = {},
		leftBehind = {},
	}
	self.state = "confirming"
	self.deleteIndex = 1
	if addon.Decision then
		addon.Decision:ShowPlan(self.plan)
	end
end

function Engine:OpenFromRow(item)
	if not item or not item.openable then
		return
	end
	if self.state ~= "confirming" and self.state ~= "idle" then
		return
	end
	self:RememberOpenable(item)
	local located = self:FindOpenable(item)
	if not located then
		addon.Print("Will open " .. (item.name or "that item") .. " after it is in your bags.")
		return
	end
	self:UseOpenable(located)
end

function Engine:OpenGrantDuringClick()
	local item = self.plan and self.plan.openItem
	local itemID = item and item.itemID
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.questGrant = nil
	if addon.Decision then
		addon.Decision:Hide()
	end
	if item and self:BagStillHolds(item) then
		self:UseOpenable(item)
		return
	end
	if self.openLater and itemID then
		self.openLater[itemID] = nil
	end
	self:Settle()
end

function Engine:ShowQuestRetry()
	self.plan = {
		directGrant = true,
		readyLoot = true,
		takes = {},
		sacrifices = {},
		leftBehind = {},
	}
	self.questGrant = true
	self.state = "confirming"
	self.deleteIndex = 1
	if addon.Decision then
		addon.Decision:ShowPlan(self.plan)
	end
end

function Engine:SkipOpenable(item)
	if self.state ~= "confirming" or not item or item.bag == nil or item.slot == nil then
		return
	end
	if not self.skippedOpen then
		self.skippedOpen = {}
	end
	self.skippedOpen[item.bag .. ":" .. item.slot] = true
	if self.plan and self.plan.openGrant and self.plan.openItem then
		local openItem = self.plan.openItem
		self.state = "loading"
		self:OfferOpenProcess(openItem)
		return
	end
	if self.questGrant or (self.plan and self.plan.directGrant) then
		local entries = self.questEntries
		if not entries or #entries == 0 then
			entries = { self:FallbackQuestEntry() }
		end
		self.state = "loading"
		self.forceSacrifice = true
		self:OfferQuestGrants(entries)
		return
	end
	self:Rescan()
end

function Engine:Accept()
	if self.state ~= "confirming" or not self.plan then
		return
	end
	if self.plan.readyLoot then
		self.state = "idle"
		self.plan = nil
		self.questGrant = nil
		self.skippedOpen = nil
		self.stepIndex = nil
		if addon.Decision then
			addon.Decision:Hide()
		end
		addon.Print("Bag space is free. Click the corpse again to take the quest item.")
		return
	end
	local first = self:CurrentSacrifice()
	if first and first.openInstead then
		self:UseOpenable(first)
		return
	end
	if first then
		self.state = "deleting"
		self:ArmDeleteOnClick()
		return
	end
	if self.plan.openGrant then
		self:OpenGrantDuringClick()
		return
	end
	self.state = "working"
	if addon.Decision then
		addon.Decision:Hide()
	end
	self:BeginStepLoot()
end

function Engine:OnAcceptRelease()
	if not self.deleteOnRelease then
		return
	end
	self.deleteOnRelease = nil
	if self.state ~= "deleting" or not self.plan then
		self:ClearCursorItem()
		return
	end
	local result = self:FinishDeleteOnRelease()
	if self.state == "idle" then
		return
	end
	if result == "wait" then
		if addon.Decision then
			addon.Decision:Hide()
		end
		return
	end
	if result == "more" then
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.state = "confirming"
		if self:TryAutoDestroyCurrent() then
			return
		end
		if addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		addon.Print("Click " .. addon.DestroyActionLabel() .. " again for the next item.")
		return
	end
	if self:IsClassicEraClient() then
		self:FinishEraDelete()
		return
	end
	if self.plan.openGrant then
		self:OpenGrantDuringClick()
		return
	end
	self.state = "working"
	if addon.Decision then
		addon.Decision:Hide()
	end
	self:BeginStepLoot()
end

function Engine:ProtectAndRebuild(item)
	if self.state ~= "confirming" or not item or not item.itemID then
		return
	end
	if item.protected then
		addon:UnprotectItem(item.itemID)
	else
		addon:ProtectItem(item.itemID, item.name)
	end
	self:Rescan()
end

function Engine:Cancel()
	self:CancelLeftoverClose()
	if self.state ~= "confirming" and not self.deleteOnRelease then
		return
	end
	if self.plan and self.plan.openGrant and self.plan.openItem and self.plan.openItem.itemID and self.openLater then
		self.openLater[self.plan.openItem.itemID] = nil
	end
	local saved = self.suspended
	self.suspended = nil
	local container = self.containerLoot
	self.containerLoot = nil
	self.deleteOnRelease = nil
	self.ignoreLootClosed = nil
	self.state = "idle"
	self.plan = nil
	self.phase = nil
	self.questGrant = nil
	self.skippedOpen = nil
	self.autoDestroying = nil
	self:ClearDeletion()
	self:Disarm()
	self:ThawBagScan()
	self:ClearCursorItem()
	if container or not saved then
		self:CloseLootWindow()
	end
	if addon.Decision then
		addon.Decision:Hide()
	end
	if saved then
		self.suspended = saved
		self:ResumeSuspended()
	end
end

function Engine:ClearCursorItem()
	if CursorHasItem and CursorHasItem() and ClearCursor then
		ClearCursor()
	end
end

function Engine:Abort(message)
	self:CancelLeftoverClose()
	self.ignoreLootClosed = nil
	self:ThawBagScan()
	local busy = self.state ~= "idle"
	self:Disarm()
	self.waitingForBag = false
	self.pendingSlot = nil
	self.inDelete = false
	self.advanceDelete = false
	self.deleteOnRelease = nil
	self.state = "idle"
	self.plan = nil
	self.questGrant = nil
	self.skippedOpen = nil
	self.autoDestroying = nil
	self:ClearDeletion()
	self:ClearCursorItem()
	if addon.Decision then
		addon.Decision:Hide()
	end
	if message and busy then
		addon.Print(message)
	end
end

function Engine:OnLootClosed()
	if self.ignoreLootClosed then
		return
	end
	if self.containerLoot then
		self.containerLoot = nil
		local quest = self.questGrant or (self.suspended and self.suspended.questGrant)
		self:Disarm()
		self.pendingSlot = nil
		if quest then
			self:FinishOpenedQuest()
			return
		end
		self.state = "idle"
		self.plan = nil
		if addon.Decision then
			addon.Decision:Hide()
		end
		self:ResumeSuspended()
		return
	end
	if self.state == "idle" or self.questGrant then
		return
	end
	self:Disarm()
	self.waitingForBag = false
	self.pendingSlot = nil
	self.inDelete = false
	self.advanceDelete = false
	if self.clickFrame then
		self.clickFrame:Hide()
	end
	if self.autoDestroying and self.plan then
		if C_Timer then
			C_Timer.After(0, function()
				Engine:AfterAutoLoot()
			end)
		else
			self:AfterAutoLoot()
		end
		return
	end
	if self.plan and #(self.plan.leftBehind or {}) > 0 then
		self:ShowLeftovers()
		return
	end
	self.state = "idle"
	self.plan = nil
	self.autoDestroying = nil
	self:ClearDeletion()
	self:ClearCursorItem()
	if addon.Decision then
		addon.Decision:Hide()
	end
	self.suspended = nil
	self:OfferWatchedOpens()
end

function Engine:FinishDeleteStep()
	self.inDelete = false
	self.advanceDelete = false
	self.waitingForBag = false
end

-- One destroy per hardware event. Pickup on mouse down; DeleteCursorItem on
-- mouse up. Bag updates from pickup taint the rest of that press, and a second
-- delete in the same click is blocked the same way.
function Engine:ArmDeleteOnClick()
	self.deleteOnRelease = nil
	if self.state ~= "deleting" or not self.plan then
		return
	end
	self.deleteIndex = self.deleteIndex or 1
	local item = self:CurrentSacrifice()
	if not item then
		self.state = "confirming"
		return
	end
	if addon.IsHearthstone(item) then
		self:Abort("Refused to delete the Hearthstone.")
		return
	end
	if addon.IsProfessionTool(item) then
		self:Abort("Refused to delete a profession tool.")
		return
	end
	if addon.IsSummonedKeep(item) then
		self:Abort("Refused to delete a summoned item.")
		return
	end
	if addon.IsSpellReagent(item) then
		self:Abort("Refused to delete a spell reagent.")
		return
	end
	if self:IsClassicEraClient() then
		self:FreezeBagScan()
		self:CloseLootForDelete()
	end
	C_Container.PickupContainerItem(item.bag, item.slot)
	if not CursorHasItem or not CursorHasItem() then
		self:Abort("Could not pick up " .. (item.name or "an item") .. ".")
		return
	end
	self.deleteOnRelease = true
end

function Engine:FinishDeleteOnRelease()
	if self.state ~= "deleting" or not self.plan then
		self:ClearCursorItem()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		return false
	end
	local item = self:CurrentSacrifice()
	if not item then
		self:ClearCursorItem()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		return false
	end
	DeleteCursorItem()
	if self:DialogShown("DELETE_GOOD_ITEM") or self:DialogShown("DELETE_GOOD_QUEST_ITEM") then
		if item.forQuest or item.openable then
			self:WaitForGoodDelete(item)
			return "wait"
		end
		self:HideDialog("DELETE_GOOD_ITEM")
		self:HideDialog("DELETE_GOOD_QUEST_ITEM")
		self:ClearCursorItem()
		self:Abort("Refused to delete a higher quality item.")
		return false
	end
	if self:DialogShown("DELETE_QUEST_ITEM") then
		self:HideDialog("DELETE_QUEST_ITEM")
		self:ClearCursorItem()
		self:Abort("Refused to delete a quest item.")
		return false
	end
	if self:DialogShown("DELETE_ITEM") and not self:IsClassicEraClient() then
		self:AcceptDialog("DELETE_ITEM")
	end
	if CursorHasItem and CursorHasItem() then
		self:ClearCursorItem()
		self:HideDialog("DELETE_ITEM")
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.state = "confirming"
		return "more"
	end
	self.deleteIndex = self.deleteIndex + 1
	if self:CurrentSacrifice() then
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		return "more"
	end
	return false
end

function Engine:WaitForGoodDelete(item)
	self.waitingForGoodDelete = true
	self.goodDeleteItem = item
	local function Watch(which)
		self:ForDialog(which, function(dialog)
			if dialog.smartLootWait or not dialog.HookScript then
				return
			end
			dialog.smartLootWait = true
			dialog:HookScript("OnHide", function(popup)
				popup.smartLootWait = nil
				if Engine.waitingForGoodDelete then
					Engine:FinishGoodDelete()
				end
			end)
		end)
	end
	Watch("DELETE_GOOD_ITEM")
	Watch("DELETE_GOOD_QUEST_ITEM")
	addon.Print("Type DELETE to remove " .. (item.name or "that item") .. ".")
end

function Engine:ItemStillInBag(item)
	if not item or not C_Container or not C_Container.GetContainerItemID then
		return false
	end
	local id = C_Container.GetContainerItemID(item.bag, item.slot)
	if item.itemID then
		return id == item.itemID
	end
	return id ~= nil
end

function Engine:FinishGoodDelete()
	if not self.waitingForGoodDelete or self.state ~= "deleting" or not self.plan then
		return
	end
	if self:DialogShown("DELETE_GOOD_ITEM") or self:DialogShown("DELETE_GOOD_QUEST_ITEM") then
		return
	end
	local item = self.goodDeleteItem
	if self:ItemStillInBag(item) then
		self.waitingForGoodDelete = false
		self.goodDeleteItem = nil
		self:ClearCursorItem()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.state = "confirming"
		if addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		return
	end
	self.waitingForGoodDelete = false
	self.goodDeleteItem = nil
	self.deleteIndex = (self.deleteIndex or 1) + 1
	if self:CurrentSacrifice() then
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.state = "confirming"
		if self:TryAutoDestroyCurrent() then
			return
		end
		if addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		addon.Print("Click " .. addon.DestroyActionLabel() .. " again for the next item.")
		return
	end
	if self.plan.openGrant then
		self:ClearStepSacrifices()
		if self:IsClassicEraClient() then
			self:ThawBagScan()
		end
		self.state = "confirming"
		if addon.Decision then
			addon.Decision:ShowPlan(self.plan)
		end
		return
	end
	if self:IsClassicEraClient() then
		self:FinishEraDelete()
		return
	end
	self.state = "working"
	self:BeginStepLoot()
end

function Engine:OnBagUpdate()
	if self:IsClassicEraClient() and self.bagScanFrozen then
		return
	end
	if addon.Inventory and addon.Inventory.RefreshCache then
		addon.Inventory.RefreshCache()
	end
	if self.waitingForGoodDelete then
		self:FinishGoodDelete()
		return
	end
	if self.autoDestroying then
		self:FindJunk()
		self:ShowClickFrameIfReady()
		return
	end
	if self.state == "idle" then
		self:OfferWatchedOpens()
		return
	end
	if self.state ~= "deleting" or not self.waitingForBag then
		return
	end
	self.waitingForBag = false
	self.inDelete = false
end

function Engine:LootSlotMatches(slot, item)
	if not slot or not item or not GetLootSlotInfo then
		return false
	end
	local _, name, _, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
	if item.lootType == "money" then
		return isCoin and true or false
	end
	if item.lootType == "currency" then
		return (currencyID and currencyID > 0) and true or false
	end
	if isCoin or (currencyID and currencyID > 0) or not name or name == "" then
		return false
	end
	if item.link and GetLootSlotLink then
		local link = GetLootSlotLink(slot)
		if link and item.link == link then
			return true
		end
		if item.itemID and type(link) == "string" then
			local id = tonumber(link:match("item:(%d+)"))
			if id and id == item.itemID then
				return true
			end
		end
	end
	return item.name ~= nil and name == item.name
end

function Engine:FindCurrentLootSlot(item)
	if not item or item.questGrant or not GetNumLootItems then
		return nil
	end
	if item.slot and self:LootSlotMatches(item.slot, item) then
		return item.slot
	end
	local count = GetNumLootItems() or 0
	local best
	for slot = count, 1, -1 do
		if self:LootSlotMatches(slot, item) then
			if not best or slot > best then
				best = slot
			end
		end
	end
	return best
end

function Engine:NextPresentLoot(list)
	if not list then
		return nil
	end
	local best, bestSlot
	for index = 1, #list do
		local item = list[index]
		if item and not item.questGrant then
			local slot = self:FindCurrentLootSlot(item)
			if slot and (not bestSlot or slot > bestSlot) then
				best = item
				bestSlot = slot
			end
		end
	end
	if best then
		best.slot = bestSlot
	end
	return best
end

function Engine:FinishLootList()
	self:Disarm()
	self.pendingSlot = nil
	if self.phase == "immediate" then
		self.phase = nil
		self:OfferDecision()
		return
	end
	if self.phase == "step" then
		self:AdvanceAfterStepLoot()
		return
	end
	if self:CompleteIfQuestGrant() then
		return
	end
	self.state = "idle"
	self.plan = nil
	self.stepIndex = nil
	self:CloseLootIfEmpty()
	self:Settle()
end

function Engine:OnLootStuck()
	local stuck = self.pendingSlot
	self.pendingSlot = nil
	self:Disarm()
	if stuck and self:SlotStillHasLoot(stuck) then
		if self.phase == "immediate" then
			self.skipImmediate = true
			self:Rescan()
			return
		end
		self:FinishLootList()
		return
	end
	self:LootNext()
end

function Engine:LootNext()
	if self.state ~= "looting" or not self.plan then
		return
	end
	local item = self:NextPresentLoot(self:ActiveLootList())
	if not item then
		self:FinishLootList()
		return
	end
	self.pendingSlot = item.slot
	self:ArmWatchdog()
	if self:IsClassicEraClient() and LootSlotHasItem and not LootSlotHasItem(item.slot) then
		self:FinishLootList()
		return
	end
	LootSlot(item.slot)
	if C_Timer then
		local slot = item.slot
		C_Timer.After(0, function()
			if self.state == "looting" and self.pendingSlot == slot and self:DialogShown("LOOT_BIND") then
				self:OnBindConfirm(slot)
			end
		end)
	end
end

function Engine:OnSlotCleared(slot)
	if self.state ~= "looting" or slot ~= self.pendingSlot then
		return
	end
	self.pendingSlot = nil
	self:LootNext()
end

function Engine:OnBindConfirm(slot)
	if self.state ~= "looting" or slot ~= self.pendingSlot then
		return
	end
	if ConfirmLootSlot then
		ConfirmLootSlot(slot)
	end
	self:HideDialog("LOOT_BIND")
end
