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
		itemLevel = 100,
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

local greed = { minItemLevel = 50, transmogRoll = "greed" }
local needTransmog = { minItemLevel = 50, transmogRoll = "need" }

expect("below threshold", SmartLoot.ChooseRoll(item({ itemLevel = 49, upgrade = true }), greed), nil)
expect("upgrade needs", SmartLoot.ChooseRoll(item({ upgrade = true }), greed), "need")
expect("same slot greeds", SmartLoot.ChooseRoll(item({}), greed), "greed")
expect("unusable greeds", SmartLoot.ChooseRoll(item({ upgrade = true, usable = false }), greed), "greed")
expect("missing transmog needs", SmartLoot.ChooseRoll(item({ missingTransmog = true }), needTransmog), "need")
expect("missing transmog greeds", SmartLoot.ChooseRoll(item({ missingTransmog = true }), greed), "greed")
expect("upgrade beats transmog greed", SmartLoot.ChooseRoll(item({ upgrade = true, missingTransmog = true }), greed), "need")
expect("need blocked falls back to greed", SmartLoot.ChooseRoll(item({ upgrade = true, canNeed = false }), greed), "greed")
expect("not gear greeds", SmartLoot.ChooseRoll(item({ isGear = false, upgrade = true }), greed), "greed")
expect("no greed leaves the roll", SmartLoot.ChooseRoll(item({ canGreed = false }), greed), nil)

print("roll checks passed: " .. passed)
