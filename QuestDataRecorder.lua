QDR = {}

local L = QuestDataRecLocals
local questGiverID, questGiven, questGiverX, questGiverY, questGiverZone, checkNextLog

function QDR:OnInitialize()
	QuestDataRecDB = QuestDataRecDB or {stopped = false, npcData = {}, questData = {}}

	self.db = QuestDataRecDB

	self.questData = setmetatable({}, {
		__index = function(tbl, index)
			tbl[index] = {objectives = {}}

			-- No data is cached yet
			if( not QDR.db.questData[index] ) then
				return tbl[index]
			end
			
			-- Format
			-- starts <npc/item/etc> #;ends <npc/item/etc> #;objectives objectiveID:zoneID:coordx,coordy;
		
			-- Parse it out
			local startType, startID, endType, endID, objectives = string.match(QDR.db.questData[index], "starts ([a-z]+) ([0-9]+);ends ([a-z]+) ([0-9]+);objectives (.+)")
			tbl[index].startType = startType
			tbl[index].starts = tonumber(startID)
			tbl[index].endType = endType
			tbl[index].ends = tonumber(endID)
			
			-- Parse objectives
			for objectiveID, zoneID, coords in string.gmatch(objectives, "([0-9]+):([0-9]+):([^;]+);") do
				objectiveID = tonumber(objectiveID)
				zoneID = tonumber(zoneID)
			
				tbl[index].objectives[objectiveID] = tbl[index].objectives[objectiveID] or {}
				tbl[index].objectives[objectiveID][zoneID] = tbl[index].objectives[objectiveID][zoneID] or {}
				table.insert(tbl[index].objectives[objectiveID][zoneID], coords)
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
			
			-- Format
			-- zoneID:coordx,coordY;zoneID:coordx,coordy;
			for zoneID, coords in string.gmatch(QDR.db.npcData[index], "([0-9]+):([^;]+);") do
				zoneID = tonumber(zoneID)
				
				tbl[index][zoneID] = tbl[index][zoneID] or {}
				table.insert(tbl[index][zoneID], coords)
			end
			
			return tbl[index]
		end
	})
		
	-- Recording
	if( not self.db.stopped ) then
		self:StartRecording()
	end
end

function QDR:StartRecording()
	self.frame:RegisterEvent("QUEST_FINISHED")
	self.frame:RegisterEvent("QUEST_DETAIL")
	self.frame:RegisterEvent("QUEST_LOG_UPDATE")
	self.frame:RegisterEvent("QUEST_PROGRESS")
end

function QDR:StopRecording()
end

-- Save that the quest starts at a mob
function QDR:QUEST_LOG_UPDATE(event)
	if( not checkNextLog ) then
		return
	end
	
	questGiven = self:StripData(questGiven)
	
	for i=1, GetNumQuestLogEntries() do
		local questName, _, _, _, isHeader = GetQuestLogTitle(i)
		if( not isHeader and self:StripData(questName) == questGiven ) then
			local questID = string.match(GetQuestLink(i), "|Hquest:(%d+):(%-?%d+)|h")
			questID = tonumber(questID)
			
			self.questData[questID].starts = questGiverID
			self.questData[questID].startType = "npc"
			print(string.format("NPC %d starts quest %d (%s)", questGiverID, questID, questName))
			break
		end
	end
	
	checkNextLog = nil
	questGiverID, questGiverX, questGiverY, questGiverZone, questGiven = nil, nil, nil, nil, nil
end

-- Can turn this quest in at them, save data
function QDR:QUEST_PROGRESS(event)
	local titleText = self:StripData(GetTitleText())
	local questID
	
	for i=1, GetNumQuestLogEntries() do
		local questName, _, _, _, isHeader = GetQuestLogTitle(i)
		if( not isHeader and self:StripData(questName) == titleText ) then
			questID = string.match(GetQuestLink(i), "|Hquest:(%d+):(%-?%d+)|h")
			break
		end
	end
	
	if( questID ) then
		questID = tonumber(questID)

		self.questData[questID].ends = self:GetMobID(UnitGUID("NPC"))
		self.questData[questID].endType = "npc"
		print(string.format("NPC %d (%s) ends quest %d (%s)", self.questData[questID].ends, (UnitName("NPC")), questID, titleText))
	end
end

-- We're looking at the details of the quest, save the quest info so we can use it later
function QDR:QUEST_DETAIL(event)
	-- When a player shares a quest with another player, the npc unitid gives you data for the player
	-- the quest was shared TO, not the player who SHARED the quest
	if( not UnitIsPlayer("npc") ) then
		questGiverID = self:GetMobID(UnitGUID("npc"))
		questGiven = GetTitleText()
	end
end

-- Flag so we know that the next quest log event has data we might want
function QDR:QUEST_FINISHED(event)
	if( questGiverID and questGiven ) then
		checkNextLog = true
		questGiverX, questGiverY, questGiverZone = self:GetPlayerLocation()
		
		-- Save this NPCs location
		local zoneID = self.mapData[questGiverZone]
		self.npcData[questGiverID][zoneID] = self.npcData[questGiverID][zoneID] or {}
		table.insert(self.npcData[questGiverID][zoneID], string.format("%.2f,%.2f", questGiverX, questGiverY))
		
		print(string.format("NPC %d is located at %.2f, %.2f in zone id %d.", questGiverID, questGiverX, questGiverY, zoneID))
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
	return tonumber(string.sub(guid, 8, 12), 16)
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