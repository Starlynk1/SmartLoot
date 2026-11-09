SmartLoot = {}
dofile("Loot/Quests.lua")

local checks = 0

local function Expect(name, condition)
	checks = checks + 1
	if not condition then
		error("failed: " .. name)
	end
end

local tracked = {
	{
		questID = 100,
		objectives = {
			{ type = "item", finished = false, text = "Wolf Meat: 0/10" },
			{ type = "monster", finished = false, text = "Wolf Meat: 0/5" },
			{ type = "item", finished = true, text = "Bear Hide: 5/5" },
		},
	},
}

Expect("objective name matches", SmartLoot.MatchesTrackedQuest({ name = "Wolf Meat", itemID = 8 }, tracked))
Expect("shorter name does not match", not SmartLoot.MatchesTrackedQuest({ name = "Meat", itemID = 9 }, tracked))
Expect("kill objective does not match", not SmartLoot.MatchesTrackedQuest({ name = "Wolf" }, {
	{ questID = 100, objectives = { { type = "monster", finished = false, text = "Wolf: 0/5" } } },
}))
Expect("finished item is not needed", not SmartLoot.MatchesTrackedQuest({ name = "Bear Hide", itemID = 4 }, tracked))
Expect("quest id on the tracker matches", SmartLoot.MatchesTrackedQuest({ name = "Strange Drop", questID = 100 }, tracked))
Expect("other quest id does not match", not SmartLoot.MatchesTrackedQuest({ name = "Strange Drop", questID = 200, isQuest = true }, tracked))

local items = {
	{ name = "Wolf Meat", itemID = 8 },
	{ name = "Junk", itemID = 1, unitPrice = 5 },
}
SmartLoot.GetTrackedQuests = function()
	return tracked
end
SmartLoot.MarkTrackedQuestItems(items)
Expect("tooltip Quest Item is needed", SmartLoot.TooltipHasQuestItem({ "Wolf Meat", "Quest Item", "Binds when picked up" }))
Expect("other tooltip text is not enough", not SmartLoot.TooltipHasQuestItem({ "Wolf Meat", "This Item Begins a Quest" }))
Expect("tracker match forces the quest loot", items[1].neededForQuest and items[1].isQuest)
Expect("unrelated loot is unchanged", not items[2].neededForQuest)
Expect("corpse quest item is needed without isActive", SmartLoot.LootSlotNeedsQuest(true, nil, false))
Expect("quest continuation item is needed", SmartLoot.LootSlotNeedsQuest(true, 100, false))
Expect("active quest id is needed", SmartLoot.LootSlotNeedsQuest(false, 100, true))
Expect("plain loot is not a quest slot", not SmartLoot.LootSlotNeedsQuest(false, nil, false))
Expect("object objective name matches", SmartLoot.MatchesTrackedQuest({ name = "Sealed Letter" }, {
	{ questID = 100, objectives = { { type = "object", finished = false, text = "Sealed Letter: 0/1" } } },
}))

print("quest checks passed: " .. checks)
