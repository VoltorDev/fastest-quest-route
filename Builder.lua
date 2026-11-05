-- Traduce el estado del jugador (diario, misiones completadas, posición) y la base de datos a la
-- lista de misiones que entiende el planificador. Lógica pura: el cliente se le pasa ya leído
-- (Route.lua lo lee del juego; los tests y el simulador, de tablas).
local _, ns = ...

local Builder = {}
ns.Builder = Builder

local MAX_WORK = 15 * 60
-- Niveles por encima del jugador que se aceptan en misiones nuevas: +3 ya es naranja en Vanilla.
Builder.MAX_ABOVE = 2

-- Tipos del diario (C_QuestLog.GetQuestObjectives) que casan con los de la base.
local LOG_KIND = { monster = "monster", item = "item", object = "object", event = "event" }

-- XP por matar un enemigo de su nivel en Vanilla: nivel × 5 + 45.
local function KillXP(level, count)
    return (level * 5 + 45) * math.max(count or 0, 0)
end

local function ObjectiveWork(kind, count)
    local work = (ns.Data.WORK[kind] or 30) * math.max(count or 1, 1)
    return math.min(work, MAX_WORK)
end

-- logQuest = { title, complete, xp?, poi = {x,y}?, objectives = {{ type, finished, numFulfilled,
-- numRequired }} } tal como lo deja Route:ReadLog().
local function BuildLogQuest(data, questID, logQuest, uiMap, ref, playerLevel)
    local quest = {
        id = questID,
        name = logQuest.title or data.lib.Quest.name(questID) or ("#" .. questID),
        inLog = true,
        objectives = {},
    }
    local known = data.lib.Quest.Exists and data.lib.Quest.Exists(questID)
    quest.xp = logQuest.xp
    if not quest.xp or quest.xp <= 0 then
        quest.xp = known and data:EstimateXP(questID, playerLevel) or data:MedianXP(playerLevel)
    end

    if logQuest.complete then
        local point = known and data:FinisherPoint(questID, uiMap, ref) or logQuest.poi
        if not point then
            return nil, "offmap"
        end
        quest.turnin = point
        return quest
    end

    -- Objetivos pendientes del diario, numerados por tipo para casarlos con la base.
    local pending, byKind = {}, {}
    for _, objective in ipairs(logQuest.objectives or {}) do
        local kind = LOG_KIND[objective.type] or "event"
        byKind[kind] = (byKind[kind] or 0) + 1
        if not objective.finished then
            local remaining = (objective.numRequired or 1) - (objective.numFulfilled or 0)
            pending[kind .. byKind[kind]] = math.max(remaining, 1)
        end
    end
    local hasLogObjectives = next(byKind) ~= nil

    local groups = known and data:ObjectiveGroups(questID, uiMap) or {}
    for _, group in ipairs(groups) do
        local key = group.kind .. group.dbIndex
        local remaining = pending[key]
        if remaining == nil and not hasLogObjectives then
            remaining = group.count
        end
        if remaining and #group.points > 0 then
            local center = ns.Data.Cluster(group.points, ref)
            quest.objectives[#quest.objectives + 1] = {
                x = center.x,
                y = center.y,
                work = ObjectiveWork(group.kind, remaining),
                label = group.kind,
            }
            if group.kind == "monster" then
                quest.killXP = (quest.killXP or 0) + KillXP(playerLevel, remaining)
            end
        end
    end
    -- Sin datos útiles en la base: el punto de interés de Blizzard (preset Enhanced).
    if #quest.objectives == 0 and logQuest.poi then
        quest.objectives[1] = { x = logQuest.poi.x, y = logQuest.poi.y, work = 120, label = "poi" }
    end
    if #quest.objectives == 0 then
        return nil, "offmap"
    end
    quest.turnin = known and data:FinisherPoint(questID, uiMap, ref) or nil
    return quest
end

local function BuildAvailableQuest(data, questID, uiMap, ref, playerLevel)
    local pickup = data:StarterPoint(questID, uiMap, ref)
    if not pickup then
        return nil
    end
    local quest = {
        id = questID,
        name = data.lib.Quest.name(questID) or ("#" .. questID),
        pickup = pickup,
        objectives = {},
    }
    quest.xp, quest.xpEstimated = data:EstimateXP(questID, playerLevel)
    for _, group in ipairs(data:ObjectiveGroups(questID, uiMap)) do
        if #group.points == 0 then
            return nil -- algún objetivo está en otro mapa: no se propone desde aquí
        end
        local center = ns.Data.Cluster(group.points, pickup)
        quest.objectives[#quest.objectives + 1] =
            { x = center.x, y = center.y, work = ObjectiveWork(group.kind, group.count), label = group.kind }
        if group.kind == "monster" then
            quest.killXP = (quest.killXP or 0) + KillXP(playerLevel, group.count)
        elseif group.kind == "item" then
            quest.killXP = (quest.killXP or 0) + KillXP(playerLevel, group.count)
        end
    end
    quest.turnin = data:FinisherPoint(questID, uiMap, quest.objectives[1] or pickup)
    return quest
end

-- state = { uiMap, position = {x,y}, player = {...}, log = { [questID] = logQuest },
--           candidates = { questIDs con dador en el mapa }, isDoable = función opcional }
-- Devuelve la lista para Planner.Plan y las misiones del diario que quedan fuera de este mapa.
function Builder.Build(data, state)
    local quests, offMap = {}, {}
    local player, ref = state.player, state.position
    for questID, logQuest in pairs(state.log or {}) do
        if not (player.ignored and player.ignored[questID]) then
            local quest = BuildLogQuest(data, questID, logQuest, state.uiMap, ref, player.level)
            if quest then
                quests[#quests + 1] = quest
            else
                offMap[#offMap + 1] = questID
            end
        end
    end
    local minLevel = player.level - 6
    local maxLevel = player.level + (state.maxAbove or Builder.MAX_ABOVE)
    for _, questID in ipairs(state.candidates or {}) do
        local level = data.lib.Quest.questLevel(questID) or player.level
        if level >= minLevel and level <= maxLevel and data:IsAvailable(questID, player) then
            if not state.isDoable or state.isDoable(questID) ~= false then
                local quest = BuildAvailableQuest(data, questID, state.uiMap, ref, player.level)
                if quest and quest.xp > 0 then
                    quests[#quests + 1] = quest
                end
            end
        end
    end
    Builder.AddFollowUps(data, state, quests)
    table.sort(offMap)
    return quests, offMap
end

-- Prerrequisitos de una misión que están entre `planned` (set de IDs).
local function PlannedPrereqs(data, questID, planned)
    local Q, after = data.lib.Quest, {}
    for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        for _, pre in ipairs(Q[field](questID) or {}) do
            if planned[pre] then
                after[#after + 1] = pre
            end
        end
    end
    local parent = Q.parentQuest(questID)
    if parent and parent ~= 0 and planned[parent] then
        after[#after + 1] = parent
    end
    return after
end

-- Continuaciones de cadena: misiones del mapa que aún no se pueden coger pero que quedarían
-- disponibles al entregar alguna de las planificadas. Se añaden con `after` (sus predecesoras),
-- para que el planificador las ordene detrás y agrupe los viajes en vez de ir y volver.
-- Admite hasta `depth` eslabones y un nivel más que el actual (se sube haciendo la ruta).
function Builder.AddFollowUps(data, state, quests, depth)
    local player = state.player
    local planned, completed = {}, {}
    for id in pairs(player.completed) do
        completed[id] = true
    end
    for _, quest in ipairs(quests) do
        planned[quest.id] = true
    end
    local hypothetical = {
        level = player.level + 1,
        raceMask = player.raceMask,
        classMask = player.classMask,
        completed = completed,
        inLog = player.inLog,
        ignored = player.ignored,
    }
    local minLevel = player.level - 6
    local maxLevel = player.level + 1 + (state.maxAbove or Builder.MAX_ABOVE)
    for _ = 1, depth or 3 do
        local added = false
        for id in pairs(planned) do
            completed[id] = true
        end
        for _, questID in ipairs(state.candidates or {}) do
            if not planned[questID] and not player.completed[questID] and not player.inLog[questID] then
                local level = data.lib.Quest.questLevel(questID) or player.level
                if level >= minLevel and level <= maxLevel and data:IsAvailable(questID, hypothetical) then
                    local after = PlannedPrereqs(data, questID, planned)
                    if #after > 0 then
                        local quest = BuildAvailableQuest(data, questID, state.uiMap, state.position, player.level)
                        if quest and quest.xp > 0 then
                            quest.after = after
                            quests[#quests + 1] = quest
                            planned[questID] = true
                            added = true
                        end
                    end
                end
            end
        end
        if not added then
            break
        end
    end
end

return Builder
