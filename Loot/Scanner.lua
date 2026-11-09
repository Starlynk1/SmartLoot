local addon = SmartLoot or {}
SmartLoot = addon

local Scanner = {}
addon.Scanner = Scanner

local function SlotKind(slot, isCoin, currencyID)
	local slotType = GetLootSlotType and GetLootSlotType(slot)
	local lootSlot = Enum and Enum.LootSlotType
	if isCoin or (lootSlot and slotType == lootSlot.Money) then
		return "money"
	end
	if (currencyID and currencyID ~= 0) or (lootSlot and slotType == lootSlot.Currency) then
		return "currency"
	end
	if lootSlot and slotType and slotType ~= lootSlot.Item then
		return nil
	end
	return "item"
end

local function ItemIDFromLink(link)
	if type(link) ~= "string" then
		return nil
	end
	return tonumber(link:match("item:(%d+)"))
end

function Scanner.ScanNow()
	local entries = {}
	local count = GetNumLootItems and GetNumLootItems() or 0
	for slot = 1, count do
		local texture, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slot)
		local kind = SlotKind(slot, isCoin, currencyID)
		if kind == "item" and (not name or name == "") then
			kind = nil
		end
		if kind then
			local link = kind == "item" and GetLootSlotLink and GetLootSlotLink(slot) or nil
			local entry = {
				slot = slot,
				lootType = kind,
				name = name,
				texture = texture,
				count = quantity or 1,
				quality = quality,
				locked = locked and true or false,
				isQuest = isQuestItem and true or false,
				questID = questID and questID ~= 0 and questID or nil,
				neededForQuest = addon.LootSlotNeedsQuest(isQuestItem, questID, isActive),
				link = link,
				itemID = ItemIDFromLink(link),
			}
			if kind == "item" then
				if not addon.ReadItemData(entry) and C_Item and C_Item.RequestLoadItemDataByID and entry.itemID then
					pcall(C_Item.RequestLoadItemDataByID, entry.itemID)
				end
			end
			entries[#entries + 1] = entry
		end
	end
	addon.MarkTrackedQuestItems(entries)
	addon.MarkOpenableItems(entries)
	return entries
end

function Scanner.Scan(callback)
	callback(Scanner.ScanNow())
end
