-- Luacheck settings for a World of Warcraft addon.
std = "lua51"
max_line_length = 140
self = false

-- Values the game client provides.
read_globals = {
    "CreateFrame", "UIParent", "GameTooltip", "WorldMapFrame", "Minimap", "UISpecialFrames",
    "hooksecurefunc", "InCombatLockdown", "GetTime", "issecretvalue",
    "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo",
    "IsFishingLoot", "GetCVar", "GetPlayerFacing",
    "UnitExists", "UnitIsPlayer", "UnitClassification", "UnitGUID", "UnitName",
    "IsInRaid", "IsInGroup", "IsInGuild",
    "C_Map", "C_Spell", "C_Minimap", "C_Timer", "C_ChatInfo",
    "date", "time",
}
-- Values the addon defines for the client to read.
globals = {
    "NodeNotesDB", "NodeNotesFrame", "SlashCmdList", "SLASH_NODENOTES1", "SLASH_NODENOTES2",
}
files["tests/harness.lua"] = { ignore = { "." } }
