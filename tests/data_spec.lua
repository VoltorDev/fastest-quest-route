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

    it("una misión de objetos de botín vale lo mismo antes y después de aceptarla", function()
        local loot = Data.New(Fake.new({
            quests = {
                [200] = {
                    name = "Colmillos",
                    startedBy = { { 1 } },
                    finishedBy = { { 1 } },
                    requiredLevel = 1,
                    questLevel = 5,
                    objectives = { nil, nil, { { 500 } } },
                    objectivesText = { "Trae 6 colmillos." },
                },
            },
            npcs = {
                [1] = { name = "Gornek", zoneID = 14, spawns = { [14] = { { 42, 68 } } } },
                [10] = { name = "Jabalí", zoneID = 14, spawns = { [14] = { { 40, 60 } } } },
            },
            items = { [500] = { npcDrops = { 10 } } },
            xp = { [200] = { 5, 400 } },
        }))
        local before = Builder.Build(loot, {
            uiMap = 1411,
            position = here,
            player = Player({ level = 5 }),
            log = {},
            candidates = { 200 },
        })[1]
        local after = Builder.Build(loot, {
            uiMap = 1411,
            position = here,
            player = Player({ level = 5, inLog = { [200] = true } }),
            log = {
                [200] = {
                    title = "Colmillos",
                    complete = false,
                    objectives = { { type = "item", finished = false, numFulfilled = 0, numRequired = 6 } },
                },
            },
            candidates = {},
        })[1]
        assert.is_true(before.killXP > 0)
        assert.are.equal(before.killXP, after.killXP)
    end)

    it("deja para luego las del diario demasiado altas, salvo si ya están completas", function()
        local function Log(level, complete)
            return {
                title = "Asegurar las rutas",
                level = level,
                complete = complete,
                poi = { x = 52, y = 22 },
                objectives = { { type = "monster", finished = complete, numFulfilled = 0, numRequired = 12 } },
            }
        end
        local quests, _, tooHigh = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player({ level = 7, inLog = { [99001] = true, [99002] = true, [99003] = true } }),
            log = { [99001] = Log(11, false), [99002] = Log(9, false), [99003] = Log(11, true) },
            candidates = {},
        })
        assert.are.same({ 99001 }, tooHigh) -- nivel 11 a nivel 7: fuera de la ruta
        local ids = {}
        for _, quest in ipairs(quests) do
            ids[#ids + 1] = quest.id
        end
        table.sort(ids)
        assert.are.same({ 99002, 99003 }, ids) -- +2 se queda; la completa se entrega aunque sea alta
    end)

    it("un objetivo por encima de tu nivel cuenta como más lento", function()
        local function Work(level)
            return Builder.Build(data, {
                uiMap = 1411,
                position = here,
                player = Player({ level = level }),
                log = {},
                candidates = { 100 },
            })[1].objectives[1].work
        end
        assert.is_true(Work(1) > Work(2)) -- la misión es de nivel 2
        assert.are.equal(Work(2), Work(3)) -- por debajo no se abarata
    end)

    it("usa el nombre del cliente para las disponibles, no para las del diario", function()
        local quests = Builder.Build(data, {
            uiMap = 1411,
            position = here,
            player = Player({ inLog = { [102] = true } }),
            log = {
                [102] = {
                    title = "Lejos (diario)",
                    complete = false,
                    poi = { x = 50, y = 50 },
                    objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } },
                },
            },
            candidates = { 100, 101 },
            titleOf = function(id)
                return id == 100 and "Jabalíes del cliente" or (id == 102 and "Otro" or nil)
            end,
        })
        local byID = {}
        for _, quest in ipairs(quests) do
            byID[quest.id] = quest
        end
        assert.are.equal("Jabalíes del cliente", byID[100].name)
        assert.are.equal("Lejos (diario)", byID[102].name)
        assert.are.equal("Más jabalíes", byID[101].name) -- sin título en el cliente: el de la base
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

describe("Data: siguiente zona", function()
    local function World()
        local function Q(name, npc, level, extra)
            local q = { name = name, startedBy = { { npc } }, finishedBy = { { npc } }, requiredLevel = 1 }
            q.questLevel = level
            for k, v in pairs(extra or {}) do
                q[k] = v
            end
            return q
        end
        return Fake.new({
            quests = {
                [1] = Q("Aquí", 1, 3),
                [2] = Q("Baldíos 1", 2, 3),
                [3] = Q("Baldíos 2", 2, 4),
                [4] = Q("Baldíos alta", 2, 12),
                [5] = Q("Lejos 1", 3, 3),
                [6] = Q("Baldíos hecha", 2, 3),
                [7] = Q("Hostil", 4, 3),
            },
            npcs = {
                [1] = { name = "A", zoneID = 14, spawns = { [14] = { { 10, 10 } } } },
                [2] = { name = "B", zoneID = 17, spawns = { [17] = { { 50, 50 } } } },
                [3] = { name = "C", zoneID = 999, spawns = {} },
                [4] = { name = "D", zoneID = 17, friendlyToFaction = "A", spawns = {} },
            },
            xp = { [2] = { 3, 300 }, [3] = { 4, 400 } },
        })
    end

    it("indexa todos los mapas troceado y rellena el índice por mapa", function()
        local data = Data.New(World())
        assert.is_nil(data:IndexAllStep(2))
        local byMap = data:IndexAllStep(100)
        assert.are.same({ 1 }, byMap[1411])
        assert.are.equal(5, #byMap[1413])
        assert.is_nil(byMap[999]) -- zona sin mapa conocido
        assert.are.same({ 1 }, data:IndexStep(1411, 1)) -- ya hecho: no recorre otra vez
    end)

    it("recomienda la zona con más XP disponible, sin la actual ni lo de fuera de nivel o hecho", function()
        local data = Data.New(World())
        assert.is_nil(data:RecommendZones(Player({ level = 3 }), { exclude = 1411 }))
        data:IndexAllStep()
        local zones = data:RecommendZones(Player({ level = 3, faction = "Horde", completed = { [6] = true } }), {
            exclude = 1411,
            minCount = 1,
        })
        assert.are.equal(1, #zones)
        assert.are.equal(1413, zones[1].map)
        assert.are.equal(2, zones[1].count) -- la de nivel 12, la hecha y la de un PNJ de la Alianza no cuentan
        assert.is_true(zones[1].xp > 0)
        local other = data:RecommendZones(Player({ level = 3 }), { exclude = 1413, minCount = 1 })
        assert.are.equal(1411, other[1].map)
        assert.are.same({}, data:RecommendZones(Player({ level = 3 }), { exclude = 1413 })) -- menos de 3
    end)

    it("prefiere las zonas del mismo continente y nunca propone capitales", function()
        local function Q(npc)
            return { name = "Q", startedBy = { { npc } }, finishedBy = { { npc } }, requiredLevel = 1, questLevel = 8 }
        end
        local lib = Fake.new({
            quests = { [1] = Q(1), [2] = Q(2), [3] = Q(2), [4] = Q(2), [5] = Q(3), [6] = Q(3), [7] = Q(3) },
            npcs = {
                [1] = { name = "Durotar", zoneID = 14, spawns = {} },
                [2] = { name = "Tirisfal", zoneID = 85, spawns = {} }, -- otro continente, más XP
                [3] = { name = "Orgrimmar", zoneID = 1637, spawns = {} },
            },
        })
        lib.Support.Get("ZoneDB").private.areaIdToUiMapId =
            "return { [14] = 1411, [17] = 1413, [85] = 1420, [1637] = 1454 }"
        local data = Data.New(lib)
        data:IndexAllStep()
        local continent = { [1411] = 12, [1413] = 12, [1454] = 12, [1420] = 13 }
        local zones = data:RecommendZones(Player({ level = 8 }), {
            exclude = 1413,
            minCount = 1,
            continentOf = function(map)
                return continent[map]
            end,
            continent = 12,
        })
        assert.are.equal(2, #zones) -- Orgrimmar (capital) fuera
        assert.are.equal(1411, zones[1].map) -- mismo continente primero aunque dé menos XP
        assert.is_false(zones[1].far)
        assert.are.equal(1420, zones[2].map)
        assert.is_true(zones[2].far)

        -- Si las guías de subida hacen la zona del otro continente a este nivel, va primero.
        local guided = data:RecommendZones(Player({ level = 8 }), {
            exclude = 1413,
            minCount = 1,
            continentOf = function(map)
                return continent[map]
            end,
            continent = 12,
            guideZones = { { 1420, 7, 9 }, { 1411, 20, 25 } },
        })
        assert.are.equal(1420, guided[1].map)
        assert.is_true(guided[1].onGuide)
        assert.is_false(guided[2].onGuide) -- Durotar está en la guía, pero a otro nivel
    end)
end)
