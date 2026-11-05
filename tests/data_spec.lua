-- Capa de datos (Data.lua) y constructor (Builder.lua) contra una QuestieDB falsa con la forma de
-- la API pública real. La prueba con la base real está en tools/simular_ruta.py.
package.path = "tests/support/?.lua;" .. package.path
local Fake = require("fake_questiedb")

local function Load()
    local ns = {}
    for _, file in ipairs({ "Planner.lua", "Data.lua", "Builder.lua" }) do
        assert(loadfile(file))("RutaMisiones", ns)
    end
    return ns
end

local ns = Load()
local Data, Builder = ns.Data, ns.Builder

local function Player(extra)
    local player = { level = 2, raceMask = 2, classMask = 256, completed = {}, inLog = {}, ignored = {} }
    for k, v in pairs(extra or {}) do
        player[k] = v
    end
    return player
end

describe("Data", function()
    it("comprueba el contrato de la librería", function()
        assert.is_true(Data.CheckLibrary(Fake.durotar()))
        local ok, why = Data.CheckLibrary(nil)
        assert.is_false(ok)
        assert.are.equal("missing", why)
        local old = Fake.durotar()
        old.RequireContract = function()
            return false, "QuestieDB contract mismatch"
        end
        assert.is_false((Data.CheckLibrary(old)))
    end)

    it("HasBit funciona con máscaras de más de 32 bits (Skyborne)", function()
        assert.is_true(Data.HasBit(8589934592 + 2, 2))
        assert.is_true(Data.HasBit(8589934592 + 2, 8589934592))
        assert.is_false(Data.HasBit(8589934592 + 2, 4294967296))
    end)

    it("traduce AreaID a UiMapID con las tablas en texto de la QuestieDB", function()
        local data = Data.New(Fake.durotar())
        assert.are.equal(1411, data.areaToMap[14])
        assert.is_true(data.mapAreas[1411][362])
        local points = data:PointsOnMap({ [14] = { { 1, 2 } }, [17] = { { 3, 4 } }, [362] = { { -1, -1 } } }, 1411)
        assert.are.same({ { x = 1, y = 2 } }, points)
    end)

    it("el grupo de un objetivo es la zona con más spawns, no la media de todos", function()
        local center =
            Data.Cluster({ { x = 40, y = 60 }, { x = 41, y = 61 }, { x = 40.5, y = 60.5 }, { x = 90, y = 10 } })
        assert.is_true(math.abs(center.x - 40.5) < 0.01 and math.abs(center.y - 60.5) < 0.01)
        assert.are.equal(3, center.n)
        assert.is_nil(Data.Cluster({}))
    end)

    it("ajusta la XP al nivel como en Vanilla", function()
        assert.are.equal(400, Data.AdjustXP(400, 10, 10))
        assert.are.equal(400, Data.AdjustXP(400, 10, 5)) -- tope 100 %
        assert.are.equal(400, Data.AdjustXP(400, 10, 15)) -- hasta 5 niveles por debajo, entera
        assert.are.equal(320, Data.AdjustXP(400, 10, 16)) -- 2·(−6)+20 = 8 → 80 %
        assert.are.equal(40, Data.AdjustXP(400, 10, 30))
    end)

    it("estima la XP de las misiones sin dato con la mediana de su nivel", function()
        local data = Data.New(Fake.new({
            quests = { [1] = { questLevel = 5 } },
            xp = { [7] = { 5, 300 }, [8] = { 5, 500 }, [9] = { 5, 400 } },
        }))
        local xp, estimated = data:EstimateXP(1, 5)
        assert.are.equal(400, xp)
        assert.is_true(estimated)
    end)

    it("disponibilidad: nivel, raza (también Skyborne), previas y exclusivas", function()
        local data = Data.New(Fake.durotar())
        assert.is_true(data:IsAvailable(100, Player()))
        assert.is_false(data:IsAvailable(101, Player())) -- falta la previa
        assert.is_true(data:IsAvailable(101, Player({ completed = { [100] = true } })))
        assert.is_false(data:IsAvailable(100, Player({ completed = { [100] = true } })))
        assert.is_false(data:IsAvailable(100, Player({ inLog = { [100] = true } })))
        assert.is_false(data:IsAvailable(100, Player({ ignored = { [100] = true } })))
        assert.is_false(data:IsAvailable(103, Player())) -- solo humanos
        assert.is_true(data:IsAvailable(104, Player())) -- máscara > 2^32 que incluye orco
        assert.is_true(data:IsAvailable(104, Player({ raceMask = 8589934592 })))
    end)

    it("indexa por trozos las misiones cuyo dador está en el mapa", function()
        local data = Data.New(Fake.durotar())
        assert.is_nil(data:IndexStep(1411, 2))
        local list = data:IndexStep(1411, 2) or data:IndexStep(1411, 2)
        assert.is_not_nil(list)
        table.sort(list)
        assert.are.same({ 100, 101, 102, 103, 104 }, list)
        assert.are.same({}, Data.New(Fake.durotar()):IndexStep(1413))
    end)
end)

describe("Builder", function()
    local data = Data.New(Fake.durotar())
    local here = { x = 42, y = 68 }

    it("propone las disponibles con su recogida, objetivo agrupado y entrega", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player(),
            log = {},
            candidates = { 100, 101, 102, 103, 104 },
        })
        local byID = {}
        for _, quest in ipairs(quests) do
            byID[quest.id] = quest
        end
        local boars = byID[100]
        assert.is_not_nil(boars)
        assert.are.same({ x = 42, y = 68, n = 1 }, boars.pickup)
        assert.is_true(math.abs(boars.objectives[1].x - 40.5) < 0.01)
        assert.are.equal(6 * Data.WORK.monster, boars.objectives[1].work) -- «Mata 6» del texto
        assert.is_true(boars.killXP > 0)
        assert.is_nil(byID[102]) -- su objetivo está en otro mapa
        assert.is_nil(byID[103]) -- raza
        -- La continuación entra como cadena, detrás de la 100.
        assert.are.same({ 100 }, byID[101].after)
    end)

    it("del diario: completa → solo entregar; a medias → solo lo que falta", function()
        local quests, offMap = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player({ inLog = { [100] = true, [102] = true } }),
            log = {
                [100] = { title = "Matar jabalíes", complete = true, objectives = {} },
                [102] = {
                    title = "Lejos",
                    complete = false,
                    objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } },
                },
            },
            candidates = {},
        })
        assert.are.equal(1, #quests)
        assert.are.equal(100, quests[1].id)
        assert.are.equal(0, #quests[1].objectives)
        assert.is_not_nil(quests[1].turnin)
        assert.are.same({ 102 }, offMap)
    end)

    it("usa el punto de interés de Blizzard si la base no conoce la misión (misiones nuevas)", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player({ inLog = { [99999] = true } }),
            log = {
                [99999] = {
                    title = "Nueva de Forever",
                    complete = false,
                    xp = 750,
                    poi = { x = 55, y = 44 },
                    objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } },
                },
            },
            candidates = {},
        })
        assert.are.equal(1, #quests)
        assert.are.equal(750, quests[1].xp)
        assert.are.equal(55, quests[1].objectives[1].x)
    end)

    it("no propone misiones de más niveles por encima de lo permitido", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player({ level = 1 }),
            log = {},
            candidates = { 100 },
            maxAbove = 0,
        })
        assert.are.equal(0, #quests)
    end)

    it("respeta el IsDoable de Questie cuando se le pasa", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player(),
            log = {},
            candidates = { 100 },
            isDoable = function()
                return false
            end,
        })
        assert.are.equal(0, #quests)
    end)

    it("de punta a punta: la ruta hace la cadena 100 → 101 en orden", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player(),
            log = {},
            candidates = { 100, 101 },
        })
        local plan = ns.Planner.Plan(quests, { start = here, w = 5000, h = 3400 })
        local order = {}
        for _, step in ipairs(plan.steps) do
            order[#order + 1] = step.questID .. ":" .. step.kind
        end
        local function Index(key)
            for i, value in ipairs(order) do
                if value == key then
                    return i
                end
            end
        end
        assert.is_true(Index("100:turnin") < Index("101:pickup"))
    end)
end)
