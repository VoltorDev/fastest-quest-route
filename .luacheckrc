-- luacheck para un addon de WoW Forever (Lua 5.1).
-- Que cada API exista DE VERDAD en Forever lo comprueba api_forever.py; aquí se declara
-- qué globales lee el addon, para que una errata en un nombre salte como "undefined variable".
std = "lua51"
max_line_length = 120
exclude_files = { "Libs/", ".release/", "tools/", ".luacheckrc" }

ignore = {
    "212/self", -- self sin usar en métodos
}

-- Globales que el addon CREA o modifica.
globals = {
    "RutaMisionesDB",
    "RutaMisionesCharDB",
    "SLASH_RUTAMISIONES1",
    "SLASH_RUTAMISIONES2",
    "SlashCmdList",
    "RutaMisiones_OnAddonCompartmentClick",
    "RutaMisiones_OnAddonCompartmentEnter",
    "RutaMisiones_OnAddonCompartmentLeave",
}

-- API de WoW que el addon lee. Añade aquí cada global nueva que uses.
read_globals = {
    "OpenWorldMap",
    "IsMounted",
    "GetUnitSpeed",
    "C_TaxiMap",
    "CreateVector2D",
    "IsShiftKeyDown",
    "UnitFactionGroup",
    "C_GossipInfo",
    "GetNumActiveQuests",
    "GetActiveTitle",
    "GetActiveQuestID",
    "SelectActiveQuest",
    "GetNumAvailableQuests",
    "GetAvailableQuestInfo",
    "SelectAvailableQuest",
    "QuestGetAutoAccept",
    "QuestIsFromAreaTrigger",
    "AcknowledgeAutoAcceptQuest",
    "QuestFlagsPVP",
    "GetQuestID",
    "AcceptQuest",
    "IsQuestCompletable",
    "CompleteQuest",
    "GetNumQuestChoices",
    "GetQuestMoneyToGet",
    "GetQuestReward",
    "GetTime",
    "C_Map",
    "C_QuestLog",
    "C_SuperTrack",
    "C_Timer",
    "GetQuestLogRewardXP",
    "UiMapPoint",
    "UnitClass",
    "UnitLevel",
    "UnitRace",
    "loadstring",
    "AbbreviateNumbers",
    "C_AddOns",
    "C_GameRules",
    "C_RestrictedActions",
    "C_Secrets",
    "Constants",
    "CreateFrame",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetBuildInfo",
    "GetLocale",
    "GetNormalizedRealmName",
    "GetRealmName",
    "InCombatLockdown",
    "LE_EXPANSION_CLASSIC",
    "LE_EXPANSION_LEVEL_CURRENT",
    "MinimalSliderWithSteppersMixin",
    "RegionalUniqueNamesEnabled",
    "Settings",
    "UIParent",
    "UnitGUID",
    "UnitHealth",
    "UnitHealthMax",
    "UnitName",
    "UnitNameUnmodified",
    "issecretvalue",
    "time",
    "wipe",
    "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE",
    "WOW_PROJECT_CLASSIC",
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_FOREVER",
}

-- Tests fuera del juego (busted o scripts/probar_addon.py): Lua 5.1 estándar + API de busted.
files["tests/**/*.lua"] = {
    std = "lua51+busted",
    globals = { "string" }, -- secret_mock parchea string.format
}

-- Datos generados por tools/extraer_guias.py: líneas largas a propósito.
files["GuideData.lua"] = { max_line_length = false }
files["FlightData.lua"] = { max_line_length = false }
