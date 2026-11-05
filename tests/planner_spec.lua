-- Planificador (Planner.lua): lógica pura de ordenación de pasos.
local function LoadPlanner()
    local ns = {}
    assert(loadfile("Planner.lua"))("RutaMisiones", ns)
    return ns.Planner
end

local Planner = LoadPlanner()
local PARAMS = { start = { x = 50, y = 50 }, w = 1000, h = 1000, speed = 7 }

local function Quest(id, xp, pickup, objective, turnin, extra)
    local quest = {
        id = id,
        name = "Q" .. id,
        xp = xp,
        pickup = pickup and { x = pickup[1], y = pickup[2] } or nil,
        objectives = objective and { { x = objective[1], y = objective[2], work = 60 } } or {},
        turnin = turnin and { x = turnin[1], y = turnin[2] } or nil,
    }
    for k, v in pairs(extra or {}) do
        quest[k] = v
    end
    return quest
end

local function Positions(plan)
    local pos = {}
    for i, step in ipairs(plan.steps) do
        pos[step.questID .. ":" .. step.kind] = i
    end
    return pos
end

local function Params(extra)
    local p = {}
    for k, v in pairs(PARAMS) do
        p[k] = v
    end
    for k, v in pairs(extra or {}) do
        p[k] = v
    end
    return p
end

describe("Planner.Plan", function()
    it("respeta recoger < objetivo < entregar en cada misión", function()
        local quests = {
            Quest(1, 500, { 50, 50 }, { 80, 50 }, { 52, 50 }),
            Quest(2, 500, { 51, 50 }, { 20, 50 }, { 50, 51 }),
            Quest(3, 500, { 50, 52 }, { 50, 80 }, { 49, 50 }),
        }
        local plan = Planner.Plan(quests, PARAMS)
        local pos = Positions(plan)
        for id = 1, 3 do
            assert.is_true(pos[id .. ":pickup"] < pos[id .. ":objective"])
            assert.is_true(pos[id .. ":objective"] < pos[id .. ":turnin"])
        end
        assert.are.equal(9, #plan.steps)
        assert.is_true(plan.xp == 1500 and plan.seconds > 0 and plan.xpPerHour > 0)
    end)

    it("recoge todo lo que hay en el campamento antes de salir", function()
        -- Dos misiones del mismo dador con objetivos en la misma dirección: recoger ambas primero.
        local quests = {
            Quest(1, 500, { 50, 50 }, { 80, 50 }, { 50, 50 }),
            Quest(2, 500, { 50, 50 }, { 82, 51 }, { 50, 50 }),
        }
        local plan = Planner.Plan(quests, PARAMS)
        assert.are.same({ "pickup", "pickup" }, { plan.steps[1].kind, plan.steps[2].kind })
        assert.are.same({ "turnin", "turnin" }, { plan.steps[5].kind, plan.steps[6].kind })
    end)

    it("no hace ir y volver entre dos campamentos lejanos", function()
        -- Campamento A (20,20) con dos misiones; campamento B (80,80) con dos. La ruta debe
        -- terminar uno antes de ir al otro: un solo cambio de campamento.
        local quests = {
            Quest(1, 600, { 20, 20 }, { 25, 22 }, { 20, 20 }),
            Quest(2, 600, { 20, 20 }, { 22, 26 }, { 20, 20 }),
            Quest(3, 600, { 80, 80 }, { 75, 78 }, { 80, 80 }),
            Quest(4, 600, { 80, 80 }, { 78, 75 }, { 80, 80 }),
        }
        local plan = Planner.Plan(quests, Params({ start = { x = 22, y = 22 } }))
        local switches, last = 0, nil
        for _, step in ipairs(plan.steps) do
            local camp = step.x < 50 and "A" or "B"
            if last and camp ~= last then
                switches = switches + 1
            end
            last = camp
        end
        assert.are.equal(1, switches)
        assert.are.equal(12, #plan.steps)
    end)

    it("descarta una misión lejana que da poca XP y explica por qué", function()
        local quests = {
            Quest(1, 800, { 50, 50 }, { 55, 50 }, { 50, 50 }),
            Quest(2, 800, { 50, 50 }, { 50, 55 }, { 50, 50 }),
            Quest(3, 50, { 5, 5 }, { 2, 2 }, { 5, 5 }),
        }
        local plan = Planner.Plan(quests, PARAMS)
        assert.is_nil(Positions(plan)["3:pickup"])
        assert.are.equal(1, #plan.skipped)
        assert.are.equal(3, plan.skipped[1].quest.id)
        assert.are.equal("rate", plan.skipped[1].reason)
    end)

    it("las del diario tienen un umbral más bajo: ya están empezadas", function()
        local far = Quest(3, 120, nil, { 10, 10 }, { 50, 50 }, { inLog = true })
        local quests = {
            Quest(1, 800, { 50, 50 }, { 55, 50 }, { 50, 50 }),
            far,
        }
        local plan = Planner.Plan(quests, Params({ keepRatio = 0 }))
        assert.is_not_nil(Positions(plan)["3:objective"])
    end)

    it("cadenas: la continuación se recoge después de entregar la anterior", function()
        local first = Quest(10, 400, { 50, 50 }, { 60, 50 }, { 50, 50 })
        local second = Quest(11, 600, { 50, 50 }, { 61, 50 }, { 50, 50 }, { after = { 10 } })
        local plan = Planner.Plan({ second, first }, PARAMS)
        local pos = Positions(plan)
        assert.is_true(pos["10:turnin"] < pos["11:pickup"])
        assert.is_true(plan.steps[pos["11:pickup"]].chained)
    end)

    it("cadenas: si la anterior no entra en la ruta, la continuación tampoco", function()
        local first = Quest(10, 400, { 50, 50 }, { 60, 50 }, nil) -- entrega fuera del mapa
        local second = Quest(11, 600, { 50, 50 }, { 61, 50 }, { 50, 50 }, { after = { 10 } })
        local plan = Planner.Plan({ first, second }, PARAMS)
        assert.is_nil(Positions(plan)["11:pickup"])
        local reasons = {}
        for _, entry in ipairs(plan.skipped) do
            reasons[entry.quest.id] = entry.reason
        end
        assert.are.equal("chain", reasons[11])
    end)

    it("una misión floja que abre una cadena buena se hace por lo que desbloquea", function()
        local opener = Quest(20, 60, { 50, 50 }, { 70, 50 }, { 50, 50 })
        local payoff = Quest(21, 3000, { 50, 50 }, { 52, 50 }, { 50, 50 }, { after = { 20 } })
        local filler = Quest(22, 900, { 50, 50 }, { 51, 50 }, { 50, 50 })
        local plan = Planner.Plan({ opener, payoff, filler }, PARAMS)
        local pos = Positions(plan)
        assert.is_not_nil(pos["20:pickup"])
        assert.is_not_nil(pos["21:turnin"])
    end)

    it("respeta el tope de duración", function()
        local quests = {}
        for i = 1, 6 do
            quests[i] = Quest(i, 500, { 50, 50 }, { 50 + i, 50 }, { 50, 50 })
            quests[i].objectives[1].work = 600
        end
        local plan = Planner.Plan(quests, Params({ maxSeconds = 25 * 60 }))
        assert.is_true(plan.seconds <= 25 * 60 + 60)
        local reasons = {}
        for _, entry in ipairs(plan.skipped) do
            reasons[entry.reason] = true
        end
        assert.is_true(reasons.time)
    end)

    it("estabilidad: con un plan anterior igual de bueno, conserva su orden", function()
        -- Dos objetivos simétricos respecto a la partida: cualquier orden cuesta lo mismo.
        local quests = {
            Quest(1, 500, nil, { 60, 50 }, nil, { inLog = true }),
            Quest(2, 500, nil, { 40, 50 }, nil, { inLog = true }),
        }
        local previous = { Planner.Key(2, "objective", 1), Planner.Key(1, "objective", 1) }
        local plan = Planner.Plan(quests, Params({ previous = previous }))
        assert.are.equal(2, plan.steps[1].questID)
        previous = { Planner.Key(1, "objective", 1), Planner.Key(2, "objective", 1) }
        plan = Planner.Plan(quests, Params({ previous = previous }))
        assert.are.equal(1, plan.steps[1].questID)
    end)

    it("el tiempo de llegada crece a lo largo de la ruta y lleva clave estable", function()
        local quests = { Quest(1, 500, { 60, 50 }, { 70, 50 }, { 60, 50 }) }
        local plan = Planner.Plan(quests, PARAMS)
        assert.is_true(plan.steps[1].arrive > 0)
        for i = 2, #plan.steps do
            assert.is_true(plan.steps[i].arrive >= plan.steps[i - 1].arrive)
        end
        assert.are.equal("1:pickup:0", plan.steps[1].key)
    end)

    it("lista de misiones a evitar: primero las del diario, luego las peores; no las que solo no caben", function()
        local plan = {
            skipped = {
                { quest = { id = 1, name = "Lejos", inLog = false }, reason = "rate", rate = 0.5 },
                { quest = { id = 2, name = "Peor", inLog = false }, reason = "rate", rate = 0.1 },
                { quest = { id = 3, name = "Diario", inLog = true }, reason = "rate", rate = 2 },
                { quest = { id = 4, name = "Luego", inLog = false }, reason = "time", rate = 9 },
                { quest = { id = 5, name = "Cadena", inLog = false }, reason = "chain", rate = 0 },
            },
        }
        local list = Planner.AvoidList(plan)
        local ids = {}
        for i, entry in ipairs(list) do
            ids[i] = entry.questID
        end
        assert.are.same({ 3, 2, 1 }, ids)
        assert.is_true(list[1].inLog)
        assert.are.equal(0.1 * 3600, list[2].xpPerHour)
        assert.are.equal(2, #Planner.AvoidList(plan, 2))
        assert.are.same({}, Planner.AvoidList(nil))
    end)

    it("de punta a punta: una del diario lejana y con poca XP sale para evitar", function()
        local quests = {
            Quest(1, 800, { 50, 50 }, { 55, 50 }, { 50, 50 }),
            Quest(2, 800, { 50, 50 }, { 50, 55 }, { 50, 50 }),
            Quest(9, 20, nil, { 2, 2 }, { 3, 3 }, { inLog = true }),
        }
        local list = Planner.AvoidList(Planner.Plan(quests, PARAMS))
        assert.are.equal(1, #list)
        assert.are.equal(9, list[1].questID)
        assert.is_true(list[1].inLog)
    end)

    it("sin misiones devuelve una ruta vacía, no un error", function()
        local plan = Planner.Plan({}, PARAMS)
        assert.are.same({}, plan.steps)
        assert.are.equal(0, plan.xpPerHour)
    end)
end)
