SmartLoot = {}
dofile("Loot/Rolls.lua")

local passed = 0

local function expect(name, got, want)
	if got ~= want then
		error(name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	end
	passed = passed + 1
end

local function item(fields)
	local copy = {
		itemLevel = 1,
		isGear = true,
		usable = true,
		upgrade = false,
		missingTransmog = false,
		canNeed = true,
		canGreed = true,
	}
	for key, value in pairs(fields) do
		copy[key] = value
	end
	return copy
end

local greed = { transmogRoll = "greed" }
local needTransmog = { transmogRoll = "need" }
local passTransmog = { transmogRoll = "pass" }

expect("main upgrade needs", SmartLoot.ChooseRoll(item({ upgrade = "main" }), greed), "need")
expect("boolean upgrade needs", SmartLoot.ChooseRoll(item({ upgrade = true }), greed), "need")
expect("same slot greeds", SmartLoot.ChooseRoll(item({}), greed), "greed")
expect("unusable greeds", SmartLoot.ChooseRoll(item({ upgrade = true, usable = false }), greed), "greed")
expect("offspec asks", SmartLoot.ChooseRoll(item({ upgrade = "offspec" }), greed), "ask-offspec")
expect("offspec without need greeds", SmartLoot.ChooseRoll(item({ upgrade = "offspec", canNeed = false }), greed), "greed")
expect("missing transmog needs", SmartLoot.ChooseRoll(item({ missingTransmog = true }), needTransmog), "need")
expect("missing transmog greeds", SmartLoot.ChooseRoll(item({ missingTransmog = true }), greed), "greed")
expect("missing transmog passes", SmartLoot.ChooseRoll(item({ missingTransmog = true }), passTransmog), "pass")
expect("upgrade beats transmog greed", SmartLoot.ChooseRoll(item({ upgrade = true, missingTransmog = true }), greed), "need")
expect("upgrade beats transmog pass", SmartLoot.ChooseRoll(item({ upgrade = "main", missingTransmog = true }), passTransmog), "need")
expect("need blocked falls back to greed", SmartLoot.ChooseRoll(item({ upgrade = true, canNeed = false }), greed), "greed")
expect("not gear greeds", SmartLoot.ChooseRoll(item({ isGear = false, upgrade = true }), greed), "greed")
expect("no greed leaves the roll", SmartLoot.ChooseRoll(item({ canGreed = false }), greed), nil)
expect("unknown mount needs", SmartLoot.ChooseRoll(item({ isMount = true, hasMount = false }), greed), "need")
expect("known mount passes", SmartLoot.ChooseRoll(item({ isMount = true, hasMount = true }), greed), "pass")
expect("low item level still needs", SmartLoot.ChooseRoll(item({ itemLevel = 1, upgrade = "main" }), greed), "need")

local Rolls = SmartLoot.Rolls
UnitClass = function()
	return "Warrior", "WARRIOR", 1
end
function Rolls:CurrentSpecIndex()
	return 1
end

expect("generic scale is main", Rolls:ScaleKind({ ClassID = 1 }), "main")
expect("matching spec is main", Rolls:ScaleKind({ ClassID = 1, SpecID = 1 }), "main")
expect("other spec is offspec", Rolls:ScaleKind({ ClassID = 1, SpecID = 2 }), "offspec")
expect("other class ignored", Rolls:ScaleKind({ ClassID = 4, SpecID = 1 }), nil)
expect("missing scale is main", Rolls:ScaleKind(nil), "main")

PawnIsReady = function()
	return true
end
PawnGetItemData = function(link)
	return { Link = link }
end
PawnCommon = {
	Scales = {
		Arms = { ClassID = 1, SpecID = 1 },
		Protection = { ClassID = 1, SpecID = 2 },
		Subtlety = { ClassID = 4, SpecID = 3 },
	},
}

PawnIsItemAnUpgrade = function()
	return { { ScaleName = "Arms", PercentUpgrade = 0.1 } }
end
expect("pawn main upgrade", (Rolls:PawnUpgradeKind("|Hitem:1|h")), "main")

PawnIsItemAnUpgrade = function()
	return { { ScaleName = "Protection", PercentUpgrade = 0.2 } }
end
expect("pawn offspec upgrade", (Rolls:PawnUpgradeKind("|Hitem:1|h")), "offspec")

PawnIsItemAnUpgrade = function()
	return {
		{ ScaleName = "Protection", PercentUpgrade = 0.2 },
		{ ScaleName = "Arms", PercentUpgrade = 0.05 },
	}
end
expect("main beats offspec", (Rolls:PawnUpgradeKind("|Hitem:1|h")), "main")

PawnIsItemAnUpgrade = function()
	return { { ScaleName = "Subtlety", PercentUpgrade = 0.4 } }
end
expect("other class not an upgrade", (Rolls:PawnUpgradeKind("|Hitem:1|h")), nil)

PawnIsItemAnUpgrade = function()
	return nil
end
expect("no pawn upgrade", (Rolls:PawnUpgradeKind("|Hitem:1|h")), nil)

PawnGetItemData = function()
	return { Link = nil }
end
local kind, pending = Rolls:PawnUpgradeKind("|Hitem:1|h")
expect("unloaded pawn item waits", kind, nil)
expect("unloaded pawn item pending", pending, true)

print("roll checks passed: " .. passed)
