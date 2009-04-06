QDR = {}

local L = QuestDataRecLocals
local lootSelfFilter, lootSelfMultiFilter
local playerX, playerY, playerZone, questGiverID, questGiven, questGiverType, setToAbandon, abandonedName
local tempQuestLog, tempQuestIDList, questLog, questIDList = {}, {}
local questPatterns, factionRanks = {}

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
	self.frame:RegisterEvent("QUEST_DETAIL")
	self.frame:RegisterEvent("QUEST_LOG_UPDATE")
	self.frame:RegisterEvent("QUEST_COMPLETE")
	self.frame:RegisterEvent("CHAT_MSG_LOOT")
end

function QDR:StopRecording()
	self.frame:UnregisterEvent("QUEST_DETAIL")
	self.frame:UnregisterEvent("QUEST_LOG_UPDATE")
	self.frame:UnregisterEvent("QUEST_COMPLETE")
	self.frame:UnregisterEvent("CHAT_MSG_LOOT")
end

function QDR:CHAT_MSG_LOOT(event, msg)
	local itemLink = string.match(msg, lootSelfFilter)
	if( not itemLink ) then
		itemLink = string.match(msg, lootSelfMultiFilter)
	end
	
	-- Got loot to parse
	if( itemLink ) then
		local itemType, subType = select(6, GetItemInfo(itemLink))
		if( itemType == "Quest" and subType == "Quest" ) then
			local itemID = string.match(itemLink, "item:([0-9]+)")
			local x, y, zone = self:GetPlayerPosition()

			itemID = tonumber(itemID)

			table.insert(self.itemData[itemID].coords, self.mapToID[zone])
			table.insert(self.itemData[itemID].coords, x)
			table.insert(self.itemData[itemID].coords, y)

			self:Debug(string.format("Item looted %d in %d at %.2f, %.2f.", itemID, self.mapToID[zone], x, y))
		end
	end
end

function QDR:Deformat(text)
	text = string.gsub(text, "%.", "%%.")
	text = string.gsub(text, "%%s", "(.+)")
	text = string.gsub(text, "%%d", "([0-9]+)")
	
	return text
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
				local current, max
				if( type == "player" ) then
					current, max = string.match(text, questPatterns[type])
					current = tonumber(current)
					max = tonumber(max)
				elseif( type == "reputation" ) then
					local currentLevel, neededLevel = select(2, string.match(text, questPatterns[type]))
					current = factionRanks[currentLevel]
					max = factionRanks[neededLevel]
				elseif( questPatterns[type] ) then
					current, max = select(2, string.match(text, questPatterns[type]))
					if( not current or not max ) then
						current, max = string.match(text, L["(%d+)/(%d+)$"])
					end
					
					current = tonumber(current)
					max = tonumber(max)
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
		
	-- Find quests we accepted
	for questID, mapID in pairs(tempQuestIDList) do
		if( questGiverID and not questIDList[questID] ) then
			self:RecordNPCLocation()

			-- We lock the objective updates for half a second after accepting, this prevents
			-- bad objective change data from happening
			tempQuestLog[mapID].updateLock = time + 0.50

			self.questData[questID].sid = questGiverID
			self.questData[questID].stype = questGiverType

			print(string.format("NPC %d starts quest %d", questGiverID, questID))
			self:Debug(string.format("Accepted quest %s from %s (%s).", questID, questGiverID, questGiverType))
		end
	end

	-- Found quests we completed/abandoned
	for questID, mapID in pairs(questIDList) do
		if( not tempQuestIDList[questID] ) then
			local questName = self:GetQuestName(questID)
			if( questGiverID and ( not abandonedName or abandonedName ~= questName ) ) then
				self:RecordNPCLocation()

				questLog[mapID].updateLock = time + 1

				self.questData[questID].eid = questGiverID
				self.questData[questID].etype = questGiverType

				print(string.format("NPC %d ends quest %d (%s)", self.questData[questID].eid, questID, questGiven))
				self:Debug(string.format("Ended quest %s on %s (%s)", questID, questGiverID, questGiverType))
			elseif( abandonedName == questName ) then
				print(string.format("Abandoned quest %s.", abandonedName))
				self:Debug(string.format("Quest abandoned %s", abandonedName))
				abandonedName = nil
				break
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
					if( questData.objectives[objID] and questData.objectives[objID].current and objData.current and questData.objectives[objID].current < objData.current ) then
						local x, y, zone = self:GetPlayerPosition()
						local zoneID = self.mapToID[zone]

						self.questData[questID].objectives[objID] = self.questData[questID].objectives[objID] or {coords = {}}
						self.questData[questID].objectives[objID].type = self.dataToID[objData.type]
				
						table.insert(self.questData[questID].objectives[objID].coords, zoneID)
						table.insert(self.questData[questID].objectives[objID].coords, x)
						table.insert(self.questData[questID].objectives[objID].coords, y)

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
	playerX, playerY, playerZone = self:GetPlayerPosition()
	
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

function QDR:RecordNPCLocation()
	playerX, playerY, playerZone = self:GetPlayerPosition()

	-- Save this NPCs location
	local zoneID = self.mapToID[playerZone]
	self.npcData[questGiverID].type = questGiverType
	table.insert(self.npcData[questGiverID].coords, zoneID)
	table.insert(self.npcData[questGiverID].coords, playerX)
	table.insert(self.npcData[questGiverID].coords, playerY)

	print(string.format("NPC %d (%s) is located at %.2f, %.2f in zone id %d.", questGiverID, questGiverType, playerX, playerY, zoneID))
	self:Debug(string.format("Event quest finished, on %s (%s) at %.2f, %.2f.", questGiverID, questGiverType, playerX, playerY))
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
	local type = bit.band(tonumber(string.sub(guid, 3, 5), 16), 0x00f)
	local mobType
	if( type == 1 ) then
		mobType = self.dataToID.object
	elseif( type == 3 ) then
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
		self.tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end	
	
	self.tooltip:ClearLines()
	self.tooltip:SetHyperlink(string.format("quest:%d", questID))
	
	return QuestDataRecTooltipTextLeft1:GetText()
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
			objectives = string.format("%s[%d]={type=%d;coords={%s}};", objectives, objID, objData.type or 0, coords)
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

					QDR.npcData = {}
					QDR.questData = {}
					QDR.itemData = {}

					QDR:Print(L["All recorded data has been reset."])
				end,
				timeout = 30,
				whileDead = 1,
				hideOnEscape = 1,
			}
		end
		
		StaticPopup_Show("TOMTOM_REMOVE_ALL_CONFIRM")
	
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