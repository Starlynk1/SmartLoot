SmartLoot = { db = { useAuctionValue = true } }
dofile("Loot/Value.lua")

Auctionator = {
	API = {
		v1 = {
			GetAuctionPriceByItemID = function()
				return 999
			end,
			GetVendorPriceByItemID = function(_, itemID)
				if itemID == 50 then
					return 20
				end
				return nil
			end,
		},
	},
}

local checks = 0

local function Expect(name, condition)
	checks = checks + 1
	if not condition then
		error("failed: " .. name)
	end
end

Expect("grey uses vendor price", SmartLoot.GetUnitPrice(1, 10, 0) == 10)
Expect("common uses auction price", SmartLoot.GetUnitPrice(1, 10, 1) == 999)
Expect("higher quality uses auction price", SmartLoot.GetUnitPrice(1, 10, 2) == 999)
Expect(
	"trade-goods Other uses vendor sell not auction",
	SmartLoot.GetUnitPrice(3371, 1, 1, { classID = 7, subclassID = 11, itemID = 3371 }) == 1
)
Expect(
	"trade-goods Parts uses vendor sell not auction",
	SmartLoot.GetUnitPrice(40, 2, 1, { classID = 7, subclassID = 1, itemID = 40 }) == 2
)
Expect(
	"cloth still uses auction",
	SmartLoot.GetUnitPrice(4306, 150, 1, { classID = 7, subclassID = 5, itemID = 4306 }) == 999
)
Expect(
	"known merchant buy price skips auction",
	SmartLoot.GetUnitPrice(50, 5, 1, { classID = 0, subclassID = 0, itemID = 50 }) == 5
)
Expect(
	"spell reagent uses vendor sell not auction",
	SmartLoot.GetUnitPrice(17032, 500, 1, { classID = 15, subclassID = 1, itemID = 17032 }) == 500
)

print("value checks passed: " .. checks)
