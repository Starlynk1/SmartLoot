SmartLoot = {}
dofile("Loot/Value.lua")
dofile("Loot/Junk.lua")
dofile("Loot/Priority.lua")

local checks = 0

local function Expect(name, condition)
	checks = checks + 1
	if not condition then
		error("failed: " .. name)
	end
end

local function Names(list)
	local out = {}
	for index, item in ipairs(list) do
		out[index] = item.name
	end
	return table.concat(out, ",")
end

local function Plan(loot, bags, freeSlots, options)
	return SmartLoot.BuildPlan(loot, bags, freeSlots, options or { protectReagents = true })
end

do
	local plan = Plan({
		{ name = "Junk", slot = 1, lootType = "item", unitPrice = 5000, count = 1, maxStack = 1, equipLoc = "" },
		{ name = "Quest", slot = 2, lootType = "item", isQuest = true, unitPrice = 0, count = 1, maxStack = 1, equipLoc = "" },
		{ name = "BoA Helm", slot = 3, lootType = "item", isAccountBound = true, equipLoc = "INVTYPE_HEAD", unitPrice = 100, count = 1, maxStack = 1 },
		{ name = "BoP Sword", slot = 4, lootType = "item", bindType = 1, equipLoc = "INVTYPE_WEAPON", unitPrice = 50, count = 1, maxStack = 1 },
		{ name = "BoE Recipe", slot = 5, lootType = "item", bindType = 2, equipLoc = "", unitPrice = 99999, count = 1, maxStack = 1 },
	}, {}, { 0, 0, 0, 0, 0 })
	Expect("rank order", Names(plan.immediate) == "Quest,BoA Helm,BoP Sword,BoE Recipe,Junk")
	Expect("everything fits", #plan.takes == 0 and #plan.sacrifices == 0 and #plan.leftBehind == 0)
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, itemFamily = 0, unitPrice = 100 },
	}, {
		{ name = "Grey Expensive", bag = 0, slot = 1, itemID = 1, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
		{ name = "Grey Cheap", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
		{ name = "White Cheap", bag = 0, slot = 3, itemID = 3, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, usable = true, equipLoc = "INVTYPE_WEAPON" },
		{ name = "Green", bag = 0, slot = 4, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, keepTransmog = true, equipLoc = "INVTYPE_CHEST" },
		{ name = "Cloth", bag = 0, slot = 5, itemID = 5, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, isReagent = true, classID = 7, subclassID = 5 },
	}, {})
	Expect("cheapest grey first", Names(plan.sacrifices) == "Grey Cheap")
	Expect("green stays", plan.sacrifices[1].name ~= "Green")
	Expect("reagent stays", plan.sacrifices[1].name ~= "Cloth")
	Expect("sword is taken", Names(plan.takes) == "Sword")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey Junk", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0 },
		{ name = "Tough Jerky", bag = 0, slot = 2, itemID = 117, quality = 1, count = 1, maxStack = 20, unitPrice = 1, bagFamily = 0, classID = 0, subclassID = 0 },
		{ name = "Refreshing Spring Water", bag = 0, slot = 3, itemID = 159, quality = 1, count = 1, maxStack = 20, unitPrice = 1, bagFamily = 0, classID = 0, subclassID = 5 },
	}, {})
	Expect("junk is deleted before cheap food and water", Names(plan.sacrifices) == "Grey Junk")
end

do
	SmartLoot.db = { junkSource = "rxpguides" }
	function SmartLoot.IsRXPJunk(item)
		return item.name == "Marked White"
	end
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey Junk", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0 },
		{ name = "Marked White", bag = 0, slot = 2, itemID = 118, quality = 1, count = 1, maxStack = 20, unitPrice = 80, bagFamily = 0 },
		{ name = "Tough Jerky", bag = 0, slot = 3, itemID = 117, quality = 1, count = 1, maxStack = 20, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("RestedXP marked junk is deleted before unmarked food", Names(plan.sacrifices) == "Marked White")
	SmartLoot.IsRXPJunk = nil
	SmartLoot.db = nil
end

do
	SmartLoot.db = { junkSource = "baganator" }
	function SmartLoot.IsBaganatorJunk(item)
		return item.name == "Bag Junk"
	end
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey Junk", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0 },
		{ name = "Bag Junk", bag = 0, slot = 2, itemID = 119, quality = 1, count = 1, maxStack = 20, unitPrice = 80, bagFamily = 0 },
		{ name = "Tough Jerky", bag = 0, slot = 3, itemID = 117, quality = 1, count = 1, maxStack = 20, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("Baganator marked junk is deleted before unmarked food", Names(plan.sacrifices) == "Bag Junk")
	SmartLoot.IsBaganatorJunk = nil
	SmartLoot.db = nil
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 10 },
	}, {
		{ name = "Hearthstone", bag = 0, slot = 1, itemID = 6948, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0 },
		{ name = "White Cheap", bag = 0, slot = 2, itemID = 3, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("hearthstone is never deleted", Names(plan.sacrifices) == "White Cheap")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1 },
	}, {
		{ name = "Hearthstone", bag = 0, slot = 1, itemID = 6948, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0 },
	}, {})
	Expect("hearthstone alone is not a sacrifice", #plan.sacrifices == 0)
	Expect("loot stays when only the hearthstone can be removed", Names(plan.leftBehind) == "Sword")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1 },
	}, {
		{ name = "Green", bag = 0, slot = 1, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0 },
		{ name = "Cloth", bag = 0, slot = 2, itemID = 5, quality = 1, count = 20, maxStack = 20, unitPrice = 1, bagFamily = 0, isReagent = true, protected = true },
	}, {})
	Expect("nothing eligible to delete", #plan.sacrifices == 0)
	Expect("sword stays on the corpse", Names(plan.leftBehind) == "Sword")
end

do
	local plan = Plan({
		{ name = "Cloth", slot = 1, lootType = "item", itemID = 123, count = 5, maxStack = 20 },
	}, {
		{ name = "Cloth Stack", bag = 0, slot = 1, itemID = 123, quality = 0, count = 15, maxStack = 20, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("stack room avoids a delete", #plan.sacrifices == 0 and #plan.takes == 0 and Names(plan.immediate) == "Cloth")
end

do
	local plan = Plan({
		{ name = "More Cloth", slot = 1, lootType = "item", itemID = 123, count = 1, maxStack = 20 },
	}, {
		{ name = "Full Cloth", bag = 0, slot = 1, itemID = 123, quality = 0, count = 20, maxStack = 20, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("same item is not deleted to loot itself", #plan.sacrifices == 0)
	Expect("full stack leaves the loot", Names(plan.leftBehind) == "More Cloth")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, itemFamily = 0, unitPrice = 100 },
	}, {
		{ name = "Herb Grey", bag = 1, slot = 1, itemID = 8, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 32 },
		{ name = "Normal Grey", bag = 0, slot = 1, itemID = 9, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0 },
	}, { 32 })
	Expect("herb slot is not used for a sword", Names(plan.sacrifices) == "Normal Grey")
	Expect("sword taken after a normal slot is freed", Names(plan.takes) == "Sword")
end

do
	local plan = Plan({
		{ name = "Coins", slot = 1, lootType = "money" },
		{ name = "Sword", slot = 2, lootType = "item", itemID = 10, count = 1, maxStack = 1 },
	}, {}, { 0 })
	Expect("money does not spend the bag slot", Names(plan.immediate) == "Coins,Sword" and #plan.takes == 0 and #plan.leftBehind == 0)
end

do
	local plan = Plan({
		{ name = "Locked", slot = 1, lootType = "item", locked = true, isQuest = true },
		{ name = "BoE Helm", slot = 2, lootType = "item", bindType = 2, equipLoc = "INVTYPE_HEAD", unitPrice = 10, count = 1, maxStack = 1 },
		{ name = "Rich White", slot = 3, lootType = "item", unitPrice = 9999, count = 1, maxStack = 1, equipLoc = "" },
	}, {}, { 0, 0 })
	Expect("locked loot is ignored", Names(plan.immediate) == "BoE Helm,Rich White" and #plan.takes == 0)
end

do
	local plan = Plan({
		{ name = "Coins", slot = 1, lootType = "money" },
		{ name = "Cloth", slot = 2, lootType = "item", itemID = 123, count = 5, maxStack = 20 },
		{ name = "Sword", slot = 3, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 10 },
	}, {
		{ name = "Cloth Stack", bag = 0, slot = 1, itemID = 123, quality = 0, count = 10, maxStack = 20, unitPrice = 1, bagFamily = 0 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {})
	Expect("money and stacks loot without a decision", Names(plan.immediate) == "Coins,Cloth")
	Expect("only the item that needs room waits", Names(plan.takes) == "Sword" and Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 50 },
	}, {
		{ name = "Grey Cheap", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0, protected = true },
		{ name = "Grey Other", bag = 0, slot = 2, itemID = 9, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
	}, {})
	Expect("protected junk is replaced", Names(plan.sacrifices) == "Grey Other" and Names(plan.takes) == "Sword")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, itemFamily = 0, classID = 2, subclassID = 7 },
	}, {
		{ name = "Ruined Leather", bag = 1, slot = 1, itemID = 30, quality = 0, count = 5, maxStack = 10, unitPrice = 1, bagFamily = 8, itemFamily = 8, classID = 7, subclassID = 6 },
	}, {})
	Expect("skinning bag is not emptied for a sword", #plan.sacrifices == 0)
	Expect("sword stays when only a skinning slot can be freed", Names(plan.leftBehind) == "Sword")
end

do
	local plan = Plan({
		{ name = "Light Leather", slot = 1, lootType = "item", itemID = 31, count = 1, maxStack = 10, itemFamily = 8, classID = 7, subclassID = 6, unitPrice = 10 },
	}, {
		{ name = "Ruined Scraps", bag = 1, slot = 1, itemID = 32, quality = 0, count = 1, maxStack = 10, unitPrice = 1, bagFamily = 8, itemFamily = 8 },
		{ name = "Bag Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0 },
	}, {})
	Expect("skinning loot deletes from the skinning bag", Names(plan.sacrifices) == "Ruined Scraps")
end

do
	local plan = Plan({
		{ name = "Skin", slot = 1, lootType = "item", itemID = 33, count = 1, maxStack = 10, itemFamily = 0, classID = 7, subclassID = 6, unitPrice = 10 },
	}, {
		{ name = "Old Skin", bag = 1, slot = 1, itemID = 34, quality = 0, count = 1, maxStack = 10, unitPrice = 1, bagFamily = 8, itemFamily = 0, classID = 7, subclassID = 6 },
	}, {})
	Expect("leather still fits a skinning bag without a family bit", Names(plan.takes) == "Skin")
end

do
	local plan = Plan({
		{ name = "White Loot", slot = 1, lootType = "item", itemID = 40, quality = 1, count = 1, maxStack = 1, unitPrice = 4 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("common below the delete value stays", Names(plan.leftBehind) == "White Loot" and #plan.sacrifices == 0 and #plan.takes == 0)
	Expect("cheap loot is marked low value", plan.leftBehind[1].skipReason == "Low value")
end

do
	local plan = Plan({
		{ name = "Green Loot", slot = 1, lootType = "item", itemID = 41, quality = 2, count = 1, maxStack = 1, unitPrice = 4 },
		{ name = "BoE Helm", slot = 2, lootType = "item", itemID = 42, quality = 2, bindType = 2, equipLoc = "INVTYPE_HEAD", count = 1, maxStack = 1, unitPrice = 4 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
		{ name = "White", bag = 0, slot = 2, itemID = 3, quality = 1, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("higher tier below the delete value stays", Names(plan.leftBehind) == "BoE Helm,Green Loot" and #plan.sacrifices == 0)
end

do
	local plan = Plan({
		{ name = "White Loot", slot = 1, lootType = "item", itemID = 43, quality = 1, count = 1, maxStack = 1, unitPrice = 30 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("common above the delete value is taken", Names(plan.takes) == "White Loot" and Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Modest", slot = 1, lootType = "item", itemID = 44, quality = 1, count = 1, maxStack = 1, unitPrice = 10 },
	}, {
		{ name = "Grey Expensive", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
		{ name = "White Cheap", bag = 0, slot = 2, itemID = 3, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("unaffordable grey is skipped for a cheaper white", Names(plan.sacrifices) == "White Cheap" and Names(plan.takes) == "Modest")
end

do
	local plan = Plan({
		{ name = "Pair", slot = 1, lootType = "item", itemID = 45, count = 2, maxStack = 1, unitPrice = 5 },
	}, {
		{ name = "Grey A", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 6, bagFamily = 0 },
		{ name = "Grey B", bag = 0, slot = 2, itemID = 3, quality = 0, count = 1, maxStack = 1, unitPrice = 6, bagFamily = 0 },
	}, {})
	Expect("two deletes that cost more than the loot are refused", Names(plan.leftBehind) == "Pair" and #plan.sacrifices == 0)
end

do
	local plan = Plan({
		{ name = "Pair", slot = 1, lootType = "item", itemID = 46, count = 2, maxStack = 1, unitPrice = 10 },
	}, {
		{ name = "Grey A", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 6, bagFamily = 0 },
		{ name = "Grey B", bag = 0, slot = 2, itemID = 3, quality = 0, count = 1, maxStack = 1, unitPrice = 6, bagFamily = 0 },
	}, {})
	Expect("two deletes are used when the loot is still ahead", Names(plan.takes) == "Pair" and Names(plan.sacrifices) == "Grey A,Grey B")
	Expect("pair step groups both deletes under one take", #plan.steps == 1 and plan.steps[1].take.name == "Pair" and Names(plan.steps[1].sacrifices) == "Grey A,Grey B")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 80, count = 1, maxStack = 1, unitPrice = 50 },
		{ name = "Helm", slot = 2, lootType = "item", itemID = 81, count = 1, maxStack = 1, unitPrice = 40 },
	}, {
		{ name = "Grey A", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
		{ name = "Grey B", bag = 0, slot = 2, itemID = 3, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {})
	Expect("two loot items become two steps", #plan.steps == 2 and plan.steps[1].take.name == "Sword" and plan.steps[2].take.name == "Helm")
	Expect("each step has its own destroy", Names(plan.steps[1].sacrifices) == "Grey A" and Names(plan.steps[2].sacrifices) == "Grey B")
end

do
	local plan = Plan({
		{ name = "BoP Sword", slot = 1, lootType = "item", itemID = 47, bindType = 1, equipLoc = "INVTYPE_WEAPON", count = 1, maxStack = 1, unitPrice = 1 },
		{ name = "Rich Junk", slot = 2, lootType = "item", itemID = 48, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("a failed higher tier leaves the junk for a better gain", Names(plan.leftBehind) == "BoP Sword" and Names(plan.takes) == "Rich Junk" and Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Match", slot = 1, lootType = "item", itemID = 49, count = 1, maxStack = 1, unitPrice = 10 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("equal coin is not a gain", Names(plan.leftBehind) == "Match" and #plan.sacrifices == 0)
end

do
	local plan = Plan({
		{ name = "Quest Drop", slot = 1, lootType = "item", isQuest = true, unitPrice = 0, count = 1, maxStack = 1 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("inactive quest item still needs a coin gain", Names(plan.leftBehind) == "Quest Drop" and #plan.sacrifices == 0)
end

do
	local plan = Plan({
		{ name = "Needed Quest", slot = 2, lootType = "item", isQuest = true, neededForQuest = true, unitPrice = 0, count = 1, maxStack = 1 },
		{ name = "Rich White", slot = 1, lootType = "item", unitPrice = 500, count = 1, maxStack = 1 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
	}, {})
	Expect("active quest item is taken despite the delete value", Names(plan.takes) == "Needed Quest" and Names(plan.sacrifices) == "Grey")
	Expect("richer loot waits when the quest item used the only delete", Names(plan.leftBehind) == "Rich White")
end

do
	local plan = Plan({
		{ name = "Needed Quest", slot = 1, lootType = "item", isQuest = true, neededForQuest = true, unitPrice = 0, count = 1, maxStack = 1, itemFamily = 0 },
	}, {
		{ name = "Grey Expensive", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
		{ name = "White Cheap", bag = 0, slot = 2, itemID = 3, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
		{ name = "Skinning Grey", bag = 1, slot = 1, itemID = 8, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 32, itemFamily = 32 },
	}, {})
	Expect("active quest item deletes the cheapest usable item", Names(plan.sacrifices) == "White Cheap" and Names(plan.takes) == "Needed Quest")
end

do
	local plan = Plan({
		{ name = "Needed Quest", slot = 1, lootType = "item", isQuest = true, neededForQuest = true, unitPrice = 0, count = 1, maxStack = 1 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
		{ name = "Green Cheap", bag = 0, slot = 2, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {})
	Expect("quest item deletes the cheapest item of any quality", Names(plan.sacrifices) == "Green Cheap" and Names(plan.takes) == "Needed Quest")
end

do
	local plan = Plan({
		{ name = "Needed Quest", slot = 1, lootType = "item", isQuest = true, neededForQuest = true, unitPrice = 0, count = 1, maxStack = 1 },
	}, {
		{ name = "Fishing Pole", bag = 0, slot = 1, itemID = 6256, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, classID = 2, subclassID = 20, equipLoc = "INVTYPE_2HWEAPON" },
		{ name = "Skinning Knife", bag = 0, slot = 2, itemID = 7005, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, classID = 2, subclassID = 14, equipLoc = "INVTYPE_WEAPON" },
		{ name = "Mining Pick", bag = 0, slot = 3, itemID = 2901, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, classID = 2, subclassID = 14 },
		{ name = "Skinning Tool", bag = 0, slot = 4, itemID = 90, quality = 2, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, classID = 19, subclassID = 10, equipLoc = "INVTYPE_PROFESSION_TOOL" },
		{ name = "Grey", bag = 0, slot = 5, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0 },
	}, {})
	Expect("quest item never deletes a profession tool", Names(plan.sacrifices) == "Grey" and Names(plan.takes) == "Needed Quest")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Fishing Pole", bag = 0, slot = 1, itemID = 6256, quality = 1, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, classID = 2, subclassID = 20 },
	}, {})
	Expect("a profession tool alone is not a sacrifice", #plan.sacrifices == 0)
	Expect("loot stays when only a profession tool can be removed", Names(plan.leftBehind) == "Sword")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
		{ name = "Green Cheap", bag = 0, slot = 2, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, usable = true, equipLoc = "INVTYPE_CHEST" },
	}, {})
	Expect("usable green is kept and the grey is deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
		-- Forever: Trade Goods / Other (11).
		{ name = "Empty Vial", bag = 0, slot = 2, itemID = 3371, quality = 1, count = 1, maxStack = 20, unitPrice = 2, bagFamily = 0, classID = 7, subclassID = 11, usable = true, isReagent = true },
	}, {}, { protectReagents = true })
	Expect("grey junk is deleted before a cheaper empty vial", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Empty Vial", bag = 0, slot = 1, itemID = 3371, quality = 1, count = 1, maxStack = 20, unitPrice = 2, bagFamily = 0, classID = 7, subclassID = 11, usable = true, isReagent = true },
	}, {}, { protectReagents = true })
	Expect("trade-goods Other reagent is still destroy-eligible", Names(plan.sacrifices) == "Empty Vial")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
		{ name = "Part", bag = 0, slot = 2, itemID = 40, quality = 1, count = 1, maxStack = 20, unitPrice = 2, bagFamily = 0, classID = 7, subclassID = 1, isReagent = true },
	}, {}, { protectReagents = true })
	Expect("grey junk is deleted before a cheaper Parts reagent", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Part", bag = 0, slot = 1, itemID = 40, quality = 1, count = 1, maxStack = 20, unitPrice = 2, bagFamily = 0, classID = 7, subclassID = 1, isReagent = true },
	}, {}, { protectReagents = true })
	Expect("trade-goods Parts reagent stays destroy-eligible", Names(plan.sacrifices) == "Part")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
		{ name = "Green Cheap", bag = 0, slot = 2, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("grey junk is deleted before a cheaper unusable green", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Green Cheap", bag = 0, slot = 1, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("unusable cheaper green is still destroy-eligible", Names(plan.sacrifices) == "Green Cheap")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
		{ name = "Green Same", bag = 0, slot = 2, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 10, bagFamily = 0 },
	}, {})
	Expect("equal value still deletes the grey", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Contents", lootType = "item", count = 1, maxStack = 1, itemFamily = 0, unitPrice = 0, neededForQuest = true },
	}, {
		{ name = "Clam", bag = 0, slot = 1, itemID = 50, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, openable = true },
		{ name = "Junk", bag = 0, slot = 2, itemID = 51, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {}, { protectReagents = true, skipBag = 0, skipSlot = 1 })
	Expect("opened container is kept and another item is removed", Names(plan.sacrifices) == "Junk")
end

do
	local plan = Plan({
		{ name = "Scrap", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, itemFamily = 0, unitPrice = 10 },
	}, {
		{ name = "Clam", bag = 0, slot = 1, itemID = 50, quality = 1, count = 1, maxStack = 1, unitPrice = 100, bagFamily = 0, openable = true, usable = true },
	}, {})
	Expect("openable is offered when it is worth more than the loot", Names(plan.sacrifices) == "Clam" and Names(plan.takes) == "Scrap" and plan.sacrifices[1].openInstead)
end

do
	local plan = Plan({
		{ name = "Quest", lootType = "item", count = 1, maxStack = 1, itemFamily = 0, unitPrice = 0, neededForQuest = true },
	}, {
		{ name = "Junk", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
		{ name = "Clam", bag = 0, slot = 2, itemID = 50, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0, openable = true },
	}, {}, { protectReagents = true, preferOpenable = true })
	Expect("quest loot tries an openable before a destroy", Names(plan.sacrifices) == "Clam" and plan.sacrifices[1].openInstead)
end

do
	local plan = Plan({
		{ name = "Quest", lootType = "item", count = 1, maxStack = 1, itemFamily = 0, unitPrice = 0, neededForQuest = true },
	}, {
		{ name = "Junk", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
		{ name = "Clam", bag = 0, slot = 2, itemID = 50, quality = 0, count = 1, maxStack = 1, unitPrice = 50, bagFamily = 0, openable = true },
	}, {}, { protectReagents = true, preferOpenable = true, skipSlots = { ["0:2"] = true } })
	Expect("skipping an openable offers the next destroy", Names(plan.sacrifices) == "Junk")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 20, bagFamily = 0 },
		{ name = "Green Look", bag = 0, slot = 2, itemID = 4, quality = 2, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0, keepTransmog = true, equipLoc = "INVTYPE_CHEST" },
	}, {})
	Expect("missing transmog stays and the grey is deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Minor Healthstone", bag = 0, slot = 1, itemID = 5512, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("healthstone is never deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Rune of Portals", bag = 0, slot = 1, itemID = 17032, quality = 1, count = 1, maxStack = 10, unitPrice = 500, bagFamily = 0, classID = 15, subclassID = 1 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("misc spell reagent is never deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 1000 },
	}, {
		{ name = "Ankh", bag = 0, slot = 1, itemID = 17030, quality = 1, count = 1, maxStack = 20, unitPrice = 500, bagFamily = 0, classID = 5, subclassID = 0 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("reagent-class spell reagent is never deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard", bag = 1, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 4, itemFamily = 4 },
		{ name = "Grey", bag = 0, slot = 1, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {})
	Expect("soul bag shards are never deleted", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {}, { protectReagents = true, keepSoulShards = 0 })
	Expect("grey junk is deleted before an overflow shard", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
	}, {}, { protectReagents = true, keepSoulShards = 0 })
	Expect("overflow shard with no soul bag is still destroy-eligible", Names(plan.sacrifices) == "Soul Shard")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, {}, { protectReagents = true, keepSoulShards = 1 })
	Expect("keepSoulShards floor protects the last shards", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard Bag", bag = 1, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 4, itemFamily = 4 },
		{ name = "Soul Shard Extra", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 5, bagFamily = 0 },
	}, {}, { protectReagents = true, keepSoulShards = 0 })
	Expect("grey junk is deleted before a regular-bag overflow shard", Names(plan.sacrifices) == "Grey")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard Bag", bag = 1, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 4, itemFamily = 4 },
		{ name = "Soul Shard Extra", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
	}, {}, { protectReagents = true, keepSoulShards = 0 })
	Expect("regular-bag overflow above soul capacity is still destroy-eligible", Names(plan.sacrifices) == "Soul Shard Extra")
end

do
	local plan = Plan({
		{ name = "Sword", slot = 1, lootType = "item", itemID = 10, count = 1, maxStack = 1, unitPrice = 100 },
	}, {
		{ name = "Soul Shard Bag", bag = 1, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 4, itemFamily = 4 },
		{ name = "Soul Shard Extra", bag = 0, slot = 1, itemID = 6265, quality = 1, count = 1, maxStack = 1, unitPrice = 0, bagFamily = 0, itemFamily = 4 },
		{ name = "Grey", bag = 0, slot = 2, itemID = 2, quality = 0, count = 1, maxStack = 1, unitPrice = 1, bagFamily = 0 },
	}, { 4 }, { protectReagents = true, keepSoulShards = 0 })
	Expect("shards under soul capacity stay and grey is deleted", Names(plan.sacrifices) == "Grey")
end

do
	SmartLoot.db = { autoDestroy = true, autoDestroyMaxQuality = 0 }
	Expect("grey vendor trash is auto-destroy junk", SmartLoot.IsAutoDestroyCandidate({
		name = "Broken Stuff",
		quality = 0,
		unitPrice = 12,
		count = 1,
		equipLoc = "",
	}))
	Expect("white is skipped at the grey cap", not SmartLoot.IsAutoDestroyCandidate({
		name = "Linen Cloth",
		quality = 1,
		unitPrice = 30,
		count = 1,
		equipLoc = "",
	}))
	Expect("the hearthstone is never junk", not SmartLoot.IsAutoDestroyCandidate({
		name = "Hearthstone",
		quality = 0,
		itemID = 6948,
		equipLoc = "",
	}))
	SmartLoot.db.autoDestroyMaxQuality = 1
	Expect("white is junk when the cap is white", SmartLoot.IsAutoDestroyCandidate({
		name = "Linen Cloth",
		quality = 1,
		unitPrice = 30,
		count = 1,
		equipLoc = "",
	}))
end

do
	local list = SmartLoot.ManualDeleteCandidates({
		{ name = "Hearthstone", itemID = 6948, quality = 0, unitPrice = 0, count = 1, bag = 0, slot = 1, equipLoc = "" },
		{ name = "Expensive Grey", quality = 0, unitPrice = 500, count = 1, bag = 0, slot = 2, equipLoc = "" },
		{ name = "Cheap Grey", quality = 0, unitPrice = 5, count = 1, bag = 0, slot = 3, equipLoc = "" },
		{ name = "White Cloth", quality = 1, unitPrice = 30, count = 1, bag = 0, slot = 4, equipLoc = "", isReagent = true, classID = 7, subclassID = 5 },
		{ name = "Usable Sword", quality = 1, unitPrice = 1, count = 1, bag = 0, slot = 5, equipLoc = "INVTYPE_WEAPON", usable = true },
		{ name = "Locked", quality = 0, unitPrice = 1, count = 1, bag = 0, slot = 6, equipLoc = "", locked = true },
		{ name = "Quest Token", quality = 1, unitPrice = 0, count = 1, bag = 0, slot = 7, equipLoc = "", isQuest = true },
		{ name = "Protected Grey", quality = 0, unitPrice = 1, count = 1, bag = 0, slot = 8, equipLoc = "", protected = true },
	}, {}, { protectReagents = true })
	Expect("manual list cheapest first", Names(list) == "Cheap Grey,Expensive Grey")
	Expect("hearthstone stays off the list", list[1].name ~= "Hearthstone")
	Expect("usable gear stays off the list", list[1].name ~= "Usable Sword" and list[2] and list[2].name ~= "Usable Sword")
	Expect("protected items stay off the list", list[1].name ~= "Protected Grey" and list[2].name ~= "Protected Grey")
	local withProtected = SmartLoot.ManualDeleteCandidates({
		{ name = "Cheap Grey", quality = 0, unitPrice = 5, count = 1, bag = 0, slot = 3, equipLoc = "" },
		{ name = "Protected Grey", quality = 0, unitPrice = 1, count = 1, bag = 0, slot = 8, equipLoc = "", protected = true },
	}, {}, { protectReagents = true, includeProtected = true })
	Expect("protected items can be shown", Names(withProtected) == "Protected Grey,Cheap Grey")
end

print("priority checks passed: " .. checks)
