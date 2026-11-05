-- Flujo completo en el cliente simulado: eventos → diario → plan → flecha → ventana, con una
-- QuestieDB falsa con la forma de la real y un mapa/diario de juguete.
package.path = "tests/support/?.lua;" .. package.path
local WowEnv = require("wow_env")
local Fake = require("fake_questiedb")

local TOC = "RutaMisiones.toc"

-- Cliente de misiones y mapa simulado. `world` es mutable desde el test.
local function Client(world)
    local function Vector(x, y)
        return {
            GetXY = function()
                return x, y
            end,
        }
    end
    return {
        LibQuestieDB = Fake.durotar(),
        UnitLevel = function()
            return world.level
        end,
        UnitRace = function()
            return "Orc", "Orc", 2
        end,
        UnitClass = function()
            return "Warlock", "WARLOCK", 9
        end,
        GetQuestLogRewardXP = function(id)
            return world.log[id] and world.log[id].xp or 0
        end,
        C_Map = {
            GetBestMapForUnit = function()
                return world.map
            end,
            GetPlayerMapPosition = function(_, _)
                return world.map and Vector(world.x / 100, world.y / 100) or nil
            end,
            GetMapWorldSize = function()
                return 5287.5, 3525
            end,
            CanSetUserWaypointOnMap = function()
                return true
            end,
            SetUserWaypoint = function(point)
                world.waypoint = point
            end,
        },
        C_SuperTrack = {
            SetSuperTrackedUserWaypoint = function(on)
                world.supertracked = on
            end,
        },
        UiMapPoint = {
            CreateFromCoordinates = function(map, x, y)
                return { uiMapID = map, x = x, y = y }
            end,
        },
        C_QuestLog = {
            GetAllCompletedQuestIDs = function()
                local ids = {}
                for id in pairs(world.completed) do
                    ids[#ids + 1] = id
                end
                return ids
            end,
            GetQuestsOnMap = function()
                return {}
            end,
            GetNumQuestLogEntries = function()
                return #world.order, #world.order
            end,
            GetInfo = function(index)
                local id = world.order[index]
                return id and { questID = id, title = world.log[id].title, isHeader = false, isHidden = false }
            end,
            GetQuestObjectives = function(id)
                return world.log[id].objectives
            end,
            ReadyForTurnIn = function(id)
                return world.log[id].complete
            end,
            IsComplete = function(id)
                return world.log[id].complete
            end,
        },
    }
end

-- Primer paso de la ruta que pertenece a `questID`.
local function StepFor(ns, questID)
    for _, step in ipairs(ns.Route.plan.steps) do
        if step.questID == questID then
            return step
        end
    end
end

local function NewWorld()
    return { level = 2, map = 1411, x = 42, y = 68, log = {}, order = {}, completed = {} }
end

local function Boot(world, opts)
    opts = opts or {}
    opts.globals = Client(world)
    local env, ns = WowEnv.boot(TOC, opts)
    env:Advance(1.1)
    return env, ns
end

local function Accept(env, world, id, title)
    world.log[id] = {
        title = title,
        complete = false,
        xp = 200,
        objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } },
    }
    world.order[#world.order + 1] = id
    env:Fire("QUEST_ACCEPTED", id)
    env:Advance(1.1)
end

describe("ruta en el cliente simulado", function()
    it("al entrar calcula la ruta, pone la flecha en el primer paso y lo lista", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        assert.are.same({}, env:Missing())
        assert.are.equal("ready", ns.Route.status)
        local first = ns.Route:CurrentStep()
        assert.are.equal("pickup", first.kind)
        assert.are.equal(100, first.questID)
        assert.are.equal(1411, world.waypoint.uiMapID)
        assert.is_true(math.abs(world.waypoint.x - 0.42) < 1e-6)
        assert.is_true(world.supertracked)
        -- La ventana muestra el paso con su verbo y el resumen de la ruta.
        local texts = {}
        for _, fs in ipairs(env:Widgets("FontString")) do
            texts[#texts + 1] = fs:GetText() or ""
        end
        local all = table.concat(texts, "\n")
        assert.is_truthy(all:find("Pick up: Matar jabalíes", 1, true))
        assert.is_truthy(all:find("XP/h", 1, true))
    end)

    it("al aceptar la misión avanza al objetivo y mueve la flecha", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        Accept(env, world, 100, "Matar jabalíes")
        assert.are.equal("objective", StepFor(ns, 100).kind)
        local current = ns.Route:CurrentStep()
        assert.is_true(math.abs(world.waypoint.x * 100 - current.x) < 1e-6)
    end)

    it("al completar los objetivos propone entregar y luego la continuación", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        Accept(env, world, 100, "Matar jabalíes")
        world.log[100].complete = true
        world.log[100].objectives[1].finished = true
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(1.1)
        assert.are.equal("turnin", StepFor(ns, 100).kind)
        -- Entregada: sale del diario, cuenta como completada y aparece la 101 (cadena).
        world.log[100], world.order = nil, {}
        world.completed[100] = true
        env:Fire("QUEST_TURNED_IN", 100, 200, 0)
        env:Advance(1.1)
        assert.is_nil(StepFor(ns, 100))
        assert.are.equal("pickup", StepFor(ns, 101).kind)
    end)

    it("en combate no recalcula; lo hace al salir", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        env:SetCombat(true)
        Accept(env, world, 100, "Matar jabalíes")
        assert.are.equal("pickup", StepFor(ns, 100).kind)
        env:SetCombat(false)
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(1.1)
        assert.are.equal("objective", StepFor(ns, 100).kind)
    end)

    it("ignorar una misión la saca de la ruta y lo guarda por personaje", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        env:RunSlash("/ruta ignorar")
        env:Advance(1.1)
        assert.is_true(env.RutaMisionesCharDB.ignored[100])
        for _, step in ipairs(ns.Route.plan.steps) do
            assert.are_not.equal(100, step.questID)
        end
    end)

    it("sin flecha automática no toca el marcador del jugador", function()
        local world = NewWorld()
        local env = WowEnv.new({ globals = Client(world) })
        env.RutaMisionesDB = { schema = 1, autoWaypoint = false }
        env:LoadToc(TOC)
        env:Login()
        env:Advance(1.1)
        assert.is_nil(world.waypoint)
    end)

    it("en una estancia sin mapa lo dice en vez de fallar", function()
        local world = NewWorld()
        world.map = nil
        local _, ns = Boot(world)
        assert.are.equal("nomap", ns.Route.status)
    end)
end)
