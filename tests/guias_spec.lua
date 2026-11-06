-- Respaldo con los datos de guías (GuideData.lua): solo donde QuestieDB no ubica la misión.
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
local data = Data.New(Fake.durotar())
local here = { x = 42, y = 68 }

local function Player(extra)
    local player = {
        level = 5,
        raceMask = 2,
        classMask = 256,
        classID = 9,
        raceToken = "Orc",
        faction = "Horde",
        completed = {},
        inLog = {},
        ignored = {},
    }
    for k, v in pairs(extra or {}) do
        player[k] = v
    end
    return player
end

local GUIDE = {
    [90001] = {
        t = "Nueva",
        f = "H",
        lo = 1,
        hi = 10,
        p = { 1411, 50, 50 },
        o = { { 1411, 60, 40 } },
        e = { 1411, 50, 51 },
    },
    [90002] = { t = "Lejos", f = "H", lo = 1, hi = 10, p = { 1411, 50, 50 }, o = { { 1412, 10, 10 } } },
    [90003] = { t = "Alianza", f = "A", lo = 1, hi = 10, p = { 1411, 30, 30 } },
    [90004] = { t = "De guerrero", f = "H", lo = 1, hi = 10, c = { 1 }, p = { 1411, 30, 30 } },
    [90005] = { t = "De trol", f = "H", lo = 1, hi = 10, r = { "Troll" }, p = { 1411, 30, 30 } },
    [90006] = { t = "Alta", f = "H", lo = 12, hi = 15, p = { 1411, 30, 30 } },
    [90007] = { t = "Cadena", f = "H", lo = 1, hi = 10, p = { 1411, 50, 51 }, a = { 90001 } },
    [90008] = { t = "Tras la de guerrero", f = "H", lo = 1, hi = 10, p = { 1411, 30, 31 }, a = { 90004 } },
    [100] = { t = "Ya en la base", f = "H", lo = 1, hi = 10, p = { 1411, 1, 1 } },
    [104] = { t = "Sin objetivos", f = "H", lo = 1, hi = 10, p = { 1411, 42, 68 }, o = { { 1411, 70, 20 } } },
}

local function Build(extra)
    local state = {
        uiMap = 1411,
        position = here,
        player = Player(extra and extra.player),
        log = extra and extra.log or {},
        candidates = extra and extra.candidates or {},
        guide = GUIDE,
        learned = extra and extra.learned,
    }
    local quests = Builder.Build(data, state)
    local byID = {}
    for _, quest in ipairs(quests) do
        byID[quest.id] = quest
    end
    return byID, quests
end

describe("Datos de guías como respaldo", function()
    it("propone la misión que QuestieDB no conoce, con recogida, objetivo y entrega", function()
        local byID = Build()
        local quest = byID[90001]
        assert.is_not_nil(quest)
        assert.is_true(quest.guide)
        assert.is_true(quest.xpEstimated)
        assert.are.same({ x = 50, y = 50 }, quest.pickup)
        assert.are.equal(60, quest.objectives[1].x)
        assert.are.equal("guide", quest.objectives[1].label)
        assert.are.same({ x = 50, y = 51 }, quest.turnin)
        assert.is_true(quest.xp > 0)
        assert.is_nil(byID[90002]) -- objetivo en otro mapa
    end)

    it("si QuestieDB ubica la misión, manda la base", function()
        local byID = Build()
        assert.is_nil(byID[100] and byID[100].guide)
    end)

    it("si la base ubica la misión pero no sus objetivos, pone los de la guía", function()
        local byID = Build({ candidates = { 104 } })
        assert.is_nil(byID[104].guide) -- la propone la base, no la guía
        assert.are.equal(70, byID[104].objectives[1].x)
        assert.are.equal("guide", byID[104].objectives[1].label)
    end)

    it("filtra facción, clase, raza y nivel", function()
        local byID = Build()
        assert.is_nil(byID[90003])
        assert.is_nil(byID[90004])
        assert.is_nil(byID[90005])
        assert.is_nil(byID[90006])
        assert.is_not_nil(Build({ player = { classID = 1 } })[90004])
        assert.is_not_nil(Build({ player = { raceToken = "Troll" } })[90005])
        assert.is_not_nil(Build({ player = { level = 12 } })[90006])
        assert.is_nil(Build({ player = { level = 17 } })[90001]) -- gris hace tiempo
    end)

    it("previas: detrás si está en la ruta; fuera si falta; se ignora si es de otra clase", function()
        local byID = Build()
        assert.are.same({ 90001 }, byID[90007].after)
        assert.is_not_nil(byID[90008]) -- la previa es de guerrero: no le toca a un brujo
        local done = Build({ player = { completed = { [90001] = true } } })
        assert.is_not_nil(done[90007])
        assert.is_nil(done[90007].after)
        local ignored = Build({ player = { ignored = { [90001] = true } } })
        assert.is_nil(ignored[90007])
        -- Un guerrero tiene la previa en la ruta: va detrás de ella.
        assert.are.same({ 90004 }, Build({ player = { classID = 1 } })[90008].after)
    end)

    it("lo aprendido jugando tiene prioridad sobre la guía", function()
        local byID = Build({
            learned = { [90001] = { title = "Aprendida", map = 1411, pickup = { x = 10, y = 10 }, classes = {} } },
        })
        assert.is_true(byID[90001].learned)
        assert.is_nil(byID[90001].guide)
    end)

    it("misiones del diario sin datos: objetivos y entrega de la guía", function()
        local byID = Build({
            player = { inLog = { [90001] = true } },
            log = {
                [90001] = {
                    title = "Nueva",
                    complete = false,
                    objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 4 } },
                },
            },
        })
        assert.are.equal(60, byID[90001].objectives[1].x)
        assert.are.same({ x = 50, y = 51 }, byID[90001].turnin)
        local complete = Build({
            player = { inLog = { [90001] = true } },
            log = { [90001] = { title = "Nueva", complete = true, objectives = {} } },
        })
        assert.are.same({ x = 50, y = 51 }, complete[90001].turnin)
    end)

    it("el fichero real carga y sus entradas tienen buena forma", function()
        local real = {}
        assert(loadfile("GuideData.lua"))("RutaMisiones", real)
        local count = 0
        for id, entry in pairs(real.GuideData) do
            count = count + 1
            assert.is_true(type(id) == "number" and type(entry.t) == "string")
            for _, key in ipairs({ "p", "e" }) do
                if entry[key] then
                    assert.are.equal(3, #entry[key])
                end
            end
        end
        assert.is_true(count > 300)
        local book = real.GuideData[91741] -- «Nibbled-On Book», Northshire
        assert.are.equal(1429, book.p[1])
    end)
end)
