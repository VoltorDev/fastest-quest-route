-- Reproducción: entregas completas al lado del jugador frente a un objetivo lejano.
-- Mismo estilo que tests/planner_spec.lua. Las misiones completas llegan del Builder solo con
-- nodo de entrega (Builder.lua: BuildLogQuest, rama logQuest.complete).
local function LoadPlanner()
    local ns = {}
    assert(loadfile("Planner.lua"))("RutaMisiones", ns)
    return ns.Planner
end

local Planner = LoadPlanner()
local PARAMS = { start = { x = 50, y = 50 }, w = 1000, h = 1000, speed = 7 }

local function Complete(id, xp, turnin)
    return {
        id = id,
        name = "C" .. id,
        xp = xp,
        inLog = true,
        objectives = {},
        turnin = { x = turnin[1], y = turnin[2] },
    }
end

-- Cuatro misiones completas con el PNJ de entrega a 10-30 yardas; una misión del diario cuyo
-- objetivo está a unas 200 yardas y que se entrega en el mismo campamento (52,50).
local function Scenario(objective)
    return {
        Complete(1, 800, { 52, 50 }),
        Complete(2, 800, { 51, 52 }),
        Complete(3, 800, { 53, 51 }),
        Complete(4, 800, { 52, 48 }),
        {
            id = 9,
            name = "Q9",
            xp = 2000,
            inLog = true,
            objectives = { { x = objective[1], y = objective[2], work = 60 } },
            turnin = { x = 52, y = 50 },
        },
    }
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

local function Positions(plan)
    local pos = {}
    for i, step in ipairs(plan.steps) do
        pos[step.questID .. ":" .. step.kind] = i
    end
    return pos
end

local function Order(plan)
    local list = {}
    for _, step in ipairs(plan.steps) do
        list[#list + 1] = step.questID .. ":" .. step.kind
    end
    return table.concat(list, " ")
end

local function AssertTurninsFirst(plan)
    local pos = Positions(plan)
    assert(pos["9:objective"], "la misión 9 no entra en la ruta: " .. Order(plan))
    for id = 1, 4 do
        assert(pos[id .. ":turnin"], "falta la entrega " .. id .. ": " .. Order(plan))
        assert(
            pos[id .. ":turnin"] < pos["9:objective"],
            "la entrega " .. id .. " va después del objetivo lejano: " .. Order(plan)
        )
    end
end

describe("Planner.Plan: entregas al lado", function()
    it("entrega las completas cercanas antes de ir al objetivo lejano (de camino)", function()
        AssertTurninsFirst(Planner.Plan(Scenario({ 70, 50 }), PARAMS))
    end)

    it("entrega las completas cercanas antes de ir al objetivo lejano (en sentido contrario)", function()
        AssertTurninsFirst(Planner.Plan(Scenario({ 30, 50 }), PARAMS))
    end)

    it("aunque el plan anterior aplazara las entregas, las adelanta", function()
        local previous = { "9:objective:1", "1:turnin:0", "2:turnin:0", "3:turnin:0", "4:turnin:0", "9:turnin:0" }
        AssertTurninsFirst(Planner.Plan(Scenario({ 70, 50 }), Params({ previous = previous })))
    end)
end)
