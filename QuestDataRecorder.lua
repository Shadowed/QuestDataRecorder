QDR = {}

local L = QuestDataRecLocals
local lootSelfFilter, lootSelfMultiFilter, questGiverID, questGiven, questGiverType, setToAbandon, abandonedName
local playerX, playerY, playerZone, questLog
local tempQuestLog, tempQuestItems, questPatterns, factionRanks = {}, {}, {}, {}
local isQuestItem, questItemsLost, questItemsGained, questItems = {}, {}, {}, {}

function QDR:OnInitialize()
	QuestDataRecDB = QuestDataRecDB or {debug = false, stopped = false, npcData = {}, objectData = {}, itemData = {}, questData = {}}
	self.db = QuestDataRecDB

	self.questData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {objectives = {}}

			-- No data is cached yet
			if( not QDR.db.questData[index] ) then
				return tbl[index]
			end
			
			
			tbl[index] = loadstring("return " .. QDR.db.questData[index])()

			return tbl[index]
		end
	})
	
	self.npcData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.npcData[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.npcData[index])()
			
			return tbl[index]
		end
	})

	self.objectData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.objectData[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.objectData[index])()
			
			return tbl[index]
		end
	})
	
	self.itemData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {coords = {}}
			
			-- No data is cached yet
			if( not QDR.db.itemData[index] ) then
				return tbl[index]
			end
			
			tbl[index] = loadstring("return " .. QDR.db.itemData[index])()
			
			return tbl[index]
		end
	})
	
	-- Loot patterns
	lootSelfFilter = self:Deformat(LOOT_ITEM_SELF)
	lootSelfMultiFilter = self:Deformat(LOOT_ITEM_SELF_MULTIPLE)
	
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
	self.frame:RegisterEvent("CHAT_MSG_LOOT")
	self.frame:RegisterEvent("BAG_UPDATE")
end

function QDR:StopRecording()
	self.frame:UnregisterEvent("QUEST_DETAIL")
	self.frame:UnregisterEvent("QUEST_LOG_UPDATE")
	self.frame:UnregisterEvent("QUEST_COMPLETE")
	self.frame:UnregisterEvent("CHAT_MSG_LOOT")
	self.frame:UnregisterEvent("BAG_UPDATE")
end

function QDR:Debug(text, ...)
	if( self.db.debug ) then
		print(string.format(text, ...))
	end
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

				tempQuestItems[tonumber(itemID)] = count
			end
		end
	end
		
	local timeout = GetTime() + 0.70
	-- Lost a quest item
	for itemID, count in pairs(questItems) do
		if( not tempQuestItems[itemID] or tempQuestItems[itemID] < count ) then
			questItemsLost[itemID] = timeout
			self:Debug("[%s] Lost quest item %d, we had %d of it before.", GetTime(), itemID, tempQuestItems[itemID] or 0)
		end
	end

	-- Gained a quest item
	for itemID, count in pairs(tempQuestItems) do
		if( not questItems[itemID] or questItems[itemID] < count ) then
			questItemsGained[itemID] = timeout
			self:Debug("[%s] Gained quest item %d, we had %d of it before.", GetTime(), itemID, questItems[itemID] or 0)
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

-- Record item loot
function QDR:CHAT_MSG_LOOT(event, msg)
	local itemLink = string.match(msg, lootSelfFilter)
	if( not itemLink ) then
		itemLink = string.match(msg, lootSelfMultiFilter)
	end
	
	-- Got loot to parse
	if( self:IsQuestItem(itemLink) ) then
		local itemID = string.match(itemLink, "item:([0-9]+)")
		local x, y, zone = self:GetPlayerPosition()

		itemID = tonumber(itemID)
		
		table.insert(self.itemData[itemID].coords, self.mapToID[zone])
		table.insert(self.itemData[itemID].coords, x)
		table.insert(self.itemData[itemID].coords, y)
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
			if( not questLog[tempID] ) then
				self:RecordNPCLocation()
				
				self.questData[tempID].sid = questGiverID
				self.questData[tempID].stype = questGiverType
				
				self:Debug("%s ID %d starts %s (%d).", self.idToData[questGiverType], questGiverID, self:GetQuestName(tempID) or "?", tempID)
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
				
				self:Debug("%s ID %d ends %s (%d).", self.idToData[questGiverType], questGiverID, self:GetQuestName(questID) or "?", questID)
			elseif( abandonedName == questName ) then
				self:Debug("Abandoned %s.", abandonedName)
				
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
					questObjective.dropitems = questObjective.dropitems or {}
					questObjective.recitems = questObjective.recitems or {}
					questObjective.type = self.dataToID[tempObjData.type]

					table.insert(questObjective.coords, zoneID)
					table.insert(questObjective.coords, x)
					table.insert(questObjective.coords, y)
					
					self:Debug("[%s] Objective %d (%s) changed for %s (%d) at %.2f, %.2f.", GetTime(), objID, tempObjData.type, self:GetQuestName(questID) or "?", questID, x, y)

					-- Do we have an item that should be associated?
					for itemID, timeout in pairs(questItemsLost) do
						if( time < timeout ) then
							if( not questObjective.dropitems[itemID] ) then
								self:Debug("Associating item id %d as an objective of %d, as it was removed from inventory.", itemID, objID)
							end
							
							questObjective.dropitems[itemID] = true
						end
						
						questItemsLost[itemID] = nil
					end

					-- Do we have an item that should be associated?
					for itemID, timeout in pairs(questItemsGained) do
						if( time < timeout ) then
							if( not questObjective.recitems[itemID] ) then
								self:Debug("Associating item id %d as an objective of %d, as it was put into the inventory.", itemID, objID)
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
			self:Debug("Failed to associate NPC id for %s (%s) to %s, cannot find the item it was from.", (UnitName("npc")) or "?", questGiverType, questGiven)
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
		self:Debug("Not recording location, as this quest was started by an item.")
		return
	-- No map data yet
	elseif( not self.mapToID[playerZone] ) then
		self:Debug("Cannot record the location of NPC, no map id found for %s (%.2f, %.2f)", playerZone, playerX, playerY)
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

	self:Debug("Found %s id %d at %.2f, %.2f in zone %s (%d).", self.idToData[questGiverType], questGiverID, playerX, playerY, playerZone, self.mapToID[playerZone])
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
	
	-- Players in an instance, and no coords found so no map for it
	if( x == 0 and y == 0 and IsInInstance() ) then
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
	elseif( type == 3859 ) then
		mobType = self.dataToID.npc
	elseif( type == 1024 ) then
		mobType = self.dataToID.item
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
				receivedItems = string.format("%s[%s] = true;", receivedItems, itemID)
			end
			
			local droppedItems = ""
			for itemID in pairs(objData.dropitems) do
				droppedItems = string.format("%s[%s] = true;", droppedItems, itemID)
			end
			
			objectives = string.format("%s[%d]={type=%d;recitems={%s};dropitems={%s};coords={%s}};", objectives, objID, objData.type or 0, receivedItems, droppedItems, coords)
		end
		
		self.db.questData[questID] = string.format("{stype=%d;sid=%d;etype=%d;eid=%d;objectives={%s}}", questData.stype or 0, questData.sid or 0, questData.etype or 0, questData.eid or 0, objectives)
	end
	
	-- Save NPC data
	for npcID, npcData in pairs(self.npcData) do
		local coords = ""
		for _, coordData in pairs(npcData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		self.db.npcData[npcID] = string.format("{type=%d;coords={%s}}", npcData.type or 0, coords)
	end

	-- Save object data
	for objectID, objectData in pairs(self.objectData) do
		local coords = ""
		for _, coordData in pairs(objectData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		self.db.objectData[objectID] = string.format("{type=%d;coords={%s}}", objectData.type or 0, coords)
	end
	
	-- Save item data
	for itemID, itemData in pairs(self.itemData) do
		local storage = ""
		local coords = ""
		for _, coordData in pairs(itemData.coords) do
			coords = string.format("%s%s;", coords, coordData)
		end
		
		self.db.itemData[itemID] = string.format("{coords={%s}}", coords)
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