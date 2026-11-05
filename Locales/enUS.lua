local _, ns = ...

-- Tabla de textos: si falta una clave, devuelve la propia clave en vez de nil
-- (un texto sin traducir se ve, pero no rompe el addon).
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ns.L = L

L.ADDON_TITLE = "RutaMisiones"
L.LOADED = "loaded. Type /ruta to show the route, /ruta help for commands."
L.SLASH_HELP = "Commands: /ruta [show | refresh | ignore [questID] | unignore | config | debug | reset]"
L.ERR_COMBAT = "Not available in combat; try again when combat ends."
L.RESET_CONFIRM = "Type /ruta reset confirm to restore the defaults."
L.RESET_DONE = "Settings restored to defaults."
L.COMPARTMENT_TOOLTIP = "Click to show or hide the route. Right-click: options."
L.ERR_NO_QUESTIEDB = "QuestieDB is not loaded: install Questie (it includes QuestieDB) to get a route."

L.OPT_ENABLED = "Enable"
L.OPT_ENABLED_TT = "Shows or hides everything this addon draws."
L.OPT_SCALE = "Scale"
L.OPT_SCALE_TT = "Size of the route window."
L.OPT_WAYPOINT = "Arrow to the next step"
L.OPT_WAYPOINT_TT = "Places Blizzard's map waypoint on the next step whenever it changes."
L.OPT_STEPS = "Steps shown"
L.OPT_STEPS_TT = "How many steps of the route the window lists."
L.OPT_ABOVE = "Max levels above you"
L.OPT_ABOVE_TT = "New quests more than this many levels above you are not suggested (+3 is orange)."
L.OPT_QUESTIE = "Use Questie's availability rules"
L.OPT_QUESTIE_TT = "If Questie is loaded, also apply its blacklists and reputation/profession checks."

L.BUTTON_REFRESH = "Refresh"
L.STEP_PICKUP = "Pick up"
L.STEP_OBJECTIVE = "Do"
L.STEP_TURNIN = "Turn in"
L.OBJ_MONSTER = "kill"
L.OBJ_ITEM = "loot"
L.OBJ_OBJECT = "use"
L.OBJ_EVENT = "go"
L.OBJ_POI = "area"
L.CHAIN_MARK = "[chain]"
L.SUMMARY = "%d steps · about %s · %s XP/h"
L.OFFMAP = "%d quests in your log are outside this map."
L.EMPTY = "Nothing worth doing here: change zone or level up."
L.STATUS_IDLE = "Waiting for the first calculation…"
L.STATUS_NODB = "QuestieDB is not loaded."
L.STATUS_INDEXING = "Indexing this map's quests…"
L.STATUS_NOMAP = "No map here (instance?)."
L.TT_ARRIVE = "You get there in about %s."
L.TT_CLICK = "Left click: arrow and map here. Right click: ignore this quest."
L.IGNORED = "Ignoring «%s». /ruta unignore restores the ignored quests."
L.UNIGNORED = "Ignored quests restored."
L.NEXT = "Next: %s"
L.SKIPPED_HEADER = "Not worth it here (%d):"
L.REASON_RATE = "too slow for its XP"
L.REASON_TIME = "doesn't fit in the route"
L.REASON_CHAIN = "its previous quest is not in the route"

L.AVOID_HEADER = "Avoid (%d):"
L.AVOID_LOG = "%s: abandon it or leave it for later (%s XP/h)"
L.AVOID_NEAR = "%s: not worth the detour (%s XP/h)"
L.TT_AVOID_LOG = "It is in your log, but doing it here slows your route down. Abandon it or leave it for later."
L.TT_AVOID_NEAR = "Available nearby, but the trip costs more time than its XP is worth."
L.TT_AVOID_RATE = "This quest: about %s XP/h. Your route: %s XP/h."
L.TT_AVOID_CLICK = "Left click: arrow and map here. Right click: hide it (ignore this quest)."
L.OPT_AVOID = "Show quests to avoid"
L.OPT_AVOID_TT = "Lists under the route the quests that are not worth doing here, with the reason."

L.OPT_OPENMAP = "Open the map on click"
L.OPT_OPENMAP_TT = "Clicking a step also opens the world map with the marker (not in combat)."
L.OPT_TOMTOM = "Also use TomTom's arrow"
L.OPT_TOMTOM_TT = "If TomTom is installed, its arrow also points to the step."

L.DEBUG_HEADER = "Diagnostics (paste this when reporting a problem):"
