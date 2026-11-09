local addon = SmartLoot or {}
SmartLoot = addon

local QUALITY_POOR = 0
local QUALITY_COMMON = 1
local HEARTHSTONE_ITEM_ID = 6948
local SOUL_SHARD_ITEM_ID = 6265
local SOUL_FAMILY = 4

local TIER_MONEY = 1
local TIER_QUEST = 2
local TIER_ACCOUNT = 3
local TIER_BOP = 4
local TIER_BOE = 5
local TIER_VALUE = 6

local BIND_ON_ACQUIRE = 1
local BIND_ON_EQUIP = 2
local BIND_ACCOUNT = { [7] = true, [8] = true, [9] = true }

local function Band(a, b)
	if bit and bit.band then
		return bit.band(a, b)
	end
	local result = 0
	local bitValue = 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			result = result + bitValue
		end
		bitValue = bitValue * 2
		a = math.floor(a / 2)
		b = math.floor(b / 2)
	end
	return result
end

local function ShallowCopy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function CopyMap(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function CopyArray(source)
	local copy = {}
	for index, value in ipairs(source) do
		copy[index] = value
	end
	return copy
end

function addon.ItemValue(item)
	return (item.unitPrice or 0) * (item.count or 1)
end

function addon.IsHearthstone(item)
	return item and item.itemID == HEARTHSTONE_ITEM_ID
end

function addon.IsSoulShard(item)
	if not item then
		return false
	end
	if item.itemID == SOUL_SHARD_ITEM_ID then
		return true
	end
	return Band(item.itemFamily or 0, SOUL_FAMILY) ~= 0
end

-- Warlock summoned stones and similar: no vendor value, always kept.
function addon.IsSummonedKeep(item)
	if not item or addon.IsSoulShard(item) then
		return false
	end
	local name = item.name
	if type(name) ~= "string" then
		return false
	end
	local lower = string.lower(name)
	if string.find(lower, "healthstone", 1, true)
		or string.find(lower, "soulstone", 1, true)
		or string.find(lower, "firestone", 1, true)
		or string.find(lower, "spellstone", 1, true) then
		return true
	end
	return false
end

local CLASS_WEAPON = 2
local CLASS_PROFESSION = 19
local WEAPON_MISCELLANEOUS = 14
local WEAPON_FISHING_POLE = 20

function addon.IsProfessionTool(item)
	if not item then
		return false
	end
	local equipLoc = item.equipLoc
	if equipLoc == "INVTYPE_PROFESSION_TOOL" or equipLoc == "INVTYPE_PROFESSION_GEAR" then
		return true
	end
	if item.classID == CLASS_PROFESSION then
		return true
	end
	if item.classID == CLASS_WEAPON and (item.subclassID == WEAPON_FISHING_POLE or item.subclassID == WEAPON_MISCELLANEOUS) then
		return true
	end
	return false
end

function addon.IsGear(item)
	local equipLoc = item.equipLoc
	return equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- Bag items auto-destroy may spend: quality at or under the Options cap, and
-- not a keep (hearthstone, tools, reagents, quest, protected, keepable gear).
function addon.IsAutoDestroyCandidate(item)
	if not item or item.locked then
		return false
	end
	local maxQuality = 0
	if addon.db then
		maxQuality = addon.db.autoDestroyMaxQuality or 0
	end
	if (item.quality or 0) > maxQuality then
		return false
	end
	if item.isQuest or item.protected then
		return false
	end
	if addon.IsHearthstone(item) or addon.IsProfessionTool(item) then
		return false
	end
	if addon.IsSummonedKeep(item) or addon.IsSpellReagent(item) then
		return false
	end
	if addon.IsGear(item) and (item.usable or item.keepTransmog) then
		return false
	end
	if addon.IsSoulShard(item) and Band(item.bagFamily or 0, SOUL_FAMILY) ~= 0 then
		return false
	end
	return true
end

function addon.LootTier(item)
	if item.locked then
		return nil
	end
	if item.lootType == "money" or item.lootType == "currency" then
		return TIER_MONEY
	end
	if item.isQuest then
		return TIER_QUEST
	end
	local gear = addon.IsGear(item)
	if gear and (item.isAccountBound or BIND_ACCOUNT[item.bindType]) then
		return TIER_ACCOUNT
	end
	if gear and item.bindType == BIND_ON_ACQUIRE then
		return TIER_BOP
	end
	if gear and item.bindType == BIND_ON_EQUIP then
		return TIER_BOE
	end
	return TIER_VALUE
end

function addon.LootReason(item)
	local tier = item.tier or addon.LootTier(item)
	if tier == TIER_MONEY then
		return item.lootType == "currency" and "Currency" or "Money"
	elseif tier == TIER_QUEST then
		return "Quest"
	elseif tier == TIER_ACCOUNT then
		return "BoA"
	elseif tier == TIER_BOP then
		return "BoP"
	elseif tier == TIER_BOE then
		return "BoE"
	end
	return "Value"
end

local REAGENT_BAG = -1
local TRADE_GOODS = 7
-- Profession bag family -> trade-goods subclass, used when the item itself has no family bit.
local FAMILY_TRADE_SUBCLASS = {
	[8] = 6, -- leatherworking / skinning
	[32] = 9, -- herb
	[64] = 12, -- enchanting
	[512] = 4, -- gem
	[1024] = 7, -- mining
}

function addon.SlotFits(slotFamily, item)
	slotFamily = slotFamily or 0
	if slotFamily == 0 then
		return true
	end
	if slotFamily == REAGENT_BAG then
		return type(item) == "table" and item.isReagent and true or false
	end
	local itemFamily = 0
	local classID, subclassID
	if type(item) == "number" then
		itemFamily = item
	elseif item then
		itemFamily = item.itemFamily or 0
		classID = item.classID
		subclassID = item.subclassID
	end
	if itemFamily ~= 0 and Band(itemFamily, slotFamily) ~= 0 then
		return true
	end
	local tradeSubclass = FAMILY_TRADE_SUBCLASS[slotFamily]
	if tradeSubclass and classID == TRADE_GOODS and subclassID == tradeSubclass then
		return true
	end
	return false
end

local function SortRank(item)
	if item.lootType == "money" or item.lootType == "currency" then
		return 0
	end
	if item.neededForQuest then
		return 1
	end
	return 2
end

local function SortLoot(left, right)
	local leftRank = SortRank(left)
	local rightRank = SortRank(right)
	if leftRank ~= rightRank then
		return leftRank < rightRank
	end
	if left.tier ~= right.tier then
		return left.tier < right.tier
	end
	if left.value ~= right.value then
		return left.value > right.value
	end
	return (left.slot or 0) < (right.slot or 0)
end

-- Poor junk first, then Common, then better. Cheapest coin within a quality.
function addon.SortDestroyCandidate(left, right)
	local leftQuality = left.quality or 0
	local rightQuality = right.quality or 0
	if leftQuality ~= rightQuality then
		return leftQuality < rightQuality
	end
	local leftValue = left.value or 0
	local rightValue = right.value or 0
	if leftValue ~= rightValue then
		return leftValue < rightValue
	end
	if (left.bag or 0) ~= (right.bag or 0) then
		return (left.bag or 0) < (right.bag or 0)
	end
	return (left.slot or 0) < (right.slot or 0)
end

local function BuildSoulState(bagItems, freeSlots, options)
	local keep = tonumber(options.keepSoulShards)
	if not keep or keep < 0 then
		keep = 0
	end
	keep = math.floor(keep)

	local total = 0
	local shardMax = 1
	local soulSlots = 0
	for _, family in ipairs(freeSlots) do
		if Band(family or 0, SOUL_FAMILY) ~= 0 then
			soulSlots = soulSlots + 1
		end
	end
	for _, item in ipairs(bagItems) do
		if Band(item.bagFamily or 0, SOUL_FAMILY) ~= 0 then
			soulSlots = soulSlots + 1
		end
		if addon.IsSoulShard(item) then
			total = total + (item.count or 1)
			local maxStack = item.maxStack or 1
			if maxStack > shardMax then
				shardMax = maxStack
			end
		end
	end

	return {
		keep = keep,
		remaining = total,
		capacity = soulSlots * shardMax,
	}
end

local function IsSoulShardNeeded(item, soul)
	-- Never destroy shards that already sit in a soul bag.
	if Band(item.bagFamily or 0, SOUL_FAMILY) ~= 0 then
		return true
	end
	local floor = soul.keep
	if soul.capacity > floor then
		floor = soul.capacity
	end
	return soul.remaining <= floor
end

-- Kept in the bag: protected, hearthstone, profession tools, bag quest items,
-- summoned stones, soul shards under keep/capacity rules, stacks still needed
-- for corpse loot, skipped openables, and crafting mats when that option is on
-- (trade-goods Parts / Other stay eligible by subclass).
local function IsNeededItem(item, options, neededItemIDs, soul)
	if item.isQuest or item.protected or addon.IsHearthstone(item) or addon.IsProfessionTool(item) then
		return true
	end
	if addon.IsSummonedKeep(item) or addon.IsSpellReagent(item) then
		return true
	end
	if addon.IsSoulShard(item) then
		return IsSoulShardNeeded(item, soul)
	end
	if options.protectReagents and item.isReagent then
		-- Vendor trade supplies (Parts / Other) stay eligible; other reagents stay.
		if not (addon.IsVendorTradeSupply and addon.IsVendorTradeSupply(item)) then
			return true
		end
	end
	if item.itemID and neededItemIDs[item.itemID] then
		return true
	end
	if options.skipBag ~= nil and item.bag == options.skipBag and item.slot == options.skipSlot then
		return true
	end
	if options.skipSlots and item.bag ~= nil and item.slot ~= nil and options.skipSlots[item.bag .. ":" .. item.slot] then
		return true
	end
	return false
end

-- Usable / transmog keeps apply only to equippable gear.
local function IsKeepableGear(item)
	return addon.IsGear(item) and (item.usable or item.keepTransmog) and true or false
end

local function TakeFreeSlot(slots, item)
	for index, family in ipairs(slots) do
		if addon.SlotFits(family, item) then
			table.remove(slots, index)
			return true
		end
	end
	return false
end

local function TryPlace(item, stacks, slots)
	if item.lootType == "money" or item.lootType == "currency" then
		return stacks, slots
	end

	local newStacks = CopyMap(stacks)
	local newSlots = CopyArray(slots)
	local remaining = item.count or 1
	if remaining < 1 then
		remaining = 1
	end
	local maxStack = item.maxStack or 1
	if maxStack < 1 then
		maxStack = 1
	end

	if item.itemID and newStacks[item.itemID] and newStacks[item.itemID] > 0 then
		local used = math.min(newStacks[item.itemID], remaining)
		newStacks[item.itemID] = newStacks[item.itemID] - used
		remaining = remaining - used
	end

	while remaining > 0 do
		if not TakeFreeSlot(newSlots, item) then
			return nil
		end
		local placed = math.min(maxStack, remaining)
		remaining = remaining - placed
		local leftover = maxStack - placed
		if item.itemID and leftover > 0 then
			newStacks[item.itemID] = (newStacks[item.itemID] or 0) + leftover
		end
	end

	return newStacks, newSlots
end

function addon.BuildPlan(lootItems, bagItems, freeSlots, options)
	options = options or {}
	lootItems = lootItems or {}
	bagItems = bagItems or {}
	freeSlots = freeSlots or {}

	local neededItemIDs = {}
	local ranked = {}
	for _, item in ipairs(lootItems) do
		local tier = addon.LootTier(item)
		if tier then
			local copy = ShallowCopy(item)
			copy.tier = tier
			copy.value = addon.ItemValue(item)
			copy.reason = addon.LootReason(copy)
			ranked[#ranked + 1] = copy
			if copy.itemID and copy.lootType ~= "money" and copy.lootType ~= "currency" then
				neededItemIDs[copy.itemID] = true
			end
		end
	end
	table.sort(ranked, SortLoot)

	local stacks = {}
	for _, item in ipairs(bagItems) do
		if item.itemID and not item.locked then
			local room = (item.maxStack or 1) - (item.count or 1)
			if room > 0 then
				stacks[item.itemID] = (stacks[item.itemID] or 0) + room
			end
		end
	end

	local slots = CopyArray(freeSlots)
	-- Poor junk first, then cheaper coin within the same quality.
	local pool = {}
	for _, item in ipairs(bagItems) do
		if not item.locked then
			local copy = ShallowCopy(item)
			copy.value = addon.ItemValue(item)
			pool[#pool + 1] = copy
		end
	end
	table.sort(pool, addon.SortDestroyCandidate)

	local soul = BuildSoulState(bagItems, freeSlots, options)

	local function ConsumeCandidate(chosen)
		if addon.IsSoulShard(chosen) then
			soul.remaining = soul.remaining - (chosen.count or 1)
		end
	end

	local consumed = {}
	local function LowestSacrifice(item, consumedMap)
		local function Cheapest(openableOnly, skipOpenable)
			local bestIndex
			local bestValue
			local bestQuality
			for index, candidate in ipairs(pool) do
				local openable = candidate.openable and true or false
				if not consumedMap[index]
					and not IsNeededItem(candidate, options, neededItemIDs, soul)
					and addon.SlotFits(candidate.bagFamily or 0, item)
					and (not openableOnly or openable)
					and not (skipOpenable and openable) then
					local value = candidate.value or 0
					local quality = candidate.quality or 0
					if not bestIndex or value < bestValue or (value == bestValue and quality < bestQuality) then
						bestIndex = index
						bestValue = value
						bestQuality = quality
					end
				end
			end
			return bestIndex
		end

		local bestIndex
		if options.preferOpenable then
			bestIndex = Cheapest(true, false)
		end
		if not bestIndex and options.avoidOpenable then
			bestIndex = Cheapest(false, true)
		end
		if not bestIndex then
			bestIndex = Cheapest(false, false)
		end
		if not bestIndex then
			return nil
		end
		consumedMap[bestIndex] = true
		local chosen = pool[bestIndex]
		ConsumeCandidate(chosen)
		if chosen.openable and not options.avoidOpenable then
			chosen.openInstead = true
		else
			chosen.forQuest = true
		end
		return chosen
	end

	-- Regular loot: cheapest Poor junk, then cheaper Common or better.
	local function CanRegularDelete(candidate)
		if IsNeededItem(candidate, options, neededItemIDs, soul) then
			return false
		end
		if candidate.openable then
			return true
		end
		if IsKeepableGear(candidate) then
			return false
		end
		return true
	end

	local function NextAffordable(item, consumedMap, cost)
		if item.neededForQuest then
			return LowestSacrifice(item, consumedMap)
		end
		for index, candidate in ipairs(pool) do
			local candidateValue = candidate.value or 0
			if not consumedMap[index]
				and CanRegularDelete(candidate)
				and addon.SlotFits(candidate.bagFamily or 0, item)
				and item.value > cost + candidateValue then
				consumedMap[index] = true
				ConsumeCandidate(candidate)
				if candidate.openable then
					candidate.openInstead = true
				end
				return candidate
			end
		end
		return nil
	end

	local function HasEligibleDestroy(item, consumedMap)
		for index, candidate in ipairs(pool) do
			if not consumedMap[index] and addon.SlotFits(candidate.bagFamily or 0, item) then
				if item.neededForQuest then
					if not IsNeededItem(candidate, options, neededItemIDs, soul) then
						return true
					end
				elseif CanRegularDelete(candidate) then
					return true
				end
			end
		end
		return false
	end

	local function NextOpenable(item, consumedMap)
		for index, candidate in ipairs(pool) do
			if not consumedMap[index]
				and candidate.openable
				and not IsNeededItem(candidate, options, neededItemIDs, soul)
				and addon.SlotFits(candidate.bagFamily or 0, item) then
				consumedMap[index] = true
				ConsumeCandidate(candidate)
				candidate.openInstead = true
				return candidate
			end
		end
		return nil
	end

	local immediate = {}
	local pending = {}
	for _, item in ipairs(ranked) do
		local newStacks, newSlots = TryPlace(item, stacks, slots)
		if newStacks then
			stacks = newStacks
			slots = newSlots
			immediate[#immediate + 1] = item
		else
			pending[#pending + 1] = item
		end
	end

	local takes = {}
	local sacrifices = {}
	local steps = {}
	local leftBehind = {}
	for _, item in ipairs(pending) do
		local trialStacks = stacks
		local trialSlots = CopyArray(slots)
		local trialConsumed = CopyMap(consumed)
		local soulBefore = soul.remaining
		local added = {}
		local cost = 0
		local done = false
		while not done do
			local newStacks, newSlots = TryPlace(item, trialStacks, trialSlots)
			if newStacks then
				stacks = newStacks
				slots = newSlots
				consumed = trialConsumed
				local stepSacrifices = {}
				for _, candidate in ipairs(added) do
					sacrifices[#sacrifices + 1] = candidate
					stepSacrifices[#stepSacrifices + 1] = candidate
				end
				takes[#takes + 1] = item
				steps[#steps + 1] = {
					take = item,
					sacrifices = stepSacrifices,
				}
				done = true
			else
				local candidate = NextAffordable(item, trialConsumed, cost)
				if not candidate then
					candidate = NextOpenable(item, trialConsumed)
				end
				if not candidate then
					soul.remaining = soulBefore
					if cost > 0 or HasEligibleDestroy(item, trialConsumed) then
						item.skipReason = "Low value"
					else
						item.skipReason = "No junk"
					end
					leftBehind[#leftBehind + 1] = item
					done = true
				else
					cost = cost + (candidate.value or 0)
					added[#added + 1] = candidate
					trialSlots[#trialSlots + 1] = candidate.bagFamily or 0
				end
			end
		end
	end

	return {
		immediate = immediate,
		takes = takes,
		sacrifices = sacrifices,
		steps = steps,
		leftBehind = leftBehind,
	}
end
