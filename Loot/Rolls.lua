local addon = SmartLoot or {}
SmartLoot = addon

local Rolls = {}
addon.Rolls = Rolls

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
	local minimum = tonumber(settings.minItemLevel) or 0
	local level = tonumber(item.itemLevel)
	if not level or level < minimum then
		return nil
	end
	local need = false
	if item.isGear and item.usable and item.upgrade then
		need = true
	elseif item.isGear and item.missingTransmog and settings.transmogRoll == "need" then
		need = true
	end
	if need and item.canNeed then
		return "need"
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

local function RollNumber(choice)
	if Enum and Enum.LootRollType then
		if choice == "need" then
			return Enum.LootRollType.Need or 1
		end
		return Enum.LootRollType.Greed or 2
	end
	if choice == "need" then
		return 1
	end
	return 2
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

function Rolls:MainHandIsTwoHand()
	if not GetInventoryItemLink then
		return false
	end
	local link = GetInventoryItemLink("player", 16)
	return EquipLoc(link) == "INVTYPE_2HWEAPON"
end

function Rolls:IsUpgrade(link, equipLoc)
	local slots = self:SlotsFor(equipLoc)
	if not slots or not GetInventoryItemLink then
		return false
	end
	local usesWeapon = false
	for index = 1, #slots do
		if slots[index] == 16 or slots[index] == 17 then
			usesWeapon = true
		end
	end
	if usesWeapon and self:MainHandIsTwoHand() then
		slots = { 16 }
	end
	local weakest
	for index = 1, #slots do
		local equipped = GetInventoryItemLink("player", slots[index])
		if not equipped then
			return true
		end
		local level = ItemLevel(equipped) or 0
		if not weakest or level < weakest then
			weakest = level
		end
	end
	return (ItemLevel(link) or 0) > (weakest or 0)
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

function Rolls:ReadRoll(rollID)
	if not GetLootRollItemInfo then
		return nil
	end
	return { GetLootRollItemInfo(rollID) }
end

function Rolls:Decide(rollID, link)
	local info = self:ReadRoll(rollID)
	if not info or (not info[1] and not info[2]) then
		return nil
	end
	local canNeed, canGreed, canTransmog = info[6], info[7], info[13]
	local equipLoc = EquipLoc(link)
	local isGear = equipLoc ~= nil
	local item = {
		itemLevel = ItemLevel(link),
		isGear = isGear,
		usable = isGear and self:IsUsable(link) or false,
		upgrade = isGear and self:IsUpgrade(link, equipLoc) or false,
		missingTransmog = isGear and self:MissingTransmog(link, canTransmog) or false,
		canNeed = canNeed and true or false,
		canGreed = canGreed and true or false,
	}
	return addon.ChooseRoll(item, {
		minItemLevel = addon.db.rollMinItemLevel,
		transmogRoll = addon.db.transmogRoll,
	})
end

function Rolls:RollNow(rollID)
	if self.pending[rollID] or not GetLootRollItemLink or not RollOnLoot then
		return
	end
	local link = GetLootRollItemLink(rollID)
	if not link or not ItemLevel(link) then
		return
	end
	local choice = self:Decide(rollID, link)
	if not choice then
		return
	end
	local rollType = RollNumber(choice)
	self.pending[rollID] = rollType
	RollOnLoot(rollID, rollType)
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
	if ItemLevel(link) then
		self:RollNow(rollID)
		return
	end
	if not Item or not Item.CreateFromItemLink then
		return
	end
	local item = Item:CreateFromItemLink(link)
	if not item or not item.ContinueOnItemLoad then
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

function Rolls:Initialize()
	if self.frame then
		return
	end
	self.pending = {}
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
			Rolls.pending[rollID] = nil
		end
	end)
end
