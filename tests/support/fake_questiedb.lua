-- QuestieDB falsa con la misma forma que la API pública de LibQuestieDB (contrato 4): getters por
-- campo (Quest.name(id), Npc.spawns(id)…), Support.Get y Enum. Solo lo que usan Data y Builder.
local M = {}

local function Entity(rows)
    local entity = {}
    setmetatable(entity, {
        __index = function(_, field)
            return function(id)
                local row = rows[id]
                return row and row[field]
            end
        end,
    })
    entity.Exists = function(id)
        return rows[id] ~= nil
    end
    entity.GetAllIds = function()
        local ids = {}
        for id in pairs(rows) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        return ids
    end
    return entity
end

-- data = { quests = {...}, npcs = {...}, objects = {...}, items = {...}, xp = {...} }
function M.new(data)
    local zone = {
        private = {
            areaIdToUiMapId = "return { [14] = 1411, [17] = 1413, [362] = 1411 }",
            areaIdToUiMapIdOverride = "return { [0] = 0 }",
        },
    }
    local xp = { db = data.xp or {} }
    return {
        contractVersion = 4,
        Quest = Entity(data.quests or {}),
        Npc = Entity(data.npcs or {}),
        Object = Entity(data.objects or {}),
        Item = Entity(data.items or {}),
        Support = {
            Get = function(name)
                if name == "ZoneDB" then
                    return zone
                elseif name == "QuestXP" then
                    return xp
                end
            end,
        },
        Enum = { raceMaskById = { [2] = 2, [95] = 4294967296, [96] = 8589934592 } },
        RequireContract = function(required)
            if required >= 1 and required <= 4 then
                return true
            end
            return false, "QuestieDB contract mismatch"
        end,
    }
end

-- Durotar de juguete: Gornek (1) da A (100) y su continuación B (101); Kaltunk (2) da C (102),
-- cuyo objetivo está en otro mapa (17). Jabalíes (10) en dos grupos, el grande al norte.
function M.durotar()
    return M.new({
        quests = {
            [100] = {
                name = "Matar jabalíes",
                startedBy = { { 1 } },
                finishedBy = { { 1 } },
                requiredLevel = 1,
                questLevel = 2,
                objectives = { { { 10 } } },
                objectivesText = { "Mata 6 jabalíes." },
            },
            [101] = {
                name = "Más jabalíes",
                startedBy = { { 1 } },
                finishedBy = { { 1 } },
                requiredLevel = 1,
                questLevel = 3,
                preQuestSingle = { 100 },
                objectives = { { { 10 } } },
            },
            [102] = {
                name = "Lejos",
                startedBy = { { 2 } },
                finishedBy = { { 2 } },
                requiredLevel = 1,
                questLevel = 2,
                objectives = { { { 11 } } },
            },
            [103] = {
                name = "Solo Alianza",
                startedBy = { { 1 } },
                finishedBy = { { 1 } },
                requiredLevel = 1,
                questLevel = 2,
                requiredRaces = 1,
                objectives = {},
            },
            [104] = {
                name = "Skyborne Horda",
                startedBy = { { 1 } },
                finishedBy = { { 1 } },
                requiredLevel = 1,
                questLevel = 2,
                requiredRaces = 8589934592 + 2,
                objectives = {},
            },
        },
        npcs = {
            [1] = { name = "Gornek", zoneID = 362, spawns = { [362] = { { 42, 68 } } } },
            [2] = { name = "Kaltunk", zoneID = 14, spawns = { [14] = { { 43, 69 } } } },
            [10] = {
                name = "Jabalí",
                zoneID = 14,
                spawns = { [14] = { { 40, 60 }, { 41, 61 }, { 40.5, 60.5 }, { 60, 80 } } },
            },
            [11] = { name = "Lejano", zoneID = 17, spawns = { [17] = { { 50, 50 } } } },
        },
        xp = { [100] = { 2, 200 }, [101] = { 3, 300 } },
    })
end

return M
