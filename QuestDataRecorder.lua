QDR = {}

local L = QuestDataRecLocals
local playerX, playerY, playerZone
local questGiverID, questGiven, questFinished, questGiverType
local tempQuestLog, tempQuestIDList, questLog, questIDList = {}, {}
local lootList = {}

function QDR:OnInitialize()
	QuestDataRecDB = QuestDataRecDB or {stopped = false, npcData = {}, itemData = {}, questData = {}}
	self.db = QuestDataRecDB

	self.questData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {objectives = {}}

			-- No data is cached yet
			if( not QDR.db.questData[index] ) then
				return tbl[index]
			end
			
			-- Parse it out
			local startType, startID, endType, endID, objectivesType, objectives = string.match(QDR.db.questData[index], "starts ([a-z]+):([0-9]+);ends ([a-z]+):([0-9]+);objtypes (.+);objectives (.+)")
			tbl[index].startType = startType
			tbl[index].starts = tonumber(startID)
			tbl[index].endType = endType
			tbl[index].ends = tonumber(endID)
			
			-- Parse objectives
			if( objectives ~= "none" ) then
				for objectiveID, zoneID, coords in string.gmatch(objectives, "([0-9]+):([0-9]+):([^&]+)&") do
					objectiveID = tonumber(objectiveID)
					zoneID = tonumber(zoneID)

					tbl[index].objectives[objectiveID] = tbl[index].objectives[objectiveID] or {}
					tbl[index].objectives[objectiveID][zoneID] = tbl[index].objectives[objectiveID][zoneID] or {}

					for coordX, coordY in string.gmatch(coords, "([^,]+),([^*]+)*") do
						table.insert(tbl[index].objectives[objectiveID][zoneID], string.format("%s,%s", coordX, coordY))
					end
				end
			end
				
			-- Now parse there types
			if( objectivesType ~= "none" ) then
				for objectiveID, objectiveType in string.gmatch(objectivesType, "([0-9]+):([^&]+)&") do
					tbl[index].objectives[objectiveID] = tbl[index].objectives[objectiveID] or {}
					tbl[index].objectives[objectiveID].type = objectiveType
				end
			end
			
			return tbl[index]
		end
	})
	
	self.npcData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {}
			
			-- No data is cached yet
			if( not QDR.db.npcData[index] ) then
				return tbl[index]
			end
			
			local type, data = string.match(QDR.db.npcData[index], "([a-z]+);(.+)")
			tbl[index].type = type
			
			for zoneID, coords in string.gmatch(data, "([0-9]+):([^;]+);") do
				zoneID = tonumber(zoneID)
				
				tbl[index][zoneID] = tbl[index][zoneID] or {}
				for coordX, coordY in string.gmatch(coords, "([^,]+),([^*]+)*") do
					table.insert(tbl[index][zoneID], string.format("%s,%s", coordX, coordY))
				end
			end
			
			return tbl[index]
		end
	})
	
	self.itemData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {}
			
			-- No data is cached yet
			if( not QDR.db.itemData[index] ) then
				return tbl[index]
			end
			
			for zoneID, coords in string.gmatch(QDR.db.itemData[index], "([0-9]+):([^;]+);") do
				zoneID = tonumber(zoneID)
				
				tbl[index][zoneID] = tbl[index][zoneID] or {}
				for coordX, coordY in string.gmatch(coords, "([^,]+),([^*]+)*") do
					table.insert(tbl[index][zoneID], string.format("%s,%s", coordX, coordY))
				end
			end
			
			return tbl[index]
		end
	})
		
	-- Hook the loot function so we can record an item looted and such
	hooksecurefunc("LootSlot", function(index)
		if( lootList[index] ) then
			self:RecordLootDrop(lootList[index])
			lootList[index] = nil
		end
	end)
	
	-- Recording
	if( not self.db.stopped ) then
		self:StartRecording()
	end
end

-- DEBUG (OBVIOUSLY)
function QDR:Debug(msg)
	if( self.db.log ) then
		table.insert(self.db.log, string.format("[%s] %s", GetTime(), msg))
	end
end

--[[
	In 3.1, I might be able to use QUEST_ACCEPTED instead of QUEST_FINISHED. Although, it has the same limitations
	with the NPC unitid becoming unusable so I still need to save info on QUEST_DETAIL.
]]
function QDR:StartRecording()
	self.frame:RegisterEvent("QUEST_FINISHED")
	self.frame:RegisterEvent("QUEST_DETAIL")
	self.frame:RegisterEvent("QUEST_LOG_UPDATE")
	self.frame:RegisterEvent("QUEST_COMPLETE")
	self.frame:RegisterEvent("LOOT_OPENED")
end

function QDR:StopRecording()
end

function QDR:LOOT_OPENED(event, autoLoot)
	playerX, playerY, playerZone = self:GetPlayerLocation()
	
	for k in pairs(lootList) do lootList[k] = nil end
	for i=1, GetNumLootItems() do
		local link = GetLootSlotLink(i)
		if( link ) then
			if( autoLoot ) then
				self:RecordLootDrop(link)
			else
				lootList[i] = link
			end
		end
	end
end

function QDR:RecordLootDrop(link)
	local itemType, subType = select(6, GetItemInfo(link))
	if( itemType == "Quest" and subType == "Quest" ) then
		local itemID = string.match(link, "item:([0-9]+)")
		local zoneID = self.mapData[playerZone]

		itemID = tonumber(itemID)
		self.itemData[itemID][zoneID] = self.itemData[itemID][zoneID] or {}
		table.insert(self.itemData[itemid][zoneID], string.format("%.2f,%.2f", playerX, playerY))

		self:Debug(string.format("Item looted %d in %d at %.2f, %.2f.", itemID, zoneID, playerX, playerY))
	end
end

-- Quest log updated, see what changed quest-wise
-- NTS: Redo this function to use two tables at most to make it more sane to work with
function QDR:QUEST_LOG_UPDATE(event)
	-- Reset our temp quest data first
	for k in pairs(tempQuestIDList) do tempQuestIDList[k] = nil end
	for _, data in pairs(tempQuestLog) do 
		for _, objData in pairs(data.objectives) do
			for k in pairs(objData) do
				objData[k] = nil
			end
		end
	end
	
	local time = GetTime()
	
	-- Scan quest log
	local questID
	local foundQuests = 0
	local index = 1
	local numQuests = select(2, GetNumQuestLogEntries())
	while( foundQuests <= numQuests ) do
		local questName, _, _, _, isHeader = GetQuestLogTitle(index)
		if( not questName ) then break end
		
		if( not isHeader ) then
			foundQuests = foundQuests + 1
			
			questID = string.match(GetQuestLink(index), "|Hquest:(%d+):(%-?%d+)|h")
			questID = tonumber(questID)
			
			tempQuestLog[foundQuests] = tempQuestLog[foundQuests] or {objectives = {}}
			
			local questData = tempQuestLog[foundQuests]
			questData.updateLock = 0
			questData.questName = questName
			questData.questID = questID
			tempQuestIDList[questID] = foundQuests

			for objID=1, GetNumQuestLeaderBoards(index) do
				local text, type, finished = GetQuestLogLeaderBoard(objID, index)
				questData.objectives[objID] = questData.objectives[objID] or {}
				questData.objectives[objID].text = text
				questData.objectives[objID].type = type
				questData.objectives[objID].finished = finished
				questData.objectives[objID].id = text .. type .. (finished and "true" or "false")
			end
		end
		
		index = index + 1
	end
	
	-- We don't have any previous data to go off of yet, so start us off
	if( not questLog ) then
		questLog = CopyTable(tempQuestLog)
		questIDList = CopyTable(tempQuestIDList)
		return
	end
	
	local tempID = ""
	local pID = ""
	for k in pairs(tempQuestIDList) do tempID = tempID .. k .. ", " end
	for k in pairs(questIDList) do pID = pID .. k .. ", " end
	
	self:Debug(string.format("Quests updated, found %s / had %s", tempID, pID))
		
	-- We have some quest giver info, check if we either accepted or completed a quest
	-- Find quests we accepted
	if( questGiverID ) then
		for questID, mapID in pairs(tempQuestIDList) do
			if( not questIDList[questID] ) then
				-- We lock the objective updates for half a second after accepting, this prevents
				-- bad objective change data from happening
				tempQuestLog[mapID].updateLock = time + 0.50
				
				self.questData[questID].starts = questGiverID
				self.questData[questID].startType = questGiverType

				print(string.format("NPC %d starts quest %d", questGiverID, questID))
				self:Debug(string.format("Accepted quest %s from %s (%s).", questID, questGiverID, questGiverType))
			end
		end

		if( questFinished ) then
			questFinished = nil
			self:Debug(string.format("Checking if we finished a finished."))
			
			-- Found quests we completed
			for questID, mapID in pairs(questIDList) do
				if( not tempQuestIDList[questID] ) then
					questLog[mapID].updateLock = time + 1
					
					self.questData[questID].ends = questGiverID
					self.questData[questID].endType = questGiverType

					print(string.format("NPC %d ends quest %d (%s)", self.questData[questID].ends, questID, questGiven))
					self:Debug(string.format("Ended quest %s on %s (%s)", questID, questGiverID, questGiverType))
				end
			end
		end
	end
		
	-- Now find out what objectives changed
	for questID, mapID in pairs(tempQuestIDList) do
		-- We have this quest last update, so we can compare it
		if( questIDList[questID] ) then
			
			local questData = questLog[questIDList[questID]]
			if( questData.updateLock < time ) then
				for objID, objData in pairs(tempQuestLog[mapID].objectives) do
					if( questData.objectives[objID] and questData.objectives[objID].id and questData.objectives[objID].id ~= objData.id ) then
						local x, y, zone = self:GetPlayerLocation()
						local zoneID = self.mapData[zone]

						self.questData[questID].objectives[objID] = self.questData[questID].objectives[objID] or {}
						self.questData[questID].objectives[objID].type = objData.type
						self.questData[questID].objectives[objID][zoneID] = self.questData[questID].objectives[objID][zoneID] or {}

						table.insert(self.questData[questID].objectives[objID][zoneID], string.format("%.2f,%.2f", x, y))

						print(string.format("Recorded quest id %d, objective id %d (type %s), in %.2f, %.2f", questID, objID, objData.type, x, y))
						self:Debug(string.format("Objectives changed \"%s\" %s for %d at %.2f, %.2f.", objData.text, objData.type, questID, x, y))
					end
				end
			end
		end
	end
			
	-- Reset what we had last time
	for questID, mapID in pairs(questIDList) do
		questIDList[questID] = nil
	end
	
	for _, questData in pairs(questLog) do
		questData.questName = nil
		questData.questID = nil
		
		for id, data in pairs(questData.objectives) do
			data.text = nil
			data.type = nil
			data.id = nil
			data.finished = nil
		end
	end
	
	-- Now copy over the new stuff
	for questID, mapID in pairs(tempQuestIDList) do
		local questData = tempQuestLog[mapID]
		questIDList[questID] = mapID
		
		questLog[mapID] = questLog[mapID] or {objectives = {}}
		questLog[mapID].updateLock = questData.updateLock
		questLog[mapID].questName = questData.questName
		questLog[mapID].questID = questData.questID

		for objID, data in pairs(questData.objectives) do
			questLog[mapID].objectives[objID] = questLog[mapID].objectives[objID] or {}
			
			for k, v in pairs(data) do
				questLog[mapID].objectives[objID][k] = v
			end
		end
	end
end

function QDR:QUEST_COMPLETE(event)
	questGiverID, questGiverType = self:GetMobID(UnitGUID("npc"))
	questGiven = self:StripData(GetTitleText())
	playerX, playerY, playerZone = self:GetPlayerLocation()
	questFinished = true
	
	self:Debug(string.format("Event quest completed %s on %s (%s) flagged for finished.", questGiven, questGiverID, questGiverType))
end

-- We're looking at the details of the quest, save the quest info so we can use it later
function QDR:QUEST_DETAIL(event)
	-- When a player shares a quest with another player, the npc unitid gives you data for the player
	-- the quest was shared TO, not the player who SHARED the quest
	if( not UnitIsPlayer("npc") ) then
		questGiverID, questGiverType = self:GetMobID(UnitGUID("npc"))
		self:Debug(string.format("Event quest details, on %s (%s)", questGiverID, questGiverType))
	else
		questGiverID = nil
	end
end

-- Flag so we know that the next quest log event has data we might want
function QDR:QUEST_FINISHED(event)
	if( questGiverID ) then
		playerX, playerY, playerZone = self:GetPlayerLocation()
		
		-- Save this NPCs location
		local zoneID = self.mapData[playerZone]
		self.npcData[questGiverID].type = questGiverType
		self.npcData[questGiverID][zoneID] = self.npcData[questGiverID][zoneID] or {}
		table.insert(self.npcData[questGiverID][zoneID], string.format("%.2f,%.2f", playerX, playerY))
		
		print(string.format("NPC %d (%s) is located at %.2f, %.2f in zone id %d.", questGiverID, questGiverType, playerX, playerY, zoneID))
		self:Debug(string.format("Event quest finished, on %s (%s) at %.2f, %.2f.", questGiverID, questGiverType, playerX, playerY))
	end
end

function QDR:GetPlayerLocation()
	-- Store what map the player is currently in
	local currentCont = GetCurrentMapContinent()
	local currentZone = GetCurrentMapZone()
	local x, y, zone
	
	SetMapToCurrentZone()
	x, y = GetPlayerMapPosition("player")
	zone = GetMapInfo()
	SetMapZoom(currentCont, currentZone)

	return x * 100, y * 100, zone
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
	local type = bit.band(tonumber(string.sub(guid, 3, 5), 16), 0x00f)
	local mobType
	if( type == 1 ) then
		mobType = "object"	
	elseif( type == 3 ) then
		mobType = "npc"		
	else
		return nil
	end
	
	return tonumber(string.sub(guid, 8, 12), 16), mobType
end

-- SV is about to be written, take everything that we have and turn it into our storage format
function QDR:PLAYER_LOGOUT()
	-- Save quest data
	for questID, questData in pairs(self.questData) do
		local objStorage = ""
		local typeStorage = ""
		
		for objID, objData in pairs(questData.objectives) do
			typeStorage = string.format("%s%s:%s&", typeStorage, objID, objData.type or "none")
			
			for zoneID, coords in pairs(objData) do
				if( zoneID ~= "type" ) then
					local coordStorage = ""
					for _, coord in pairs(coords) do
						coordStorage = coordStorage .. coord .. "*"
					end

					objStorage = string.format("%s%s:%s:%s&", objStorage, objID, zoneID, coordStorage)
				end
			end
		end
		
		if( typeStorage == "" ) then
			typeStorage = "none"
		end
		
		if( objStorage == "" ) then
			objStorage = "none"
		end

		self.db.questData[questID] = string.format("starts %s:%d;ends %s:%d;objtypes %s;objectives %s", questData.startType or "none", questData.starts or 0, questData.endType or "none", questData.ends or 0, typeStorage, objStorage)
	end
	
	-- Save NPC data
	for npcID, npcData in pairs(self.npcData) do
		local storage = ""
		for zoneID, coords in pairs(npcData) do
			if( zoneID ~= "type" ) then
				local coordStorage = ""
				for _, coord in pairs(coords) do
					coordStorage = coordStorage .. coord .. "*"
				end

				storage = string.format("%s%d:%s;", storage, zoneID, coordStorage)
			end
		end
		
		self.db.npcData[npcID] = string.format("%s;%s", npcData.type or "none", storage)
	end
	
	-- Save item data
	for itemID, itemData in pairs(self.itemData) do
		local storage = ""
		for zoneID, coords in pairs(itemdata) do
			local coordStorage = ""
			for _, coord in pairs(coords) do
				coordStorage = coordStorage .. coord .. "*"
			end
			
			storage = string.format("%s%d:%s;", storage, zoneID, coordStorage)
		end
		
		self.db.itemdata[itemID] = storage
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

-- Random output
function QDR:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Afflicted3|r: " .. msg)
end

function QDR:Echo(msg)
	DEFAULT_CHAT_FRAME:AddMessage(msg)
end