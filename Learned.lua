-- Misiones que QuestieDB no conoce (las nuevas de Forever sin datos): se aprenden jugando y se
-- proponen a los demás personajes de la cuenta. Se guarda, por misión, dónde se aceptó, dónde se
-- terminaron los objetivos y dónde se entregó, con la XP que dio. Solo posiciones y misiones: nada
-- de combate ni valores secretos.
--
-- Prudencia con lo que no sabemos: el nivel exigido se toma como el más bajo al que la ha aceptado
-- alguno de tus personajes, y una misión vista solo con una clase se propone solo a esa clase
-- hasta que la acepte otra (puede ser de clase).
local _, ns = ...
local module = ns:NewModule("Learned")
ns.Learned = module

module.wasIncomplete = {} -- misiones vistas sin completar en esta sesión (para fechar el «hecho»)

local function Known(questID)
    local lib = rawget(_G, "LibQuestieDB")
    if type(lib) ~= "table" or not lib.Quest or type(lib.Quest.Exists) ~= "function" then
        return true -- sin base no sabemos si es nueva: no se aprende nada
    end
    local ok, exists = pcall(lib.Quest.Exists, questID)
    return not ok or exists and true or false
end

-- Posición del jugador en su mapa, en porcentaje (0-100). nil en instancias.
function module.Here()
    local uiMap = C_Map.GetBestMapForUnit("player")
    local position = uiMap and C_Map.GetPlayerMapPosition(uiMap, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    return { map = uiMap, x = x * 100, y = y * 100 }
end

local function PlayerClassID()
    local _, _, classID = UnitClass("player")
    if issecretvalue and issecretvalue(classID) then
        return nil
    end
    return classID
end

local function Store()
    ns.db.learned = ns.db.learned or {}
    return ns.db.learned
end

-- Pura: añade lo observado al registro (los tests la llaman directamente).
function module.RecordAccept(store, questID, info)
    local entry = store[questID]
    if not entry then
        entry = { classes = {} }
        store[questID] = entry
    end
    entry.title = info.title or entry.title
    entry.faction = entry.faction or info.faction
    if info.faction and entry.faction ~= info.faction then
        entry.anyFaction = true
    end
    if info.level and (not entry.level or info.level < entry.level) then
        entry.level = info.level
    end
    if info.classID then
        entry.classes[info.classID] = true
        local count = 0
        for _ in pairs(entry.classes) do
            count = count + 1
        end
        entry.anyClass = count > 1
    end
    if info.here and not entry.pickup then
        entry.map = info.here.map
        entry.pickup = { x = info.here.x, y = info.here.y }
    end
    return entry
end

function module:OnEnable()
    ns:RegisterEvent("QUEST_ACCEPTED", function(_, _, questID)
        if not questID or Known(questID) then
            return
        end
        local logIndex = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
        local info = logIndex and C_QuestLog.GetInfo(logIndex)
        module.RecordAccept(Store(), questID, {
            title = info and info.title,
            faction = UnitFactionGroup("player"),
            level = UnitLevel("player"),
            classID = PlayerClassID(),
            here = module.Here(),
        })
        module.wasIncomplete[questID] = true
    end)
    ns:RegisterEvent("QUEST_TURNED_IN", function(_, _, questID, xpReward)
        local entry = questID and Store()[questID]
        if not entry then
            return
        end
        local here = module.Here()
        if here and not entry.turnin then
            entry.turnin = here
        end
        if type(xpReward) == "number" and xpReward > 0 and not issecretvalue(xpReward) then
            entry.xp, entry.xpLevel = xpReward, UnitLevel("player")
        end
    end)
end

-- Llamado por Route con el diario ya leído: la primera vez que una misión aprendida pasa de
-- incompleta a completa en esta sesión, allí estaban sus objetivos.
function module:Observe(log, here)
    local store = ns.db.learned
    if not store then
        return
    end
    for questID, logQuest in pairs(log) do
        local entry = store[questID]
        if entry then
            if not logQuest.complete then
                self.wasIncomplete[questID] = true
            elseif self.wasIncomplete[questID] and not entry.done and here then
                entry.done = { map = here.map, x = here.x, y = here.y }
                self.wasIncomplete[questID] = nil
            end
        end
    end
end

function module:Count()
    local count = 0
    for _ in pairs(ns.db.learned or {}) do
        count = count + 1
    end
    return count
end
