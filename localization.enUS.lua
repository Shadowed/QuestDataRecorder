QuestDataRecLocals = {
	-- This is the match that should be used if it fails to find the quest objective amounts
	-- "Scarlet Ballista destroyed: 100/150" is an example of where this is used
	["(%d+)/(%d+)$"] = "(%d+)/(%d+)$",

	-- Slash commands
	["/qdr reset - Resets the saved quest database"] = "/qdr reset - Resets the saved quest database",
	["/qdr stop - Stop recording quest data, you will have to manually start it back up."] = "/qdr stop - Stop recording quest data, you will have to manually start it back up.",
	["/qdr start - Start recording quest data"] = "/qdr start - Start recording quest data",
	["/qdr export - Allows you to export recorded quest data to the website."] = "/qdr export - Allows you to export recorded quest data to the website.",
	
	["Quest recording has been stopped until you start it again."] = "Quest recording has been stopped until you start it again.",
	["Quest recording has been started."] = "Quest recording has been started.",
	
	["All recorded data has been reset."] = "All recorded data has been reset.",
	["Are you sure you want to reset ALL data recorded?"] = "Are you sure you want to reset ALL data recorded?",
	["Yes"] = "Yes",
	["No"] = "No",
	
	["Select all"] = "Select all",
}