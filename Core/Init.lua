local addon = SmartLoot or {}
SmartLoot = addon

addon.VERSION = "0.1.0"

local DEFAULTS = {
	enabled = true,
	autoDestroy = false,
	autoDestroyMaxQuality = 0,
	autoCloseLeftover = 5,
	protectCraftingReagents = true,
	keepSoulShards = 0,
	keepConjured = 0,
	keepAmmo = 0,
	useAuctionValue = true,
	autoRoll = false,
	rollMinItemLevel = 1,
	transmogRoll = "greed",
	protected = {},
	minimap = {
		x = -12,
		y = -80,
		hide = false,
	},
	layouts = {},
}

local function CopyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				CopyDefaults(target[key], value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			CopyDefaults(target[key], value)
		end
	end
end

function addon.DefaultFrameLayout(key)
	if key == "decision" then
		return {
			point = "CENTER",
			relativePoint = "CENTER",
			x = 0,
			y = 40,
			scale = 1,
			fontSize = 12,
		}
	end
	return {
		point = "CENTER",
		relativePoint = "CENTER",
		x = 0,
		y = -40,
		scale = 1,
		fontSize = 12,
	}
end

function addon:HoldAutoLoot()
	if self.db.savedAutoLoot == nil and GetCVar then
		self.db.savedAutoLoot = GetCVar("autoLootDefault")
	end
	if SetCVar then
		SetCVar("autoLootDefault", "0")
	end
end

function addon:ReleaseAutoLoot()
	if self.db.savedAutoLoot ~= nil and SetCVar then
		SetCVar("autoLootDefault", self.db.savedAutoLoot)
		self.db.savedAutoLoot = nil
	end
end

function addon:SetEnabled(enabled, quiet)
	self.db.enabled = enabled and true or false
	if self.db.enabled then
		self:HoldAutoLoot()
		if self.Engine then
			self.Engine:Enable()
		end
	else
		if self.Engine then
			self.Engine:Disable()
		end
		self:ReleaseAutoLoot()
	end
	if self.Options and self.Options.Refresh then
		self.Options:Refresh()
	end
	if not quiet and self.Print then
		self.Print(self.db.enabled and "Enabled." or "Disabled.")
	end
end

function addon:ProtectItem(itemID, name)
	itemID = tonumber(itemID)
	if not itemID or not self.db then
		return
	end
	self.db.protected[itemID] = name or self.db.protected[itemID] or true
	if self.Options and self.Options.RefreshProtected then
		self.Options:RefreshProtected()
	end
	local stored = self.db.protected[itemID]
	local label = type(stored) == "string" and stored or ("item " .. itemID)
	self.Print("Protected " .. label .. ".")
end

function addon:UnprotectItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or not self.db then
		return
	end
	local stored = self.db.protected[itemID]
	self.db.protected[itemID] = nil
	if self.Options and self.Options.RefreshProtected then
		self.Options:RefreshProtected()
	end
	local label = type(stored) == "string" and stored or ("item " .. itemID)
	self.Print("Removed " .. label .. ".")
end

function addon:Initialize()
	if self.initialized then
		return
	end
	self.initialized = true
	if not self.IsSupported() then
		self.Print("SmartLoot loot behavior currently runs on Retail, Forever, and Classic Era.")
		return
	end
	SmartLootDB = SmartLootDB or {}
	self.db = SmartLootDB
	CopyDefaults(self.db, DEFAULTS)
	if self.db.confirmBeforeDelete == false then
		self.db.autoDestroy = true
	end
	self.db.confirmBeforeDelete = nil
	local quality = tonumber(self.db.autoDestroyMaxQuality) or 0
	if quality < 0 then
		quality = 0
	elseif quality > 2 then
		quality = 2
	end
	self.db.autoDestroyMaxQuality = math.floor(quality)
	local closeAfter = tonumber(self.db.autoCloseLeftover)
	if not closeAfter then
		closeAfter = 5
	elseif closeAfter < 0 then
		closeAfter = 0
	elseif closeAfter > 15 then
		closeAfter = 15
	end
	self.db.autoCloseLeftover = math.floor(closeAfter + 0.5)
	if self.Decision then
		self.Decision:Initialize()
	end
	if self.Options then
		self.Options:Initialize()
	end
	if self.Minimap then
		self.Minimap:Initialize()
	end
	if self.EditMode then
		self.EditMode:Initialize()
	end
	if self.Engine then
		self.Engine:Initialize()
	end
	if self.Rolls then
		self.Rolls:Initialize()
	end
	self:SetEnabled(self.db.enabled, true)
	if self.EditMode then
		self.EditMode:ApplySaved()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		if name == "SmartLoot" then
			addon:Initialize()
		end
		if addon.EditMode then
			addon.EditMode:TryHook()
		end
		if addon.Options then
			addon.Options:HookBags()
		end
	elseif event == "PLAYER_LOGIN" then
		if addon.Inventory and addon.Inventory.RefreshCache then
			addon.Inventory.RefreshCache()
		end
		if addon.Minimap then
			addon.Minimap:Initialize()
		end
		if addon.EditMode then
			addon.EditMode:TryHook()
		end
		if addon.Options then
			addon.Options:HookBags()
		end
	end
end)

SLASH_SMARTLOOT1 = "/smartloot"
SLASH_SMARTLOOT2 = "/sl"
SlashCmdList.SMARTLOOT = function(message)
	if not addon.db then
		return
	end
	message = addon.Trim(message):lower()
	if message == "enable" or message == "on" then
		addon:SetEnabled(true)
	elseif message == "disable" or message == "off" then
		addon:SetEnabled(false)
	elseif addon.Options then
		addon.Options:Toggle()
	end
end
