local addon = SmartLoot or {}
SmartLoot = addon

local function Plain(text)
	if not text then
		return ""
	end
	return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function addon.ObjectiveNamesItem(text, itemName)
	if not text or not itemName or itemName == "" then
		return false
	end
	text = Plain(text)
	if text == itemName then
		return true
	end
	local before = text:match("^(.-):")
	if not before then
		return false
	end
	before = before:match("^%s*(.-)%s*$")
	return before == itemName
end

function addon.LootSlotNeedsQuest(isQuestItem, questID, isActive)
	if isQuestItem then
		return true
	end
	if questID and questID ~= 0 then
		return true
	end
	return false
end

local function ObjectiveKind(objective)
	local kind = objective.type
	if type(kind) == "string" then
		return kind:lower()
	end
	local types = Enum and Enum.QuestObjectiveType
	local enumType = objective.objectiveType
	if type(kind) == "number" then
		enumType = kind
	end
	if not types or enumType == nil then
		return ""
	end
	if enumType == types.Item then
		return "item"
	end
	if enumType == types.Object then
		return "object"
	end
	return ""
end

function addon.MatchesTrackedQuest(item, tracked)
	if not item or not tracked then
		return false
	end
	local questID = item.questID
	local itemID = item.itemID
	local name = item.name
	for index = 1, #tracked do
		local quest = tracked[index]
		if questID and questID ~= 0 and quest.questID == questID then
			return true
		end
		local objectives = quest.objectives
		if objectives then
			for objectiveIndex = 1, #objectives do
				local objective = objectives[objectiveIndex]
				local kind = ObjectiveKind(objective)
				if (kind == "item" or kind == "object") and not objective.finished then
					if itemID and objective.itemID and objective.itemID == itemID then
						return true
					end
					if addon.ObjectiveNamesItem(objective.text, name) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function AddWatch(tracked, seen, questID)
	if not questID or questID == 0 or seen[questID] or not C_QuestLog then
		return
	end
	seen[questID] = true
	local objectives = {}
	if C_QuestLog.GetQuestObjectives then
		local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
		if ok and type(list) == "table" then
			for index = 1, #list do
				objectives[#objectives + 1] = list[index]
			end
		end
	end
	if #objectives == 0 and GetQuestLogLeaderBoard and C_QuestLog.GetLogIndexForQuestID then
		local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
		local count = 0
		if logIndex and GetNumQuestLeaderBoards then
			count = GetNumQuestLeaderBoards(logIndex) or 0
		end
		for index = 1, count do
			local text, objectiveType, finished = GetQuestLogLeaderBoard(index, logIndex)
			objectives[#objectives + 1] = {
				text = text,
				type = objectiveType,
				finished = finished,
			}
		end
	end
	tracked[#tracked + 1] = {
		questID = questID,
		objectives = objectives,
	}
end

function addon.GetTrackedQuests()
	local tracked = {}
	local seen = {}
	if not C_QuestLog then
		return tracked
	end
	local watches = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
	for index = 1, watches do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex and C_QuestLog.GetQuestIDForQuestWatchIndex(index)
		AddWatch(tracked, seen, questID)
	end
	local worldWatches = C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetNumWorldQuestWatches() or 0
	for index = 1, worldWatches do
		local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex and C_QuestLog.GetQuestIDForWorldQuestWatchIndex(index)
		AddWatch(tracked, seen, questID)
	end
	local shown = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
	if C_QuestLog.GetInfo then
		for index = 1, shown do
			local ok, info = pcall(C_QuestLog.GetInfo, index)
			if ok and type(info) == "table" and not info.isHeader then
				AddWatch(tracked, seen, info.questID)
			end
		end
	end
	return tracked
end

local function LineHasQuestItem(text)
	if type(text) ~= "string" then
		return false
	end
	local ok, found = pcall(function()
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if text:find("Quest Item", 1, true) then
			return true
		end
		local localized = ITEM_BIND_QUEST
		if type(localized) == "string" and localized ~= "" and localized ~= "Quest Item" then
			return text:find(localized, 1, true) ~= nil
		end
		return false
	end)
	return ok and found or false
end

function addon.TooltipHasQuestItem(lines)
	if not lines then
		return false
	end
	for index = 1, #lines do
		if LineHasQuestItem(lines[index]) then
			return true
		end
	end
	return false
end

local function TooltipDataNeedsQuest(data)
	if not data or not data.lines then
		return false
	end
	if TooltipUtil and TooltipUtil.SurfaceArgs then
		pcall(TooltipUtil.SurfaceArgs, data)
	end
	local questLine = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
	for index = 1, #data.lines do
		local line = data.lines[index]
		if type(line) == "table" then
			if TooltipUtil and TooltipUtil.SurfaceArgs then
				pcall(TooltipUtil.SurfaceArgs, line)
			end
			if questLine and line.type == questLine and not line.completed then
				return true
			end
			if LineHasQuestItem(line.leftText) or LineHasQuestItem(line.rightText) then
				return true
			end
		elseif LineHasQuestItem(line) then
			return true
		end
	end
	return false
end

local scanTip

local function HiddenTooltipLines(slot, link)
	if not CreateFrame then
		return nil
	end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "SmartLootQuestTip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTip:ClearLines()
	local shown = false
	if slot and scanTip.SetLootItem then
		shown = pcall(scanTip.SetLootItem, scanTip, slot)
	end
	if not shown and link and scanTip.SetHyperlink then
		shown = pcall(scanTip.SetHyperlink, scanTip, link)
	end
	if not shown then
		scanTip:Hide()
		return nil
	end
	local lines = {}
	local tipName = scanTip:GetName()
	local count = scanTip:NumLines() or 0
	for index = 1, count do
		local left = _G[tipName .. "TextLeft" .. index]
		local right = _G[tipName .. "TextRight" .. index]
		if left and left.GetText then
			lines[#lines + 1] = left:GetText()
		end
		if right and right.GetText then
			lines[#lines + 1] = right:GetText()
		end
	end
	scanTip:Hide()
	return lines
end

function addon.LootTooltipNeedsQuest(slot, link)
	local needed = false
	if C_TooltipInfo and C_TooltipInfo.GetLootItem and slot then
		local ok, data = pcall(C_TooltipInfo.GetLootItem, slot)
		if ok and TooltipDataNeedsQuest(data) then
			needed = true
		end
	end
	if not needed and C_TooltipInfo and C_TooltipInfo.GetHyperlink and link then
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
		if ok and TooltipDataNeedsQuest(data) then
			needed = true
		end
	end
	if not needed then
		local hidden = HiddenTooltipLines(slot, link)
		if hidden and addon.TooltipHasQuestItem(hidden) then
			needed = true
		end
	end
	return needed
end

function addon.MarkTrackedQuestItems(items)
	if not items then
		return
	end
	local tracked = addon.GetTrackedQuests()
	for index = 1, #items do
		local item = items[index]
		local tooltipQuest = item.lootType == "item" and addon.LootTooltipNeedsQuest(item.slot, item.link)
		if item.neededForQuest or tooltipQuest or addon.MatchesTrackedQuest(item, tracked) then
			item.neededForQuest = true
			item.isQuest = true
		end
	end
end
