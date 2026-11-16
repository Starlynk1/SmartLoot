local addon = SmartLoot or {}
SmartLoot = addon

local Rolls = {}
addon.Rolls = Rolls

local CLASS_MISC = 15
local SUBCLASS_MOUNT = 5

local SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_TABARD = { 19 },
}

function addon.ChooseRoll(item, settings)
	settings = settings or {}
	local transmogRoll = settings.transmogRoll or "greed"
	if item.isMount then
		if item.hasMount then
			return "pass"
		end
		if item.canNeed then
			return "need"
		end
		if item.canGreed then
			return "greed"
		end
		return nil
	end
	if item.isGear ~= false and item.usable ~= false and (item.upgrade == "main" or item.upgrade == true) then
		if item.canNeed then
			return "need"
		end
		if item.canGreed then
			return "greed"
		end
		return nil
	end
	if item.upgrade == "offspec" then
		if item.canNeed then
			return "ask-offspec"
		end
		if item.canGreed then
			return "greed"
		end
		return nil
	end
	if item.missingTransmog then
		if transmogRoll == "pass" then
			return "pass"
		end
		if transmogRoll == "need" and item.canNeed then
			return "need"
		end
		if item.canGreed then
			return "greed"
		end
		return nil
	end
	if item.canGreed then
		return "greed"
	end
	return nil
end

local function ItemLevel(link)
	if not link then
		return nil
	end
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		local level = C_Item.GetDetailedItemLevelInfo(link)
		if type(level) == "number" then
			return level
		end
	end
	if GetDetailedItemLevelInfo then
		local level = GetDetailedItemLevelInfo(link)
		if type(level) == "number" then
			return level
		end
	end
	if C_Item and C_Item.GetItemInfo then
		return select(4, C_Item.GetItemInfo(link))
	end
	if GetItemInfo then
		return select(4, GetItemInfo(link))
	end
end

local function EquipLoc(link)
	local loc
	if C_Item and C_Item.GetItemInfo then
		loc = select(9, C_Item.GetItemInfo(link))
	elseif GetItemInfo then
		loc = select(9, GetItemInfo(link))
	end
	if loc == "" or loc == "INVTYPE_NON_EQUIP" or loc == "INVTYPE_NON_EQUIP_IGNORE" then
		return nil
	end
	return loc
end

local function ItemID(link)
	if not link then
		return nil
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local id = C_Item.GetItemInfoInstant(link)
		if id then
			return id
		end
	end
	return tonumber(string.match(link, "item:(%d+)"))
end

local function RollNumber(choice)
	local types = Enum and Enum.LootRollType
	if choice == "need" then
		return types and types.Need or 1
	end
	if choice == "pass" then
		return types and types.Pass or 0
	end
	return types and types.Greed or 2
end

function Rolls:SlotsFor(equipLoc)
	if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
		if addon.UsesClassicRangedSlot and addon.UsesClassicRangedSlot() then
			return { 18 }
		end
		return { 16 }
	end
	return SLOTS[equipLoc]
end

function Rolls:InGroup()
	if IsInGroup then
		return IsInGroup()
	end
	if GetNumGroupMembers then
		return (GetNumGroupMembers() or 0) > 0
	end
	return false
end

function Rolls:CurrentSpecIndex()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	if GetSpecialization then
		return GetSpecialization()
	end
	if GetPrimaryTalentTree then
		return GetPrimaryTalentTree()
	end
	if not GetNumTalentTabs or not GetTalentTabInfo then
		return nil
	end
	local bestIndex
	local bestPoints = -1
	for index = 1, GetNumTalentTabs() or 0 do
		local _, _, pointsSpent = GetTalentTabInfo(index)
		local points = type(pointsSpent) == "number" and pointsSpent or 0
		if points > bestPoints then
			bestPoints = points
			bestIndex = index
		end
	end
	return bestIndex
end

function Rolls:ScaleKind(scale)
	if not scale then
		return "main"
	end
	local classID
	if UnitClass then
		classID = select(3, UnitClass("player"))
	end
	if scale.ClassID and classID and scale.ClassID ~= classID then
		return nil
	end
	if not scale.SpecID then
		return "main"
	end
	local spec = self:CurrentSpecIndex()
	if not spec or scale.SpecID == spec then
		return "main"
	end
	return "offspec"
end

function Rolls:PawnUpgradeKind(link)
	if not link or not PawnGetItemData or not PawnIsItemAnUpgrade then
		return nil, false
	end
	if PawnIsReady and not PawnIsReady() then
		return nil, true
	end
	local ok, item = pcall(PawnGetItemData, link)
	if not ok or not item then
		return nil, false
	end
	if item.Link == nil then
		return nil, true
	end
	local upgradeOk, upgrades = pcall(PawnIsItemAnUpgrade, item)
	if not upgradeOk or type(upgrades) ~= "table" or #upgrades == 0 then
		return nil, false
	end
	local hasMain
	local hasOff
	for index = 1, #upgrades do
		local name = upgrades[index] and upgrades[index].ScaleName
		local scale = PawnCommon and PawnCommon.Scales and name and PawnCommon.Scales[name]
		local kind = self:ScaleKind(scale)
		if kind == "main" then
			hasMain = true
		elseif kind == "offspec" then
			hasOff = true
		end
	end
	if hasMain then
		return "main", false
	end
	if hasOff then
		return "offspec", false
	end
	return nil, false
end

function Rolls:IsUsable(link)
	if C_Item and C_Item.IsEquippableItem and not C_Item.IsEquippableItem(link) then
		return false
	end
	if C_Item and C_Item.IsUsableItem then
		if C_Item.IsUsableItem(link) == false then
			return false
		end
	elseif IsUsableItem and IsUsableItem(link) == false then
		return false
	end
	return true
end

function Rolls:MissingTransmog(link, canTransmog)
	if canTransmog == false or not link or not C_TransmogCollection then
		return false
	end
	if not C_TransmogCollection.GetItemInfo or not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
		return false
	end
	local ok, _, sourceID = pcall(C_TransmogCollection.GetItemInfo, link)
	if not ok or not sourceID or sourceID == 0 then
		return false
	end
	local knownOk, known = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID)
	if not knownOk then
		return false
	end
	return not known
end

function Rolls:MountInfo(link)
	local id = ItemID(link)
	local mountID
	if id and C_MountJournal and C_MountJournal.GetMountFromItem then
		local ok, found = pcall(C_MountJournal.GetMountFromItem, id)
		if ok then
			mountID = found
		end
	end
	local classID, subclassID
	if C_Item and C_Item.GetItemInfoInstant then
		classID, subclassID = select(6, C_Item.GetItemInfoInstant(link))
	elseif GetItemInfoInstant then
		classID, subclassID = select(6, GetItemInfoInstant(link))
	end
	local misc = Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous or CLASS_MISC
	local mountSub = Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount or SUBCLASS_MOUNT
	local isMount = mountID ~= nil or (classID == misc and subclassID == mountSub)
	if not isMount then
		return false, false
	end
	if mountID and C_MountJournal and C_MountJournal.GetMountInfoByID then
		local ok, collected = pcall(function()
			return select(11, C_MountJournal.GetMountInfoByID(mountID))
		end)
		if ok then
			return true, collected and true or false
		end
	end
	if id and GetItemSpell then
		local _, spellID = GetItemSpell(id)
		if type(spellID) ~= "number" then
			_, _, spellID = GetItemSpell(id)
		end
		if type(spellID) == "number" then
			if IsPlayerSpell and IsPlayerSpell(spellID) then
				return true, true
			end
			if IsSpellKnown and IsSpellKnown(spellID) then
				return true, true
			end
		end
	end
	return true, false
end

function Rolls:ReadRoll(rollID)
	if not GetLootRollItemInfo then
		return nil
	end
	return { GetLootRollItemInfo(rollID) }
end

function Rolls:Decide(rollID, link)
	local info = self:ReadRoll(rollID)
	if not info or (not info[1] and not info[2]) then
		return nil, false
	end
	local canNeed, canGreed, canTransmog = info[6], info[7], info[13]
	local isMount, hasMount = self:MountInfo(link)
	local equipLoc = EquipLoc(link)
	local isGear = equipLoc ~= nil
	local upgrade, pending = nil, false
	if isGear then
		upgrade, pending = self:PawnUpgradeKind(link)
	end
	local item = {
		isMount = isMount,
		hasMount = hasMount,
		isGear = isGear,
		usable = isGear and self:IsUsable(link) or false,
		upgrade = upgrade,
		missingTransmog = isGear and self:MissingTransmog(link, canTransmog) or false,
		canNeed = canNeed and true or false,
		canGreed = canGreed and true or false,
	}
	return addon.ChooseRoll(item, {
		transmogRoll = addon.db and addon.db.transmogRoll or "greed",
	}), pending
end

function Rolls:ApplyChoice(rollID, choice)
	if not choice or choice == "ask-offspec" or not RollOnLoot then
		return
	end
	local rollType = RollNumber(choice)
	self.pending[rollID] = rollType
	RollOnLoot(rollID, rollType)
end

function Rolls:EnsurePrompt()
	if self.prompt then
		return
	end
	local frame = CreateFrame("Frame", "SmartLootRollPrompt", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(360, 120)
	frame:SetPoint("CENTER", 0, 80)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
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
	local iconButton = CreateFrame("Button", nil, frame)
	iconButton:SetSize(36, 36)
	iconButton:SetPoint("TOPLEFT", 18, -18)
	local icon = iconButton:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	iconButton:SetScript("OnEnter", function(owner)
		if Rolls.promptLink and GameTooltip then
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(Rolls.promptLink)
			GameTooltip:Show()
		end
	end)
	iconButton:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 10, -2)
	title:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
	title:SetJustifyH("LEFT")
	title:SetText("Off-spec item")
	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	name:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
	name:SetJustifyH("LEFT")
	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	help:SetPoint("TOPLEFT", iconButton, "BOTTOMLEFT", 0, -8)
	help:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
	help:SetJustifyH("LEFT")
	help:SetText("This is an off-spec upgrade. Need or Greed?")
	local need = addon.CreateButton(frame, "Need", 90)
	need:SetPoint("BOTTOMLEFT", 40, 16)
	need:SetScript("OnClick", function()
		Rolls:AnswerPrompt("need")
	end)
	local greed = addon.CreateButton(frame, "Greed", 90)
	greed:SetPoint("LEFT", need, "RIGHT", 16, 0)
	greed:SetScript("OnClick", function()
		Rolls:AnswerPrompt("greed")
	end)
	frame:Hide()
	self.prompt = frame
	self.promptIcon = icon
	self.promptName = name
end

function Rolls:HidePrompt()
	if self.prompt then
		self.prompt:Hide()
	end
	self.promptRollID = nil
	self.promptLink = nil
end

function Rolls:ShowOffSpecPrompt(rollID, link, texture, itemName)
	self:EnsurePrompt()
	self.promptRollID = rollID
	self.promptLink = link
	self.promptIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	self.promptName:SetText(itemName or link or "Item")
	self.prompt:Show()
end

function Rolls:AnswerPrompt(choice)
	local rollID = self.promptRollID
	self:HidePrompt()
	if rollID then
		self:ApplyChoice(rollID, choice)
	end
	self:NextQueued()
end

function Rolls:Enqueue(rollID, link, texture, itemName)
	self.queue = self.queue or {}
	self.queue[#self.queue + 1] = {
		rollID = rollID,
		link = link,
		texture = texture,
		name = itemName,
	}
end

function Rolls:NextQueued()
	local queue = self.queue
	if not queue or #queue == 0 then
		return
	end
	local nextPrompt = table.remove(queue, 1)
	if self.pending[nextPrompt.rollID] then
		self:NextQueued()
		return
	end
	self:ShowOffSpecPrompt(nextPrompt.rollID, nextPrompt.link, nextPrompt.texture, nextPrompt.name)
end

function Rolls:RollNow(rollID)
	if self.pending[rollID] or not GetLootRollItemLink then
		return
	end
	local link = GetLootRollItemLink(rollID)
	if not link then
		return
	end
	local choice, pending = self:Decide(rollID, link)
	if pending then
		self.wait = self.wait or {}
		local tries = (self.wait[rollID] or 0) + 1
		self.wait[rollID] = tries
		if tries <= 10 and C_Timer and C_Timer.After then
			C_Timer.After(0.3, function()
				if addon.db and addon.db.autoRoll then
					Rolls:RollNow(rollID)
				end
			end)
			return
		end
	end
	if self.wait then
		self.wait[rollID] = nil
	end
	if choice == "ask-offspec" then
		local info = self:ReadRoll(rollID) or {}
		if self.promptRollID then
			self:Enqueue(rollID, link, info[1], info[2])
		else
			self:ShowOffSpecPrompt(rollID, link, info[1], info[2])
		end
		return
	end
	self:ApplyChoice(rollID, choice)
end

function Rolls:OnStart(rollID)
	if not addon.db or not addon.db.enabled or not addon.db.autoRoll then
		return
	end
	if not self:InGroup() then
		return
	end
	if not GetLootRollItemLink then
		return
	end
	local link = GetLootRollItemLink(rollID)
	if not link then
		return
	end
	if ItemLevel(link) or ItemID(link) then
		self:RollNow(rollID)
		return
	end
	if not Item or not Item.CreateFromItemLink then
		self:RollNow(rollID)
		return
	end
	local item = Item:CreateFromItemLink(link)
	if not item or not item.ContinueOnItemLoad then
		self:RollNow(rollID)
		return
	end
	item:ContinueOnItemLoad(function()
		if not addon.db or not addon.db.autoRoll then
			return
		end
		self:RollNow(rollID)
	end)
end

function Rolls:OnConfirm(rollID, rollType)
	if self.pending[rollID] ~= rollType or not ConfirmLootRoll then
		return
	end
	ConfirmLootRoll(rollID, rollType)
end

function Rolls:OnCancel(rollID)
	self.pending[rollID] = nil
	if self.promptRollID == rollID then
		self:HidePrompt()
		self:NextQueued()
	elseif self.queue then
		local kept = {}
		for index = 1, #self.queue do
			if self.queue[index].rollID ~= rollID then
				kept[#kept + 1] = self.queue[index]
			end
		end
		self.queue = kept
	end
end

function Rolls:Initialize()
	if self.frame then
		return
	end
	self.pending = {}
	self.queue = {}
	local frame = CreateFrame("Frame")
	self.frame = frame
	frame:RegisterEvent("START_LOOT_ROLL")
	frame:RegisterEvent("CANCEL_LOOT_ROLL")
	frame:RegisterEvent("CONFIRM_LOOT_ROLL")
	frame:SetScript("OnEvent", function(_, event, rollID, rollType)
		if event == "START_LOOT_ROLL" then
			Rolls:OnStart(rollID)
		elseif event == "CONFIRM_LOOT_ROLL" then
			Rolls:OnConfirm(rollID, rollType)
		else
			Rolls:OnCancel(rollID)
		end
	end)
end
