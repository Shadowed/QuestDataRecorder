if( not QDR ) then return end

QDR.mapToID = {
	-- Instance maps
	["instance"] = 99,
	["WarsongGulch"] = 1,
	["AlteracValley"] = 2,
	["ArathiBasin"] = 3,
	["NetherstormArena"] = 4,
	["StrandoftheAncients"] = 5,
	["ScarletEnclave"] = 6,
	
	-- Kalimdor
	["Kalimdor"] = 100,
	["Ashenvale"] = 101,
	["Aszhara"] = 102,
	["AzuremystIsle"] = 103,
	["Barrens"] = 104,
	["BloodmystIsle"] = 105,
	["Darkshore"] = 106,
	["Darnassis"] = 107,
	["Desolace"] = 108,
	["Durotar"] = 109,
	["Dustwallow"] = 110,
	["Felwood"] = 111,
	["Feralas"] = 112,
	["Moonglade"] = 113,
	["Mulgore"] = 114,
	["Ogrimmar"] = 115,
	["Silithus"] = 116,
	["StonetalonMountains"] = 117,
	["Tanaris"] = 118,
	["Teldrassil"] = 119,
	["TheExodar"] = 120,
	["ThousandNeedles"] = 121,
	["ThunderBluff"] = 122,
	["UngoroCrater"] = 123,
	["Winterspring"] = 124,

	-- Eastern Kingdom
	["Azeroth"] = 200,
	["Alterac"] = 201,
	["Arathi"] = 202,
	["Badlands"] = 203,
	["BlastedLands"] = 204,
	["BurningSteppes"] = 205,
	["DeadwindPass"] = 206,
	["DunMorogh"] = 207,
	["Duskwood"] = 208,
	["EasternPlaguelands"] = 209,
	["Elwynn"] = 210,
	["EversongWoods"] = 211,
	["Ghostlands"] = 212,
	["Hilsbrad"] = 213,
	["Hinterlands"] = 214,
	["Ironforge"] = 215,
	["LochModan"] = 216,
	["Redridge"] = 217,
	["SearingGorge"] = 218,
	["SilvermoonCity"] = 219,
	["Silverpine"] = 220,
	["Stormwind"] = 221,
	["Stranglethorn"] = 222,
	["Sunwell"] = 223,
	["SwampOfSorrows"] = 224,
	["Tirisfal"] = 225,
	["Undercity"] = 226,
	["WesternPlaguelands"] = 227,
	["Westfall"] = 228,
	["Wetlands"] = 229,

	-- Outlands
	["Expansion01"] = 300,
	["BladesEdgeMountains"] = 301,
	["Hellfire"] = 302,
	["Nagrand"] = 303,
	["Netherstorm"] = 304,
	["ShadowmoonValley"] = 305,
	["ShattrathCity"] = 306,
	["TerokkarForest"] = 307,
	["Zangarmarsh"] = 308,
	
	-- Northrend
	["Northrend"] = 400,
	["BoreanTundra"] = 401,
	["CrystalsongForest"] = 402,
	["Dalaran"] = 403,
	["Dragonblight"] = 404,
	["GrizzlyHills"] = 405,
	["HowlingFjord"] = 406,
	["IcecrownGlacier"] = 407,
	["LakeWintergrasp"] = 408,
	["SholazarBasin"] = 409,
	["TheStormPeaks"] = 410,
	["ZulDrak"] = 411,
}

QDR.dataToID = {
	["none"] = 0,
	["npc"] = 1,
	["object"] = 2,
	["item"] = 3,
	["monster"] = 4,
	["reputation"] = 5,
	["event"] = 6,
	["player"] = 7,
}

-- This is mainly for debug purposes
QDR.idToData = {}
for key, value in pairs(QDR.dataToID) do
	QDR.idToData[value] = key
end