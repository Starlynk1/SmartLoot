local addon = SmartLoot or {}
SmartLoot = addon

local Inventory = {}
addon.Inventory = Inventory

local function AddBag(list, seen, bag)
	if bag == nil or seen[bag] then
		return
	end
	seen[bag] = true
	list[#list + 1] = bag
end

function Inventory.BagList()
	local list = {}
	local seen = {}
	local backpack = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
	AddBag(list, seen, backpack)
	local bagCount = NUM_TOTAL_EQUIPPED_BAG_SLOTS
	if not bagCount then
		bagCount = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
	end
	if addon.IsClassicEra and addon.IsClassicEra() then
		bagCount = NUM_BAG_SLOTS or 4
	end
	for index = 1, bagCount do
		AddBag(list, seen, index)
	end
	if addon.IsClassicEra and addon.IsClassicEra() then
		return list
	end
	if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
		AddBag(list, seen, Enum.BagIndex.ReagentBag)
	end
	return list
end

local CONTAINER_FAMILY = {
	[1] = 4, -- soul
	[2] = 32, -- herb
	[3] = 64, -- enchanting
	[4] = 128, -- engineering
	[5] = 512, -- gem
	[6] = 1024, -- mining
	[7] = 8, -- leatherworking / skinning
	[8] = 16, -- inscription
	[9] = 32768, -- fishing
	[10] = 65536, -- cooking
}

function Inventory.ResolveBagFamily(bag, reported)
	if reported and reported ~= 0 then
		return reported
	end
	if not bag or bag == 0 or not C_Container or not C_Container.ContainerIDToInventoryID then
		return 0
	end
	local invID = C_Container.ContainerIDToInventoryID(bag)
	local link = invID and GetInventoryItemLink and GetInventoryItemLink("player", invID)
	if not link then
		return 0
	end
	if C_Item and C_Item.GetItemFamily then
		local ok, family = pcall(C_Item.GetItemFamily, link)
		if ok and family and family ~= 0 then
			return family
		end
	end
	if not C_Item or not C_Item.GetItemInfo then
		return 0
	end
	local ok, _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfo, link)
	if not ok then
		return 0
	end
	local containerClass = Enum and Enum.ItemClass and Enum.ItemClass.Container or 1
	if classID == containerClass then
		if subclassID == 11 then
			return -1
		end
		return CONTAINER_FAMILY[subclassID] or 0
	end
	local quiverClass = Enum and Enum.ItemClass and Enum.ItemClass.Quiver or 11
	if classID == quiverClass then
		if subclassID == 3 then
			return 2
		end
		return 1
	end
	return 0
end

function addon.BagItemUsable(item)
	local query = item and (item.link or item.itemID)
	if not query then
		return false
	end
	if C_Item and C_Item.IsUsableItem then
		local ok, usable = pcall(C_Item.IsUsableItem, query)
		return ok and usable and true or false
	end
	if IsUsableItem then
		return IsUsableItem(query) and true or false
	end
	return false
end

function addon.BagItemNeedsTransmog(item)
	if not item or not addon.Rolls or not addon.Rolls.MissingTransmog then
		return false
	end
	local query = item.link or item.itemID
	if not query then
		return false
	end
	return addon.Rolls:MissingTransmog(query) and true or false
end

function addon.MarkBagKeeps(items)
	if not items then
		return
	end
	for index = 1, #items do
		local item = items[index]
		-- Only gear uses usable / transmog keeps. Trade goods (vials, cloth, etc.)
		-- often report IsUsableItem and must still be deletable when cheap.
		if item.quality ~= 0 and addon.IsGear(item) then
			item.usable = addon.BagItemUsable(item)
			item.keepTransmog = addon.BagItemNeedsTransmog(item)
		else
			item.usable = false
			item.keepTransmog = false
		end
	end
end

-- Live bag snapshot so the corpse click can compare vendor values without
-- waiting for a second inventory scan.
Inventory.items = {}
Inventory.freeSlots = {}
Inventory.junk = {}

local function SortJunk(left, right)
	return addon.SortDestroyCandidate(left, right)
end

function Inventory.RebuildJunk()
	local junk = {}
	if addon.db and addon.db.autoDestroy then
		for index = 1, #(Inventory.items or {}) do
			local item = Inventory.items[index]
			if addon.IsAutoDestroyCandidate(item) then
				local copy = {}
				for key, value in pairs(item) do
					copy[key] = value
				end
				copy.value = addon.ItemValue(item)
				junk[#junk + 1] = copy
			end
		end
		table.sort(junk, SortJunk)
	end
	Inventory.junk = junk
	return junk
end

function Inventory.ScanNow()
	if Inventory.scanLocked then
		return Inventory.items or {}, Inventory.freeSlots or {}
	end
	local items = {}
	local freeSlots = {}
	Inventory.items = items
	Inventory.freeSlots = freeSlots
	Inventory.junk = {}
	if not C_Container then
		return items, freeSlots
	end

	local skipQuestInfo = addon.IsClassicEra and addon.IsClassicEra()
	for _, bag in ipairs(Inventory.BagList()) do
		local slotCount = C_Container.GetContainerNumSlots(bag) or 0
		local _, reportedFamily = C_Container.GetContainerNumFreeSlots(bag)
		local bagFamily = Inventory.ResolveBagFamily(bag, reportedFamily or 0)
		for slot = 1, slotCount do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if not info or not info.itemID then
				freeSlots[#freeSlots + 1] = bagFamily
			else
				local questInfo
				if not skipQuestInfo and C_Container.GetContainerItemQuestInfo then
					questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
				end
				local item = {
					bag = bag,
					slot = slot,
					itemID = info.itemID,
					link = info.hyperlink,
					name = info.itemName,
					texture = info.iconFileID,
					count = info.stackCount or 1,
					quality = info.quality,
					locked = info.isLocked and true or false,
					openable = (info.hasLoot or info.lootable or info.isOpenable) and true or false,
					isQuest = questInfo and questInfo.isQuestItem or false,
					bagFamily = bagFamily,
					protected = addon.db and addon.db.protected and addon.db.protected[info.itemID] ~= nil or false,
				}
				if not addon.ReadItemData(item) and C_Item and C_Item.RequestLoadItemDataByID then
					pcall(C_Item.RequestLoadItemDataByID, info.itemID)
				end
				items[#items + 1] = item
			end
		end
	end

	addon.MarkBagKeeps(items)
	addon.MarkOpenableItems(items)
	Inventory.RebuildJunk()
	return items, freeSlots
end

function Inventory.RefreshCache()
	local items, freeSlots = Inventory.ScanNow()
	if addon.DeleteList and addon.DeleteList.RefreshIfShown then
		addon.DeleteList:RefreshIfShown()
	end
	return items, freeSlots
end

function Inventory.Scan(callback)
	local items, freeSlots = Inventory.ScanNow()
	callback(items, freeSlots)
end

local function LineIsOpenable(text)
	if type(text) ~= "string" then
		return false
	end
	local phrase = ITEM_OPENABLE
	if type(phrase) ~= "string" or phrase == "" then
		phrase = "Right Click to Open"
	end
	local ok, found = pcall(function()
		local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if plain:find(phrase, 1, true) then
			return true
		end
		if phrase ~= "Right Click to Open" then
			return plain:find("Right Click to Open", 1, true) ~= nil
		end
		return false
	end)
	return ok and found or false
end

local function DataSaysOpenable(data)
	if not data or not data.lines then
		return false
	end
	if TooltipUtil and TooltipUtil.SurfaceArgs then
		pcall(TooltipUtil.SurfaceArgs, data)
	end
	for index = 1, #data.lines do
		local line = data.lines[index]
		if type(line) == "table" then
			if TooltipUtil and TooltipUtil.SurfaceArgs then
				pcall(TooltipUtil.SurfaceArgs, line)
			end
			if LineIsOpenable(line.leftText) or LineIsOpenable(line.rightText) then
				return true
			end
		elseif LineIsOpenable(line) then
			return true
		end
	end
	return false
end

local openTip

local function HiddenOpenable(item)
	if not CreateFrame then
		return false
	end
	if not openTip then
		openTip = CreateFrame("GameTooltip", "SmartLootOpenTip", nil, "GameTooltipTemplate")
	end
	openTip:SetOwner(UIParent, "ANCHOR_NONE")
	openTip:ClearLines()
	local shown = false
	if item.bag ~= nil and item.slot and openTip.SetBagItem then
		shown = pcall(openTip.SetBagItem, openTip, item.bag, item.slot)
	end
	if not shown and item.link and openTip.SetHyperlink then
		shown = pcall(openTip.SetHyperlink, openTip, item.link)
	end
	if not shown then
		openTip:Hide()
		return false
	end
	local tipName = openTip:GetName()
	local count = openTip:NumLines() or 0
	local found = false
	for index = 1, count do
		local left = _G[tipName .. "TextLeft" .. index]
		local right = _G[tipName .. "TextRight" .. index]
		if (left and LineIsOpenable(left:GetText())) or (right and LineIsOpenable(right:GetText())) then
			found = true
			break
		end
	end
	openTip:Hide()
	return found
end

function addon.TooltipSaysOpenable(item)
	if not item then
		return false
	end
	if C_TooltipInfo and C_TooltipInfo.GetBagItem and item.bag ~= nil and item.slot then
		local ok, data = pcall(C_TooltipInfo.GetBagItem, item.bag, item.slot)
		if ok and DataSaysOpenable(data) then
			return true
		end
	end
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink and item.link then
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, item.link)
		if ok and DataSaysOpenable(data) then
			return true
		end
	end
	return HiddenOpenable(item)
end

local openableKnown = {}

function addon.MarkOpenableItems(items)
	if not items then
		return
	end
	for index = 1, #items do
		local item = items[index]
		if item and not item.openable and item.itemID and item.lootType ~= "money" and item.lootType ~= "currency" then
			local known = openableKnown[item.itemID]
			if known == nil then
				known = addon.TooltipSaysOpenable(item) and true or false
				openableKnown[item.itemID] = known
			end
			if known then
				item.openable = true
			end
		end
	end
end
