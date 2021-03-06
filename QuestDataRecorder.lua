QDR = {}

local L = QuestDataRecLocals
local questGiverID, questGiven, questGiverType, setToAbandon, abandonedName
local playerX, playerY, playerZone, questLog
local tempQuestLog, tempQuestItems, questPatterns, factionRanks, lootedGUID = {}, {}, {}, {}, {}
local isQuestItem, questItemsLost, questItemsGained, questItems = {}, {}, {}, {}

function QDR:OnInitialize()
	QuestDataRecDB = QuestDataRecDB or {}
	self.db = QuestDataRecDB
	self.logs = {}

	local defaults = {stopped = false, debugLevel = 0, npcdata = {}, objectdata = {}, itemdata = {}, questdata = {}}
	for key, value in pairs(defaults) do
		if( QuestDataRecDB[key] == nil ) then
			if( type(value) == "table" ) then
				QuestDataRecDB[key] = CopyTable(value)
			else
				QuestDataRecDB[key] = value
			end
		end
	end
	
	self.questData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {objectives = {}}

			-- No data is cached yet
			if( not QDR.db.questdata[index] ) then
				return tbl[index]
			end
			
			
			tbl[index] = loadstring("return " .. QDR.db.questdata[index])()

			return tbl[index]
		end
	})
	
	self.npcData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.npcdata[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.npcdata[index])()
			
			return tbl[index]
		end
	})

	self.objectData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.objectdata[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.objectdata[index])()
			
			return tbl[index]
		end
	})
	
	self.itemData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.itemdata[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.itemdata[index])()
			
			return tbl[index]
		end
	})
		
	-- Quest patterns
	questPatterns.reputation = self:Deformat(QUEST_FACTION_NEEDED)
	questPatterns.item = self:Deformat(QUEST_ITEMS_NEEDED)
	questPatterns.monster = self:Deformat(QUEST_MONSTERS_KILLED)
	questPatterns.object = self:Deformat(QUEST_OBJECTS_FOUND)
	questPatterns.player = self:Deformat(QUEST_PLAYERS_KILLED)
	
	factionRanks = {
		[FACTION_STANDING_LABEL1] = 0,
		[FACTION_STANDING_LABEL2] = 1,
		[FACTION_STANDING_LABEL3] = 3,
		[FACTION_STANDING_LABEL4] = 4,
		[FACTION_STANDING_LABEL5] = 5,
		[FACTION_STANDING_LABEL6] = 6,
		[FACTION_STANDING_LABEL7] = 7,
		[FACTION_STANDING_LABEL8] = 8,
	}
	
	-- Handle quest abandoning
	hooksecurefunc("AbandonQuest", function()
		abandonedName = setToAbandon
		setToAbandon = nil
	end)
	
	hooksecurefunc("SetAbandonQuest", function()
		setToAbandon = GetAbandonQuestName()
	end)
	
	-- Recording
	if( not self.db.stopped ) then
		self:StartRecording()
	end
end

function QDR:StartRecording()
	self.frame:RegisterEvent("QUEST_DETAIL")
	self.frame:RegisterEvent("QUEST_LOG_UPDATE")
	self.frame:RegisterEvent("QUEST_COMPLETE")
	self.frame:RegisterEvent("LOOT_OPENED")
	self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	self.frame:RegisterEvent("PLAYER_LEAVING_WORLD")
	self.frame:RegisterEvent("BAG_UPDATE")
end

function QDR:StopRecording()
	self.frame:UnregisterEvent("QUEST_DETAIL")
	self.frame:UnregisterEvent("QUEST_LOG_UPDATE")
	self.frame:UnregisterEvent("QUEST_COMPLETE")
	self.frame:UnregisterEvent("LOOT_OPENED")
	self.frame:UnregisterEvent("BAG_UPDATE")
	self.frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self.frame:UnregisterEvent("PLAYER_LEAVING_WORLD")
end

function QDR:Debug(level, text, ...)
	if( self.db.debugLevel == 0 ) then
		return
	elseif( level <= self.db.debugLevel  ) then
		print(string.format(text, ...))
		table.insert(self.logs, string.format("[%s] " .. text, GetTime(), ...))
	else
		table.insert(self.logs, string.format("[%s] " .. text, GetTime(), ...))
	end
end

function QDR:LOOT_OPENED()
	-- If the target exists, is dead, not a player, and it's an actual NPC then we will say we're looting that NPC
	local npcID
	local guid = UnitGUID("target")
	if( guid and UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") ) then
		-- We already looted this corpse
		if( lootedGUID[guid] ) then
			return
		end
		
		lootedGUID[guid] = true

		-- Make sure the GUID is actually an NPC ones
		local id, npcType = self:GetMobID(guid)
		if( npcType == self.dataToID.npc ) then
			npcID = id
		end
	end
		
	-- Record all the items on this NPC
	for i=1, GetNumLootItems() do
		local link = GetLootSlotLink(i)
		if( self:IsQuestItem(link) ) then
			-- Record the item loot location
			local itemID = string.match(link, "item:([0-9]+)")
			local x, y, zone = self:GetPlayerPosition()

			itemID = tonumber(itemID)

			self.itemData[itemID].type = self.dataToID.item
			table.insert(self.itemData[itemID].coords, self.mapToID[zone])
			table.insert(self.itemData[itemID].coords, x)
			table.insert(self.itemData[itemID].coords, y)

			-- If we have an NPC ID then associate the npc with dropping that item
			if( npcID ) then
				self:Debug(1, "Found itemid %d from npc %d in %s at %.2f, %.2f.", itemID, npcID, self.mapToID[zone], x, y)

				self.npcData[npcID].items = self.npcData[npcID].items or {}

				-- Already recorded it
				for _, dropID in pairs(self.npcData[npcID].items) do
					if( itemID == dropID ) then
						return
					end
				end

				table.insert(self.npcData[npcID].items, itemID)
				self:Debug(1, "Associated the NPC %d with dropping %d.", npcID, itemID)
			else
				self:Debug(1, "Found itemid %d in %s at %.2f, %.2f.", itemID, self.mapToID[zone], x, y)
			end
		end
	end
end

-- Stop bag updates while we are entering/leaving the world
function QDR:PLAYER_ENTERING_WORLD()
	self.frame:RegisterEvent("BAG_UPDATE")
end

function QDR:PLAYER_LEAVING_WORLD()
	self.frame:UnregisterEvent("BAG_UPDATE")
end

-- Record quest item association
function QDR:BAG_UPDATE()
	for k in pairs(tempQuestItems) do tempQuestItems[k] = nil end
	
	-- Load all quest items in the players bag
	for bag=0, 4 do
		for slot=1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if( self:IsQuestItem(link) ) then
				local count = select(2, GetContainerItemInfo(bag, slot))
				local itemID = string.match(link, "item:([0-9]+)")

				tempQuestItems[tonumber(itemID)] = (tempQuestItems[tonumber(itemID)] or 0) + count
			end
		end
	end
		
	local timeout = GetTime() + 0.70
	-- Lost a quest item
	for itemID, count in pairs(questItems) do
		if( not tempQuestItems[itemID] or tempQuestItems[itemID] < count ) then
			questItemsLost[itemID] = timeout
			self:Debug(2, "Lost quest item %d, we had %d of it before.", itemID, tempQuestItems[itemID] or 0)
		end
	end

	-- Gained a quest item
	for itemID, count in pairs(tempQuestItems) do
		if( not questItems[itemID] or questItems[itemID] < count ) then
			questItemsGained[itemID] = timeout
			self:Debug(2, "Gained quest item %d, we had %d of it before.", itemID, questItems[itemID] or 0)
		end
	end

	-- Copy data in
	for key in pairs(questItems) do
		questItems[key] = nil
	end
	
	for itemID, count in pairs(tempQuestItems) do
		questItems[itemID] = count
	end
end

-- Figure out if an item is a quest item, then cache the results
-- Some items, like "Demonic Rune Stone" are tagged as "Quest Items", but the item types are not
function QDR:IsQuestItem(link)
	if( not link ) then
		return nil
	elseif( isQuestItem[link] ~= nil ) then
		return isQuestItem[link]
	end
	
	local itemType, subType = select(6, GetItemInfo(link))
	if( itemType == "Quest" and subType == "Quest" ) then
		isQuestItem[link] = true
	else
		if( not self.tooltip ) then
			self.tooltip = CreateFrame("GameTooltip", "QuestDataRecTooltip", UIParent, "GameTooltipTemplate")
		end	
		
		self.tooltip:ClearLines()
		self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
		self.tooltip:SetHyperlink(link)
		
		isQuestItem[link] = QuestDataRecTooltipTextLeft2:GetText() == ITEM_BIND_QUEST
	end
	
	return isQuestItem[link]
end

-- Quest log updated, see what changed quest-wise
-- NTS: Redo this function to use two tables at most to make it more sane to work with
function QDR:QUEST_LOG_UPDATE(event)
	-- Scan quest log
	local foundQuests = 0
	local index = 1
	local numQuests = select(2, GetNumQuestLogEntries())
	while( foundQuests <= numQuests ) do
		local questName, _, _, _, isHeader = GetQuestLogTitle(index)
		if( not questName ) then break end
		
		if( not isHeader ) then
			foundQuests = foundQuests + 1
			
			local questID = string.match(GetQuestLink(index), "|Hquest:(%d+):(%-?%d+)|h")
			questID = tonumber(questID)
			
			tempQuestLog[questID] = tempQuestLog[questID] or {objectives = {}}
			
			local questData = tempQuestLog[questID]
			questData.id = questID
			questData.inactive = false
			
			-- Parse the leaderboard objectives to find the progress on the objectives
			for objID=1, GetNumQuestLeaderBoards(index) do
				local text, type, finished = GetQuestLogLeaderBoard(objID, index)
				local current, max = 0, 0
				
				-- Players slain: #/#
				if( type == "player" ) then
					current, max = string.match(text, questPatterns[type])
					current = tonumber(current)
					max = tonumber(max)
				-- <faction>: <have> / <needed>
				elseif( type == "reputation" ) then
					local currentLevel, neededLevel = select(2, string.match(text, questPatterns[type]))
					current = factionRanks[currentLevel]
					max = factionRanks[neededLevel]
				-- Remaining: <item/object> #/# & <name> slain: #/# (Or (%d+)/(%d+) if those fail)
				elseif( questPatterns[type] ) then
					current, max = select(2, string.match(text, questPatterns[type]))
					if( not current or not max ) then
						current, max = string.match(text, L["(%d+)/(%d+)$"])
					end
					
					current = tonumber(current)
					max = tonumber(max)
				-- No number, it's just either completed or is not
				else
					max = 1
					current = finished and 1 or 0
				end
						
				questData.objectives[objID] = questData.objectives[objID] or {}
				questData.objectives[objID].text = text
				questData.objectives[objID].type = type
				questData.objectives[objID].finished = finished
				questData.objectives[objID].current = current
				questData.objectives[objID].max = max
			end
		end
		
		index = index + 1
	end
	
	-- We don't have any previous data to go off of yet, store what we had
	if( not questLog ) then
		questLog = CopyTable(tempQuestLog)
		return
	end
		
	-- Find quests we accepted
	if( questGiverID ) then
		for tempID, tempData in pairs(tempQuestLog) do
			if( not tempData.inactive and not questLog[tempID] ) then
				self:RecordNPCLocation()
				
				self.questData[tempID].sid = questGiverID
				self.questData[tempID].stype = questGiverType
				
				self:Debug(1, "%s ID %d starts %s (%d).", self.idToData[questGiverType], questGiverID, self:GetQuestName(tempID) or "?", tempID)
			end
		end
	end

	-- Find quests we abandoned or accepted
	for questID, questData in pairs(questLog) do
		if( not tempQuestLog[questID] or tempQuestLog[questID].inactive ) then
			local questName = self:GetQuestName(questID)
			if( questGiverID and ( not abandonedName or abandonedName ~= questName ) ) then
				self:RecordNPCLocation()
				
				self.questData[questID].eid = questGiverID
				self.questData[questID].etype = questGiverType

				-- Remove our data on it then
				questLog[questID] = nil
				tempQuestLog[questID] = nil
				
				self:Debug(1, "%s ID %d ends %s (%d).", self.idToData[questGiverType], questGiverID, self:GetQuestName(questID) or "?", questID)
			elseif( abandonedName == questName ) then
				self:Debug(2, "Abandoned %s.", abandonedName)
				
				questLog[questID] = nil
				
				abandonedName = nil
				break
			end
		end
	end
	
	-- Check if an objective changed
	local time = GetTime()
	for questID, tempData in pairs(tempQuestLog) do
		-- We have this quest last update, so we can compare it
		local questData = questLog[questID]
		if( questData ) then	
			for objID, tempObjData in pairs(tempData.objectives) do
				if( questData.objectives[objID] and questData.objectives[objID].current and tempObjData.current and questData.objectives[objID].current < tempObjData.current ) then
					local x, y, zone = self:GetPlayerPosition()
					local zoneID = self.mapToID[zone]
					
					self.questData[questID].objectives[objID] = self.questData[questID].objectives[objID] or {coords = {}}

					local questObjective = self.questData[questID].objectives[objID]
					questObjective.reagitems = questObjective.reagitems or {}
					questObjective.recitems = questObjective.recitems or {}
					questObjective.type = self.dataToID[tempObjData.type]

					table.insert(questObjective.coords, zoneID)
					table.insert(questObjective.coords, x)
					table.insert(questObjective.coords, y)
					
					self:Debug(1, "Objective %d (%s) changed for %s (%d) at %.2f, %.2f.", objID, tempObjData.type, self:GetQuestName(questID) or "?", questID, x, y)

					-- Do we have an item that should be associated?
					for itemID, timeout in pairs(questItemsLost) do
						if( time < timeout ) then
							if( not questObjective.reagitems[itemID] ) then
								self:Debug(2, "Associating item id %d as an objective of %d, as it was removed from inventory.", itemID, objID)
							end
							
							questObjective.reagitems[itemID] = true
						end
						
						questItemsLost[itemID] = nil
					end

					-- Do we have an item that should be associated?
					for itemID, timeout in pairs(questItemsGained) do
						if( time < timeout ) then
							if( not questObjective.recitems[itemID] ) then
								self:Debug(2, "Associating item id %d as an objective of %d, as it was put into the inventory.", itemID, objID)
							end
							
							questObjective.recitems[itemID] = true
						end
						
						questItemsGained[itemID] = nil
					end
				end
			end
		end
	end
					
	-- Copy data for next time + reset our temp data
	for tempID, tempData in pairs(tempQuestLog) do
		if( not tempData.inactive ) then
			questLog[tempID] = questLog[tempID] or {objectives = {}}

			-- Flag we haven't seen this yet, next update it'll be reset
			tempData.inactive = true

			local questData = questLog[tempID]
			questData.id = tempData.id

			for tempObjID, tempObjData in pairs(tempData.objectives) do
				questData.objectives[tempObjID] = questData.objectives[tempObjID] or {}

				-- Reset previous objective data
				local objectives = questData.objectives[tempObjID]
				-- Copy new one in
				for key, value in pairs(tempObjData) do
					objectives[key] = value
					tempObjData[key] = nil
				end
			end
		end
	end
end

function QDR:QuestProgress()
	questGiverID, questGiverType = self:GetMobID(UnitGUID("npc"))
	questGiven = self:StripData(GetTitleText())
	
	-- We cannot get itemid from GUId, so we have to do an inventory scan to find what we want
	if( questGiverType == self.dataToID.item ) then
		questGiverID = nil
		
		-- Loop through bags
		for bag=0, 4 do
			-- Scanning a bag
			for slot=1, GetContainerNumSlots(bag) do
				local link = GetContainerItemLink(bag, slot)
				if( link and GetItemInfo(link) == UnitName("npc") ) then
					local itemID = string.match(link, "item:([0-9]+)")
					questGiverID = tonumber(itemID)
					break
				end
			end
		end
		
		if( not questGiverID ) then
			self:Debug(1, "Failed to associate NPC id for %s (%s) to %s, cannot find the item it was from.", (UnitName("npc")) or "?", questGiverType, questGiven)
		end
	end
	
	-- We store the player position here, because thats more accurate theres a slightly 0.5s-1s delay
	-- before we see the quest was accepted
	playerX, playerY, playerZone = self:GetPlayerPosition()
end

function QDR:QUEST_COMPLETE(event)
	self:QuestProgress()
end

-- We're looking at the details of the quest, save the quest info so we can use it later
function QDR:QUEST_DETAIL(event)
	-- When a quest is shared with us, "npc" is actually the "player" unitid
	if( UnitIsPlayer("npc") ) then
		questGiverID = nil
		return
	end
	
	self:QuestProgress()
end

function QDR:RecordNPCLocation()
	-- Location if it was started from an item needs to be pulled from itemData
	if( questGiverType == self.dataToID.item ) then
		self:Debug(2, "Not recording location, as this quest was started by an item.")
		return
	-- No map data yet
	elseif( not self.mapToID[playerZone] ) then
		self:Debug(1, "Cannot record the location of NPC, no map id found for %s (%.2f, %.2f)", playerZone, playerX, playerY)
		return
	end
	
	-- Save the location
	local field = "objectData"
	if( questGiverType == self.dataToID.npc ) then
		field = "npcData"
	end
	
	local data = self[field][questGiverID]
	data.type = questGiverType
	
	table.insert(data.coords, self.mapToID[playerZone])
	table.insert(data.coords, playerX)
	table.insert(data.coords, playerY)

	self:Debug(1, "Found %s id %d at %.2f, %.2f in zone %s (%d).", self.idToData[questGiverType], questGiverID, playerX, playerY, playerZone, self.mapToID[playerZone])
end

function QDR:GetPlayerPosition()
	-- Store what map the player is currently in
	local currentCont = GetCurrentMapContinent()
	local currentZone = GetCurrentMapZone()
	local x, y, zone
	
	SetMapToCurrentZone()
	x, y = GetPlayerMapPosition("player")
	zone = GetMapInfo()
	SetMapZoom(currentCont, currentZone)
	
	-- In an instance without a map, or we don't have the map for the instance yet.
	if( IsInInstance() and ( x == 0 and y == 0 or not self.mapToID[zone] ) ) then
		return 0, 0, "instance"
	end

	return tonumber(string.format("%.2f", x * 100)), tonumber(string.format("%.2f", y * 100)), zone
end

-- Handle any incompatabilies that other mods can cause
function QDR:StripData(text)
	-- Strip [<level crap>] <quest title>
	text = string.gsub(text, "%[(.+)%]", "")
	-- Strip color codes
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x(.+)|r", "%1")
	-- Strip (low level) at the end of a quest
	text = string.gsub(text, "(.+) %((.+)%)", "%1")

	return string.trim(text)
end

-- Get the mob ID from GUID
function QDR:GetMobID(guid)
	if( not guid ) then return nil end
	local type = tonumber(string.sub(guid, 3, 5), 16)
	local mobType
	if( type == 3857 ) then
		mobType = self.dataToID.object
	elseif( type == 1024 ) then
		mobType = self.dataToID.item
	elseif( bit.band(tonumber(string.sub(guid, 3, 5), 16), 0x00f) == 3 ) then
		mobType = self.dataToID.npc
	else
		return nil
	end
	
	return tonumber(string.sub(guid, 8, 12), 16), mobType
end

-- Quest name from ID
function QDR:GetQuestName(questID)
	if( not self.tooltip ) then
		self.tooltip = CreateFrame("GameTooltip", "QuestDataRecTooltip", UIParent, "GameTooltipTemplate")
	end	
	
	self.tooltip:ClearLines()
	self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.tooltip:SetHyperlink(string.format("quest:%d", questID))
	
	return QuestDataRecTooltipTextLeft1:GetText()
end

function QDR:Deformat(text)
	text = string.gsub(text, "%.", "%%.")
	text = string.gsub(text, "%%s", "(.+)")
	text = string.gsub(text, "%%d", "([0-9]+)")
	
	return text
end

-- SV is about to be written, take everything that we have and turn it into our storage format
function QDR:PLAYER_LOGOUT()
	-- Save quest data
	for questID, questData in pairs(self.questData) do
		local objectives = ""
		for objID, objData in pairs(questData.objectives) do
			local coords = ""
			for _, coordData in pairs(objData.coords) do
				coords = string.format("%s%s;", coords, coordData)
			end
			
			local receivedItems = ""
			for itemID in pairs(objData.recitems) do
				receivedItems = string.format("%s[%s]=true;", receivedItems, itemID)
			end
			
			local reageantItems = ""
			for itemID in pairs(objData.reagitems) do
				reageantItems = string.format("%s[%s]=true;", droppedItems, itemID)
			end
			
			objectives = string.format("%s[%d]={type=%d;recitems={%s};reagitems={%s};coords={%s}};", objectives, objID, objData.type or 0, receivedItems, reageantItems, coords)
		end
		
		self.db.questdata[questID] = string.format("{stype=%d;sid=%d;etype=%d;eid=%d;objectives={%s}}", questData.stype or 0, questData.sid or 0, questData.etype or 0, questData.eid or 0, objectives)
	end
	
	-- Save NPC data
	for npcID, npcData in pairs(self.npcData) do
		local coords = ""
		for _, coordData in pairs(npcData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		local items = ""
		if( npcData.items ) then
			for _, itemData in pairs(npcData.items) do
				items = string.format("%s%s;", items, itemData)
			end
		end
		
		self.db.npcdata[npcID] = string.format("{type=%d;items={%s};coords={%s}}", npcData.type or 0, items, coords)
	end

	-- Save object data
	for objectID, objectData in pairs(self.objectData) do
		local coords = ""
		for _, coordData in pairs(objectData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		self.db.objectdata[objectID] = string.format("{type=%d;coords={%s}}", objectData.type or 0, coords)
	end
	
	-- Save item data
	for itemID, itemData in pairs(self.itemData) do
		local coords = ""
		for _, coordData in pairs(itemData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		self.db.itemdata[itemID] = string.format("{type=%d;coords={%s}}", itemData.type or 0, coords)
	end
end

-- Slash commands
SLASH_QUESTDATAREC1 = "/qdr"
SLASH_QUESTDATAREC2 = "/questdata"
SLASH_QUESTDATAREC3 = "/questdatarecorder"
SlashCmdList["QUESTDATAREC"] = function(msg)
	local self = QDR
	msg = string.lower(msg or "")
	
	if( msg == "reset" ) then
		if( not StaticPopupDialogs["QUESTDATAREC_CONFIRM_RESET"] ) then
			StaticPopupDialogs["QUESTDATAREC_CONFIRM_RESET"] = {
				text = L["Are you sure you want to reset ALL data recorded?"],
				button1 = L["Yes"],
				button2 = L["No"],
				OnAccept = function()
					QuestDataRecDB.npcData = {}
					QuestDataRecDB.questData = {}
					QuestDataRecDB.itemData = {}

					for k in pairs(QDR.npcData) do QDR.npcData[k] = nil end
					for k in pairs(QDR.questData) do QDR.questData[k] = nil end
					for k in pairs(QDR.itemData) do QDR.itemData[k] = nil end

					QDR:Print(L["All recorded data has been reset."])
				end,
				timeout = 30,
				whileDead = 1,
				hideOnEscape = 1,
			}
		end
		
		StaticPopup_Show("QUESTDATAREC_CONFIRM_RESET")
	
	elseif( msg == "export" ) then
		self:ExportData()
	elseif( msg == "stop" ) then
		self.db.stopped = true
		self:Print(L["Quest recording has been stopped until you start it again."])
		self:StopRecording()
	elseif( msg == "start" ) then
		self.db.stopped = false
		self:Print(L["Quest recording has been started."])
		self:StartRecording()
	else
		self:Echo(L["/qdr reset - Resets the saved quest database"])
		self:Echo(L["/qdr stop - Stop recording quest data, you will have to manually start it back up."])
		self:Echo(L["/qdr start - Start recording quest data"])
		self:Echo(L["/qdr export - Allows you to export recorded quest data to the website."])
	end
end

-- Check if we need to load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "ADDON_LOADED" ) then
		if( select(1, ...) == "QuestDataRecorder" ) then
			self:UnregisterEvent("ADDON_LOADED")

			QDR.frame = frame
			QDR:OnInitialize()
		end
	else
		QDR[event](QDR, event, ...)
	end
end)
frame:Hide()

-- Random output
function QDR:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Afflicted3|r: " .. msg)
end

function QDR:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function QDR:ExportData()
	local startTime = GetTime()

	self:CreateExportFrame()
	self.guiFrame:Show()
	self.guiFrame.title:SetText("Put web site URL here and such.")
	self.guiFrame.editBox:SetText(self:Compress())
	
	self:Debug(1, "Took %.2f seconds to initialize the edit box, and compress data.", GetTime() - startTime)
end

function QDR:CreateExportFrame()
	if( self.guiFrame ) then
		return
	end
	
	local backdrop = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
		tile = true,
		edgeSize = 1,
		tileSize = 5,
		insets = {left = 1, right = 1, top = 1, bottom = 1}
	}

	self.guiFrame = CreateFrame("Frame", nil, UIParent)
	self.guiFrame:SetWidth(550)
	self.guiFrame:SetHeight(275)
	self.guiFrame:SetBackdrop(backdrop)
	self.guiFrame:SetBackdropColor(0.0, 0.0, 0.0, 1.0)
	self.guiFrame:SetBackdropBorderColor(0.65, 0.65, 0.65, 1.0)
	self.guiFrame:SetMovable(true)
	self.guiFrame:EnableMouse(true)
	self.guiFrame:SetFrameStrata("HIGH")
	self.guiFrame:Hide()

	-- Fix edit box size
	self.guiFrame:SetScript("OnShow", function(self)
		self.child:SetHeight(self.scroll:GetHeight())
		self.child:SetWidth(self.scroll:GetWidth())
		self.editBox:SetWidth(self.scroll:GetWidth())
	end)
	
	-- Select all text
	self.guiFrame.copy = CreateFrame("Button", nil, self.guiFrame, "UIPanelButtonGrayTemplate")
	self.guiFrame.copy:SetWidth(70)
	self.guiFrame.copy:SetHeight(18)
	self.guiFrame.copy:SetText(L["Select all"])
	self.guiFrame.copy:SetPoint("TOPLEFT", self.guiFrame, "TOPLEFT", 1, -1)
	self.guiFrame.copy:SetScript("OnClick", function(self)
		self.editBox:SetFocus()
		self.editBox:SetCursorPosition(0)
		self.editBox:HighlightText(0)
	end)
	
	-- Title info
	self.guiFrame.title = self.guiFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	self.guiFrame.title:SetPoint("TOPLEFT", self.guiFrame, "TOPLEFT", 75, -4)
	
	-- Close button (Shocking!)
	local button = CreateFrame("Button", nil, self.guiFrame, "UIPanelCloseButton")
	button:SetPoint("TOPRIGHT", self.guiFrame, "TOPRIGHT", 6, 6)
	button:SetScript("OnClick", function()
		HideUIPanel(self.guiFrame)
	end)
	
	self.guiFrame.closeButton = button
	
	-- Create the container frame for the scroll box
	local container = CreateFrame("Frame", nil, self.guiFrame)
	container:SetHeight(265)
	container:SetWidth(1)
	container:ClearAllPoints()
	container:SetPoint("BOTTOMLEFT", self.guiFrame, 0, -9)
	container:SetPoint("BOTTOMRIGHT", self.guiFrame, 4, 0)
	
	self.guiFrame.container = container
	
	-- Scroll frame
	local scroll = CreateFrame("ScrollFrame", "QDRFrameScroll", container, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 5, 0)
	scroll:SetPoint("BOTTOMRIGHT", -28, 10)
	
	self.guiFrame.scroll = scroll
	
	local child = CreateFrame("Frame", nil, scroll)
	scroll:SetScrollChild(child)
	child:SetHeight(2)
	child:SetWidth(2)
	
	self.guiFrame.child = child

	-- Create the actual edit box
	local editBox = CreateFrame("EditBox", nil, child)
	editBox:SetPoint("TOPLEFT")
	editBox:SetHeight(50)
	editBox:SetWidth(50)

	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:EnableMouse(true)
	editBox:SetFontObject(GameFontHighlightSmall)
	editBox:SetTextInsets(0, 0, 0, 0)
	editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
	scroll:SetScript("OnMouseUp", function() editBox:SetFocus() end)	

	self.guiFrame.editBox = editBox
	self.guiFrame.copy.editBox = editBox

	self.guiFrame:SetPoint("CENTER", UIParent, "CENTER")
end

function QDR:Compress()
	--[[
		Converting decimals to whole numbers accounts for ~4% of the total compression
		Renaming fields to a shorter one is 8-12%
		Number mapping anything over 3 characters that occures >= 3 times is another 8%-12%
		LibCompress is around 40%
		overall it works out to 40% lib compress/20% everything else/60% total
		
		Everything takes <0.25 seconds, except for decimal conversion which can be half a second to a second.
	]]

	local DB = "{"
	for field, tbl in pairs(QuestDataRecDB) do
		if( field ~= "logs" and type(tbl) == "table" ) then
			-- All of the keys in the main table are strings, so we don't need to wrap them
			DB = string.format("%s%s={", DB, field)
			
			-- Now copy all of the content of these tables in
			for key, value in pairs(tbl) do
				DB = string.format("%s[%d]=%s;", DB, key, value)
			end

			DB = DB .. "}"
		end
	end

	DB = DB .. "}"
	
	-- Debug
	local startCharacters = string.len(DB)
	local startTime = GetTime()
	self:Debug(1, "Starting to compress quest data, initial characters %d, time is %s.", startCharacters, startTime)
	
	-- Rename fields into something that uses less characters
	local fieldConversion = {
		["coords="] = "c=",
		["type="] = "t=",
		["objectives="] = "o=",
		["questdata="] = "q=",
		["recitems="] = "reci=",
		["reagitems="] = "reai=",
		[";}"] = "}",
	}
	
	for find, replace in pairs(fieldConversion) do
		DB = string.gsub(DB, find, replace)
	end
	
	-- Remove any empty tables
	DB = string.gsub(DB, "([a-z]+)={}", "")
	
	-- Build a mapping to reduce the size of numbers that occur a lot
	local numbers = {}
	for num in string.gmatch(DB, "([0-9]+)") do
		if( string.len(num) >= 3 ) then
			numbers[num] = (numbers[num] or 0) + 1
		end
	end
	
	local mapDB = "{map={"
	local alphaTable = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"}
	local mainIndex = 1
	local secondIndex = 0
	local usingSecond
	
	local sortTbl = {}
	for num, occured in pairs(numbers) do
		if( occured >= 3 ) then
			table.insert(sortTbl, num)
		end
	end
	
	table.sort(sortTbl, function(a, b)
		return numbers[a] > numbers[b]
	end)
	
	for _, number in pairs(sortTbl) do
		local id = alphaTable[mainIndex]
		if( usingSecond ) then
			id = id .. alphaTable[secondIndex]
		end

		-- Store the mapping
		mapDB = string.format("%s%s=%d;", mapDB, id, number)
		-- Now convert it to our map
		DB = string.gsub(DB, number, id)

		if( secondIndex >= #(alphaTable) ) then
			secondIndex = 0
			mainIndex = mainIndex + 1

			if( mainIndex > #(alphaTable) ) then
				break
			end

		elseif( mainIndex >= #(alphaTable) ) then
			mainIndex = 1
			secondIndex = 1
			usingSecond = true
		end

		if( not usingSecond ) then
			mainIndex = mainIndex + 1
		else
			secondIndex = secondIndex + 1
		end
	end
	
	if( mapDB == "{map={" ) then
		mapDB = ""
	else
		mapDB = string.format("%s}", mapDB)
	end
	
	DB = string.format("%s%s", mapDB, DB)
	
	-- Debug
	local endCharacters = string.len(DB)
	self:Debug(1, "End characters %d (%d saved, %.2f%% compression), end time %s (%.2f taken)", endCharacters, startCharacters - endCharacters, 100 - (100 * (endCharacters / startCharacters)), GetTime(), GetTime() - startTime)
	
	return DB
end
