-- Tiempo de viaje (Travel.lua) y su uso al recomendar la siguiente zona (Data:RecommendZones).
package.path = "tests/support/?.lua;" .. package.path
local Fake = require("fake_questiedb")

local function Load(files)
    local ns = {}
    for _, file in ipairs(files) do
        assert(loadfile(file))("RutaMisiones", ns)
    end
    return ns
end

local ns = Load({ "Planner.lua", "Data.lua", "Builder.lua", "FlightData.lua", "Travel.lua" })
local Travel, Data = ns.Travel, ns.Data

local function P(c, x, y)
    return { c = c, x = x, y = y }
end

describe("Travel", function()
    local times = { [1] = { [2] = 100 } } -- solo consta un sentido: se usa en los dos

    it("va a pie si no conoces maestros de vuelo", function()
        local seconds, flew = Travel.Seconds(P(0, 0, 0), P(0, 700, 0), { speed = 7 })
        assert.are.equal(100, seconds)
        assert.is_false(flew)
    end)

    it("vuela si es más rápido: andar al nodo, volar y andar desde el de llegada", function()
        local nodes = { [1] = P(0, 70, 0), [2] = P(0, 7000, 0) }
        local seconds, flew = Travel.Seconds(P(0, 0, 0), P(0, 7070, 0), { speed = 7, nodes = nodes, times = times })
        assert.are.equal(10 + 100 + 10, seconds)
        assert.is_true(flew)
        -- El tramo se usa en el sentido que no consta.
        local back = Travel.Seconds(P(0, 7070, 0), P(0, 0, 0), { speed = 7, nodes = nodes, times = times })
        assert.are.equal(120, back)
    end)

    it("no vuela a un nodo que no conoces", function()
        local nodes = { [1] = P(0, 70, 0) } -- el 2 está sin descubrir
        local seconds, flew = Travel.Seconds(P(0, 0, 0), P(0, 7070, 0), { speed = 7, nodes = nodes, times = times })
        assert.are.equal(1010, seconds)
        assert.is_false(flew)
    end)

    it("encadena vuelos y cruza el mar en barco; sin forma de llegar devuelve nil", function()
        local nodes = { [1] = P(0, 0, 0), [2] = P(0, 7000, 0), [3] = P(1, 0, 0) }
        local opts = { speed = 7, nodes = nodes, times = times, transports = { { 2, 3 } } }
        local seconds, flew = Travel.Seconds(P(0, 0, 0), P(1, 700, 0), opts)
        assert.are.equal(100 + Travel.TRANSPORT_SECONDS + 100, seconds)
        assert.is_true(flew)
        assert.is_nil((Travel.Seconds(P(0, 0, 0), P(1, 700, 0), { speed = 7 })))
    end)

    it("los datos de vuelo cargan y los transportes unen nodos que existen", function()
        for _, key in ipairs({ "A", "H" }) do
            local fts = ns.FlightTimes[key]
            assert.is_truthy(next(fts))
            for _, pair in ipairs(Travel.TRANSPORTS[key]) do
                assert.is_truthy(fts[pair[1]])
                assert.is_truthy(fts[pair[2]])
            end
        end
        assert.are.equal(113, ns.FlightTimes.A[2][5]) -- Ventormenta - Villa del Lago
    end)
end)

describe("RecommendZones con viaje", function()
    local function Q(npc)
        return { name = "Q", startedBy = { { npc } }, finishedBy = { { npc } }, requiredLevel = 1, questLevel = 8 }
    end

    local function Setup()
        local lib = Fake.new({
            quests = { [1] = Q(1), [2] = Q(1), [3] = Q(2), [4] = Q(2), [5] = Q(2) },
            npcs = {
                [1] = { name = "Cerca", zoneID = 14, spawns = { [14] = { { 50, 50 } } } },
                [2] = { name = "Lejos", zoneID = 85, spawns = { [85] = { { 50, 50 } } } }, -- más XP
            },
        })
        lib.Support.Get("ZoneDB").private.areaIdToUiMapId = "return { [14] = 1411, [17] = 1413, [85] = 1420 }"
        local data = Data.New(lib)
        data:IndexAllStep()
        return data
    end

    local player = { level = 8, raceMask = 2, classMask = 256, completed = {}, inLog = {}, ignored = {} }
    local continent = { [1411] = 12, [1413] = 12, [1420] = 13 }
    local function Opts(travel)
        return {
            exclude = 1413,
            minCount = 1,
            continentOf = function(map)
                return continent[map]
            end,
            continent = 12,
            travel = travel,
        }
    end

    it("sin datos de viaje, el orden de siempre", function()
        local zones = Setup():RecommendZones(player, Opts(nil))
        assert.are.equal(1411, zones[1].map)
        assert.is_true(zones[2].far)
        assert.is_nil(zones[1].travel)
        assert.are.equal(zones[1].xp, zones[1].net)
    end)

    it("una zona de otro continente a la que sabes llegar compite por XP neta del viaje", function()
        local asked = {}
        local function Travel_(seconds)
            return function(map, x, y)
                asked[map] = { x, y }
                return seconds[map], seconds[map] and seconds[map] > 60
            end
        end
        local data = Setup()
        -- Viaje corto a las dos: gana la de más XP aunque esté en otro continente.
        local zones = data:RecommendZones(player, Opts(Travel_({ [1411] = 30, [1420] = 60 })))
        assert.are.equal(1420, zones[1].map)
        assert.is_false(zones[1].far)
        assert.are.equal(60, zones[1].travel)
        assert.are.same({ 50, 50 }, asked[1420]) -- se viaja al campamento de dadores
        assert.is_true(zones[1].net < zones[1].xp)
        -- Viaje muy largo a la lejana: lo que dejas de ganar viajando la pone detrás.
        zones = data:RecommendZones(player, Opts(Travel_({ [1411] = 30, [1420] = 3600 })))
        assert.are.equal(1411, zones[1].map)
        -- Sin forma conocida de llegar, sigue detrás como antes.
        zones = data:RecommendZones(player, Opts(Travel_({ [1411] = 30 })))
        assert.are.equal(1411, zones[1].map)
        assert.is_true(zones[2].far)
    end)
end)
