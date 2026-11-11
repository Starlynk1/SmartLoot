local addon = SmartLoot or {}
SmartLoot = addon

local JUNK_QUALITY = "quality"
local JUNK_BAGANATOR = "baganator"
local JUNK_RXP = "rxpguides"

function addon.JunkSource()
	local source = addon.db and addon.db.junkSource
	if source == JUNK_BAGANATOR or source == JUNK_RXP then
		return source
	end
	return JUNK_QUALITY
end

local function AddonLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name) and true or false
	end
	if IsAddOnLoaded then
		return IsAddOnLoaded(name) and true or false
	end
	return false
end

local function IsPoorJunk(item)
	if not item or (item.quality or 0) ~= 0 then
		return false
	end
	if item.hasNoValue then
		return false
	end
	return true
end

function addon.GetRXPInventoryManager()
	local lib = LibStub
	if not lib then
		return nil
	end
	local ace = lib("AceAddon-3.0", true)
	if not ace or not ace.GetAddon then
		return nil
	end
	local ok, rxp = pcall(ace.GetAddon, ace, "RXPGuides", true)
	if not ok or not rxp then
		return nil
	end
	if rxp.inventoryManager and rxp.inventoryManager.IsJunk then
		return rxp.inventoryManager
	end
	if rxp.GetModule then
		local moduleOk, manager = pcall(rxp.GetModule, rxp, "InventoryManager", true)
		if moduleOk and manager and manager.IsJunk then
			return manager
		end
	end
	return nil
end

function addon.IsRXPJunk(item)
	if not item or not item.itemID then
		return false
	end
	local manager = addon.GetRXPInventoryManager()
	if not manager then
		return IsPoorJunk(item)
	end
	local ok, junk = pcall(manager.IsJunk, manager, item.itemID, item.bag, item.slot)
	return ok and junk == true
end

function addon.BaganatorJunkPluginID()
	if Baganator and Baganator.API and Baganator.API.IsJunkPluginActive then
		local ids = { "RXPGuides", "selljunk", "scrap", "vendor", "dejunk", "none" }
		for index = 1, #ids do
			local ok, active = pcall(Baganator.API.IsJunkPluginActive, ids[index])
			if ok and active then
				return ids[index]
			end
		end
	end
	local config = BAGANATOR_CONFIG
	if type(config) ~= "table" or type(config.Profiles) ~= "table" then
		return "poor_quality"
	end
	local profile = BAGANATOR_CURRENT_PROFILE or "DEFAULT"
	local data = config.Profiles[profile] or config.Profiles.DEFAULT
	if type(data) ~= "table" then
		return "poor_quality"
	end
	return data.junk_plugin or "poor_quality"
end

function addon.IsBaganatorJunk(item)
	if not item then
		return false
	end
	if not AddonLoaded("Baganator") then
		return IsPoorJunk(item)
	end
	local pluginID = addon.BaganatorJunkPluginID()
	if pluginID == "none" then
		return false
	end
	if pluginID == "RXPGuides" then
		return addon.IsRXPJunk(item)
	end
	if pluginID == "selljunk" and SellJunk and SellJunk.CheckItemIsJunk then
		local ok, junk = pcall(SellJunk.CheckItemIsJunk, SellJunk, item.link, item.bag, item.slot)
		return ok and junk == true
	end
	if pluginID == "scrap" and Scrap and Scrap.IsJunk then
		local ok, junk = pcall(Scrap.IsJunk, Scrap, item.itemID, item.bag, item.slot)
		return ok and junk == true
	end
	if pluginID == "vendor" and Vendor and Vendor.EvaluateItem then
		local ok, result = pcall(Vendor.EvaluateItem, item.bag, item.slot)
		return ok and result ~= 0 and result ~= nil
	end
	if pluginID == "dejunk" and DejunkApi and DejunkApi.IsJunk then
		local ok, junk = pcall(DejunkApi.IsJunk, DejunkApi, item.bag, item.slot)
		return ok and junk == true
	end
	return IsPoorJunk(item)
end

function addon.IsMarkedJunk(item)
	if not item then
		return false
	end
	local source = addon.JunkSource()
	if source == JUNK_BAGANATOR then
		return addon.IsBaganatorJunk(item)
	end
	if source == JUNK_RXP then
		return addon.IsRXPJunk(item)
	end
	return IsPoorJunk(item)
end
