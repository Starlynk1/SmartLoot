local addon = SmartLoot or {}
SmartLoot = addon

local TRADE_GOODS = 7
local CLASS_REAGENT = 5
local CLASS_MISCELLANEOUS = 15
local MISC_REAGENT = 1
-- Trade Goods subclasses that are vendor supplies (not gathered/looted mats):
-- classic catch-all (0), Parts (1), Other (11, Forever vials).
local VENDOR_TRADE_SUBCLASS = {
	[0] = true,
	[1] = true,
	[11] = true,
}

-- Spell reagents by classification: mage portal/teleport runes, ankhs,
-- symbols, feathers, arcane powder, etc. Forever files many as Misc / Reagent.
function addon.IsSpellReagent(item)
	if not item then
		return false
	end
	local classID = item.classID
	if classID == CLASS_REAGENT then
		return true
	end
	return classID == CLASS_MISCELLANEOUS and item.subclassID == MISC_REAGENT
end

local function AsCopper(value)
	if type(value) == "number" and value > 0 then
		return math.floor(value + 0.5)
	end
	return nil
end

-- True for Trade Goods Parts / Other (and classic Trade Goods catch-all).
function addon.IsVendorTradeSupply(item)
	if not item or item.classID ~= TRADE_GOODS then
		return false
	end
	return VENDOR_TRADE_SUBCLASS[item.subclassID] and true or false
end

function addon.HasVendorBuyPrice(itemID, link)
	if Auctionator and Auctionator.API and Auctionator.API.v1 then
		local api = Auctionator.API.v1
		if itemID and api.GetVendorPriceByItemID then
			local ok, price = pcall(api.GetVendorPriceByItemID, "SmartLoot", itemID)
			if ok and AsCopper(price) then
				return true
			end
		end
		if link and api.GetVendorPriceByItemLink then
			local ok, price = pcall(api.GetVendorPriceByItemLink, "SmartLoot", link)
			if ok and AsCopper(price) then
				return true
			end
		end
	end
	if TSM_API and TSM_API.GetCustomPriceValue and itemID then
		local ok, price = pcall(TSM_API.GetCustomPriceValue, "vendorBuy", "i:" .. itemID)
		if ok and AsCopper(price) then
			return true
		end
	end
	return false
end

-- Vendor-purchased (not crafted/looted): classified trade supplies, spell
-- reagents (portal runes, ankhs, etc.), or a known merchant buy price.
function addon.IsVendorPurchased(item)
	if not item then
		return false
	end
	if addon.IsVendorTradeSupply(item) then
		return true
	end
	if addon.IsSpellReagent(item) then
		return true
	end
	return addon.HasVendorBuyPrice(item.itemID, item.link)
end

local function TooltipSaysConjured(data)
	if not data or not data.lines then
		return false
	end
	local marker = ITEM_CONJURED
	if type(marker) ~= "string" or marker == "" then
		return false
	end
	for index = 1, #data.lines do
		local line = data.lines[index]
		if line and line.leftText == marker then
			return true
		end
	end
	return false
end

function addon.DetectConjured(item)
	if not item then
		return false
	end
	if not C_TooltipInfo then
		return item.conjured and true or false
	end
	if item.link and C_TooltipInfo.GetHyperlink then
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, item.link)
		if ok and TooltipSaysConjured(data) then
			return true
		end
	end
	if item.itemID and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, item.itemID)
		if ok and TooltipSaysConjured(data) then
			return true
		end
	end
	if item.bag ~= nil and item.slot and C_TooltipInfo.GetBagItem then
		local ok, data = pcall(C_TooltipInfo.GetBagItem, item.bag, item.slot)
		if ok and TooltipSaysConjured(data) then
			return true
		end
	end
	return false
end

function addon.GetAuctionPrice(itemID)
	if not itemID then
		return nil
	end
	if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
		local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "SmartLoot", itemID)
		local copper = AsCopper(ok and price or nil)
		if copper then
			return copper
		end
	end
	if TSM_API and TSM_API.GetCustomPriceValue then
		local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
		local copper = AsCopper(ok and price or nil)
		if copper then
			return copper
		end
	end
	return nil
end

-- item may be a table with classID/subclassID/itemID/link for vendor checks.
function addon.GetUnitPrice(itemID, sellPrice, quality, item)
	sellPrice = sellPrice or 0
	if quality == 0 then
		return sellPrice
	end
	if item and addon.IsVendorPurchased(item) then
		return sellPrice
	end
	if addon.db and addon.db.useAuctionValue then
		local auction = addon.GetAuctionPrice(itemID)
		if auction then
			return auction
		end
	end
	return sellPrice
end

function addon.ReadItemData(item)
	local query = item.link or item.itemID
	if not query or not C_Item or not C_Item.GetItemInfo then
		return false
	end
	local ok, name, link, quality, _, _, _, _, maxStack, equipLoc, texture, sellPrice, classID, subclassID, bindType, _, _, isReagent = pcall(C_Item.GetItemInfo, query)
	if not ok or not name then
		return false
	end

	item.name = name
	item.link = link or item.link
	item.quality = quality
	item.maxStack = maxStack or 1
	item.equipLoc = equipLoc or ""
	item.texture = texture or item.texture
	item.classID = classID
	item.subclassID = subclassID
	item.bindType = bindType or 0
	item.isReagent = isReagent and true or false

	local questClass = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
	local questBind = Enum and Enum.ItemBind and Enum.ItemBind.Quest or 4
	if item.bindType == questBind or item.classID == questClass then
		item.isQuest = true
	end

	item.itemFamily = 0
	if C_Item.GetItemFamily then
		local familyOk, family = pcall(C_Item.GetItemFamily, query)
		if familyOk and family then
			item.itemFamily = family
		end
	end

	local account = false
	if C_Item.IsItemBindToAccount then
		local boundOk, bound = pcall(C_Item.IsItemBindToAccount, query)
		account = boundOk and bound or false
	end
	if not account and C_Item.IsItemBindToAccountUntilEquip then
		local boundOk, bound = pcall(C_Item.IsItemBindToAccountUntilEquip, query)
		account = boundOk and bound or false
	end
	local accountBind = Enum and Enum.ItemBind
	if accountBind then
		if bindType == accountBind.ToWoWAccount or bindType == accountBind.ToBnetAccount or bindType == accountBind.ToBnetAccountUntilEquipped then
			account = true
		end
	elseif bindType == 7 or bindType == 8 or bindType == 9 then
		account = true
	end
	item.isAccountBound = account
	item.conjured = addon.DetectConjured(item)
	item.unitPrice = addon.GetUnitPrice(item.itemID, sellPrice or 0, quality, item)
	if not item.openable and C_Item.GetItemSpell then
		local spellOk, spellName = pcall(C_Item.GetItemSpell, query)
		if spellOk and type(spellName) == "string" then
			local lowerName = spellName:lower()
			if lowerName == "open" or lowerName == "opening" or lowerName:sub(1, 5) == "open " then
				item.openable = true
			end
		end
	end
	return true
end

function addon.CopyItemFields(target, info)
	if not info then
		return
	end
	if info.name then target.name = info.name end
	if info.link then target.link = info.link end
	if info.quality ~= nil then target.quality = info.quality end
	if info.maxStack then target.maxStack = info.maxStack end
	if info.equipLoc ~= nil then target.equipLoc = info.equipLoc end
	if info.texture and not target.texture then target.texture = info.texture end
	if info.classID ~= nil then target.classID = info.classID end
	if info.subclassID ~= nil then target.subclassID = info.subclassID end
	if info.bindType ~= nil then target.bindType = info.bindType end
	if info.isReagent ~= nil then target.isReagent = info.isReagent and true or false end
	if info.isQuest then target.isQuest = true end
	if info.isAccountBound then target.isAccountBound = true end
	if info.conjured then target.conjured = true end
	if info.itemFamily ~= nil then target.itemFamily = info.itemFamily end
	if info.unitPrice ~= nil then target.unitPrice = info.unitPrice end
	if info.openable then target.openable = true end
end

function addon.WhenItemReady(itemID, link, callback)
	local info = { itemID = itemID, link = link }
	if addon.ReadItemData(info) then
		callback(info)
		return
	end
	local function Deliver()
		addon.ReadItemData(info)
		callback(info)
	end
	local item
	if Item and link and Item.CreateFromItemLink then
		item = Item:CreateFromItemLink(link)
	elseif Item and itemID and Item.CreateFromItemID then
		item = Item:CreateFromItemID(itemID)
	end
	if item and item.ContinueOnItemLoad then
		item:ContinueOnItemLoad(Deliver)
	else
		callback(info)
	end
end

function addon.ResolveItems(entries, callback)
	local pending = 0
	local scanning = true
	local finished = false

	local function Finish()
		if finished or scanning or pending > 0 then
			return
		end
		finished = true
		callback(entries)
	end

	for _, entry in ipairs(entries) do
		if entry.needsItemData then
			pending = pending + 1
			addon.WhenItemReady(entry.itemID, entry.link, function(info)
				addon.CopyItemFields(entry, info)
				pending = pending - 1
				Finish()
			end)
		end
	end

	scanning = false
	Finish()

	if C_Timer then
		C_Timer.After(0.75, function()
			if finished then
				return
			end
			scanning = false
			pending = 0
			finished = true
			callback(entries)
		end)
	end
end
