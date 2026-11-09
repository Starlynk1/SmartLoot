local addon = SmartLoot or {}
SmartLoot = addon

function addon.IsRetail()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

-- Forever shares the modern UI but its project id is not mainline.
-- 1.60.x reports interface 16001.
function addon.IsForever()
	if not GetBuildInfo then
		return false
	end
	local version, _, _, toc = GetBuildInfo()
	toc = tonumber(toc) or 0
	if toc >= 16000 and toc < 20000 then
		return true
	end
	return type(version) == "string" and version:find("^1%.60") ~= nil
end

-- Classic Era / SoD / Hardcore use WOW_PROJECT_CLASSIC and interface 115xx.
function addon.IsClassicEra()
	if WOW_PROJECT_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
		return true
	end
	if not GetBuildInfo then
		return false
	end
	local _, _, _, toc = GetBuildInfo()
	toc = tonumber(toc) or 0
	return toc >= 11500 and toc < 12000
end

-- Classic loot cannot LootSlot after a delete, so the button only destroys.
function addon.DestroyActionLabel()
	if addon.IsClassicEra() then
		return "Destroy Item"
	end
	return "Destroy and Loot"
end

-- Side options tabs (spellbook style) on Forever and Classic Era.
function addon.UsesSideOptionsTabs()
	return addon.IsForever() or addon.IsClassicEra()
end

-- Separate ranged slot (18) on Classic Era and Forever; Retail uses main-hand (16).
function addon.UsesClassicRangedSlot()
	return addon.IsForever() or addon.IsClassicEra()
end

function addon.HasEditMode()
	return (C_EditMode and true or false) or (EditModeManagerFrame and true or false)
end

function addon.HasTransmog()
	return C_TransmogCollection and C_TransmogCollection.GetItemInfo and true or false
end

function addon.IsSupported()
	return addon.IsRetail() or addon.IsForever() or addon.IsClassicEra()
end

function addon.PlayerClassFile()
	if not UnitClass then
		return nil
	end
	local _, classFile = UnitClass("player")
	return classFile
end

function addon.IsWarlock()
	return addon.PlayerClassFile() == "WARLOCK"
end

function addon.IsMage()
	return addon.PlayerClassFile() == "MAGE"
end

function addon.IsHunter()
	return addon.PlayerClassFile() == "HUNTER"
end
