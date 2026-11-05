-- Planificador de ruta: lógica pura, sin API del juego (se prueba fuera del cliente).
--
-- Entrada: posición de partida, tamaño del mapa en yardas, velocidad y una lista de misiones con
-- sus puntos (recoger, objetivos, entregar) en porcentaje del mapa (0-100). Salida: la secuencia
-- de pasos que más XP da por unidad de tiempo, con el tiempo estimado y las misiones descartadas.
--
-- Método (heurística, no óptimo exacto):
--   1. Ordena las misiones por eficiencia aislada (XP / tiempo de hacerla sola desde la partida).
--   2. Inserta cada misión con «inserción más barata» respetando recoger < objetivos < entregar.
--      La acepta si su XP por segundo marginal compensa frente al ritmo actual de la ruta.
--   3. Mejora local: recoloca cada paso en su mejor hueco válido hasta que no mejore.
local _, ns = ...

local Planner = {}
ns.Planner = Planner

local sqrt, huge = math.sqrt, math.huge

Planner.DEFAULTS = {
    speed = 7, -- yardas por segundo a pie (velocidad de carrera base)
    pickupWork = 8, -- segundos por hablar con un PNJ
    turninWork = 10,
    minRatio = 0.4, -- una misión nueva debe dar al menos este % del ritmo de XP de la ruta
    keepRatio = 0.2, -- umbral (más bajo) para las del diario: ya están empezadas
    offMapFactor = 0.5, -- XP que se cuenta si la entrega está fuera de este mapa
    maxSeconds = 90 * 60, -- tope de duración de la ruta: lo que no quepa se deja para después
    passes = 25, -- pasadas máximas de mejora local
    chainBonus = 0.5, -- parte del valor de las continuaciones que se suma a la misión que las abre
}

local KIND_ORDER = { pickup = 1, objective = 2, turnin = 3 }

local function Distance(a, b, w, h)
    local dx = (a.x - b.x) * w / 100
    local dy = (a.y - b.y) * h / 100
    return sqrt(dx * dx + dy * dy)
end
Planner.Distance = Distance

-- Coste total (segundos) de una ruta: desplazamientos + trabajo en cada paso.
local function RouteCost(route, start, p)
    local total, prev = 0, start
    for i = 1, #route do
        local node = route[i]
        total = total + Distance(prev, node, p.w, p.h) / p.speed + node.work
        prev = node
    end
    return total
end
Planner.RouteCost = RouteCost

-- Coste de meter `node` entre route[i-1] (o la partida) y route[i] (o nada).
local function InsertDelta(route, i, node, start, p)
    local prev = route[i - 1] or start
    local nextNode = route[i]
    local add = Distance(prev, node, p.w, p.h) / p.speed + node.work
    if nextNode then
        add = add + Distance(node, nextNode, p.w, p.h) / p.speed - Distance(prev, nextNode, p.w, p.h) / p.speed
    end
    return add
end

local function BestInsert(route, node, first, last, start, p)
    local bestI, bestDelta = nil, huge
    for i = first, last do
        local delta = InsertDelta(route, i, node, start, p)
        if delta < bestDelta then
            bestI, bestDelta = i, delta
        end
    end
    return bestI, bestDelta
end

-- Posiciones permitidas para un nodo: recoger < objetivos < entregar dentro de la misión, y en las
-- cadenas, todo lo de la continuación después de entregar la anterior (quest.afterSet).
local function ValidRange(route, node)
    local first, last = 1, #route + 1
    local order = KIND_ORDER[node.kind]
    local quest = node.q
    for i = 1, #route do
        local other = route[i]
        if other ~= node then
            if other.q == quest then
                local otherOrder = KIND_ORDER[other.kind]
                if otherOrder < order and i + 1 > first then
                    first = i + 1
                elseif otherOrder > order and i < last then
                    last = i
                end
            elseif other.kind == "turnin" and quest.afterSet and quest.afterSet[other.q] then
                if i + 1 > first then
                    first = i + 1
                end
            elseif node.kind == "turnin" and other.q.afterSet and other.q.afterSet[quest] then
                if i < last then
                    last = i
                end
            end
        end
    end
    return first, last
end

local function BuildNodes(quest, p)
    local nodes = {}
    if quest.pickup then
        nodes[#nodes + 1] = { q = quest, kind = "pickup", x = quest.pickup.x, y = quest.pickup.y, work = p.pickupWork }
    end
    for index, objective in ipairs(quest.objectives or {}) do
        nodes[#nodes + 1] = {
            q = quest,
            kind = "objective",
            index = index,
            x = objective.x,
            y = objective.y,
            work = objective.work or 60,
            label = objective.label,
        }
    end
    if quest.turnin then
        nodes[#nodes + 1] = { q = quest, kind = "turnin", x = quest.turnin.x, y = quest.turnin.y, work = p.turninWork }
    end
    return nodes
end

local function QuestValue(quest, p)
    local xp = quest.xp or 0
    if not quest.turnin then
        xp = xp * p.offMapFactor
    end
    return xp + (quest.killXP or 0)
end

-- Inserta los nodos de una misión en orden; devuelve la ruta nueva y el tiempo añadido.
local function InsertQuest(route, nodes, start, p)
    local candidate = {}
    for i = 1, #route do
        candidate[i] = route[i]
    end
    local before = RouteCost(candidate, start, p)
    for _, node in ipairs(nodes) do
        local first, last = ValidRange(candidate, node)
        if first > last then
            return nil
        end
        local i = BestInsert(candidate, node, first, last, start, p)
        table.insert(candidate, i, node)
    end
    return candidate, RouteCost(candidate, start, p) - before
end

-- Saca todos los nodos de una misión y la vuelve a insertar entera en su mejor sitio.
local function MoveQuest(route, quest, start, p)
    local without, nodes = {}, {}
    for _, node in ipairs(route) do
        if node.q == quest then
            nodes[#nodes + 1] = node
        else
            without[#without + 1] = node
        end
    end
    table.sort(nodes, function(a, b)
        local ka, kb = KIND_ORDER[a.kind], KIND_ORDER[b.kind]
        if ka ~= kb then
            return ka < kb
        end
        return (a.index or 0) < (b.index or 0)
    end)
    return InsertQuest(without, nodes, start, p)
end

-- Mejora local: (1) mover misiones enteras, que es lo que agrupa el trabajo por zonas y evita ir y
-- volver; (2) recolocar pasos sueltos en su mejor hueco válido.
local function LocalSearch(route, start, p)
    local improved, pass = true, 0
    local cost = RouteCost(route, start, p)
    while improved and pass < p.passes do
        improved, pass = false, pass + 1
        local seen = {}
        for i = 1, #route do
            local quest = route[i] and route[i].q
            if quest and not seen[quest] then
                seen[quest] = true
                local candidate = MoveQuest(route, quest, start, p)
                if candidate then
                    local newCost = RouteCost(candidate, start, p)
                    if newCost < cost - 0.5 then
                        route, cost, improved = candidate, newCost, true
                    end
                end
            end
        end
        for i = 1, #route do
            local node = table.remove(route, i)
            local first, last = ValidRange(route, node)
            local bestI = BestInsert(route, node, first, last, start, p)
            table.insert(route, bestI, node)
            local newCost = RouteCost(route, start, p)
            if newCost < cost - 0.5 then
                cost, improved = newCost, true
            else
                table.remove(route, bestI)
                table.insert(route, i, node)
            end
        end
    end
    return route, cost
end

-- Poda final: con la ruta ya completa, quita una a una las misiones que aportan menos XP por el
-- tiempo que ocupan si no llegan al umbral (más bajo para las del diario). Hace falta porque las del
-- diario se insertan primero, contra una ruta aún vacía, y entonces nunca parecen malas. No toca
-- misiones que abren una continuación que sigue en la ruta.
local function Prune(route, cost, totalValue, entryOf, skipped, start, p)
    local removed = 0
    while removed < 15 and cost > 0 do
        local hasSuccessor, quests = {}, {}
        for _, node in ipairs(route) do
            quests[node.q] = true
            for pred in pairs(node.q.afterSet or {}) do
                hasSuccessor[pred] = true
            end
        end
        local routeRate = totalValue / cost
        local worst, worstScore, worstRoute, worstCost, worstRate
        for quest in pairs(quests) do
            local entry = entryOf[quest]
            if entry and not hasSuccessor[quest] then
                local without = {}
                for _, node in ipairs(route) do
                    if node.q ~= quest then
                        without[#without + 1] = node
                    end
                end
                local newCost = RouteCost(without, start, p)
                local rate = (entry.value + (entry.bonus or 0)) / math.max(cost - newCost, 1)
                local ratio = quest.inLog and p.keepRatio or p.minRatio
                local score = rate / math.max(routeRate * ratio, 1e-9)
                if score < 1 and (not worstScore or score < worstScore) then
                    worst, worstScore, worstRoute, worstCost, worstRate = quest, score, without, newCost, rate
                end
            end
        end
        if not worst then
            break
        end
        route, cost = worstRoute, worstCost
        totalValue = totalValue - entryOf[worst].value
        skipped[#skipped + 1] = { quest = worst, reason = "rate", rate = worstRate }
        removed = removed + 1
    end
    if removed > 0 then
        route, cost = LocalSearch(route, start, p)
    end
    return route, cost, totalValue
end

-- Misiones a evitar, a partir de las descartadas por un plan: primero las del diario (conviene
-- abandonarlas o dejarlas para luego), después las cercanas que no merecen el desvío; dentro de cada
-- grupo, de peor a mejor XP por hora. Las que solo «no caben» o dependen de otra no se avisan: no
-- son malas, solo van después.
function Planner.AvoidList(plan, limit)
    local list = {}
    for _, entry in ipairs(plan and plan.skipped or {}) do
        local quest = entry.quest
        if entry.reason == "rate" or (quest.inLog and entry.reason == "time") then
            list[#list + 1] = {
                questID = quest.id,
                name = quest.name,
                inLog = quest.inLog and true or false,
                reason = entry.reason,
                xpPerHour = (entry.rate or 0) * 3600,
            }
            local point = quest.pickup or (quest.objectives and quest.objectives[1]) or quest.turnin
            if point then
                list[#list].x, list[#list].y = point.x, point.y
            end
        end
    end
    table.sort(list, function(a, b)
        if a.inLog ~= b.inLog then
            return a.inLog
        end
        if a.xpPerHour ~= b.xpPerHour then
            return a.xpPerHour < b.xpPerHour
        end
        return a.questID < b.questID
    end)
    if limit then
        for i = #list, limit + 1, -1 do
            list[i] = nil
        end
    end
    return list
end

function Planner.Key(questID, kind, index)
    return questID .. ":" .. kind .. ":" .. (index or 0)
end

local function Merge(defaults, params)
    local p = {}
    for key, value in pairs(defaults) do
        p[key] = value
    end
    for key, value in pairs(params or {}) do
        p[key] = value
    end
    return p
end

-- quests: { id, name, xp, inLog, pickup = {x,y}?, objectives = {{x,y,work,label}}, turnin = {x,y}? }
-- params: start = {x,y}, w, h (yardas del mapa) y, opcionalmente, cualquier clave de DEFAULTS.
function Planner.Plan(quests, params)
    local p = Merge(Planner.DEFAULTS, params)
    local start = p.start
    assert(start and p.w and p.h, "Planner.Plan necesita start, w y h")

    -- Cadenas: quest.after lista los IDs de las misiones que hay que entregar antes de recogerla.
    local byID = {}
    for _, quest in ipairs(quests) do
        byID[quest.id] = quest
    end
    for _, quest in ipairs(quests) do
        quest.afterSet, quest.depth = nil, 0
        for _, id in ipairs(quest.after or {}) do
            local pred = byID[id]
            if pred then
                quest.afterSet = quest.afterSet or {}
                quest.afterSet[pred] = true
            end
        end
    end
    local function Depth(quest, guard)
        if not quest.afterSet or guard > 10 then
            return 0
        end
        local depth = 0
        for pred in pairs(quest.afterSet) do
            depth = math.max(depth, Depth(pred, guard + 1) + 1)
        end
        return depth
    end

    -- Eficiencia aislada de cada misión, para decidir el orden de inserción.
    local entries, entryOf = {}, {}
    for _, quest in ipairs(quests) do
        local nodes = BuildNodes(quest, p)
        if #nodes > 0 then
            quest.depth = Depth(quest, 0)
            local solo = RouteCost(nodes, start, p)
            local value = QuestValue(quest, p)
            local entry = { quest = quest, nodes = nodes, value = value, solo = solo }
            entries[#entries + 1] = entry
            entryOf[quest] = entry
        end
    end
    -- Una misión que abre continuaciones vale también por lo que desbloquea (a medias: aún hay que
    -- hacerlas), así una entrega floja que abre una cadena buena no se descarta.
    for _, entry in ipairs(entries) do
        entry.bonus = 0
    end
    for _, entry in ipairs(entries) do
        for pred in pairs(entry.quest.afterSet or {}) do
            local predEntry = entryOf[pred]
            if predEntry then
                predEntry.bonus = predEntry.bonus + entry.value * p.chainBonus
            end
        end
    end
    for _, entry in ipairs(entries) do
        entry.rate = (entry.value + entry.bonus) / math.max(entry.solo, 1)
    end
    table.sort(entries, function(a, b)
        if a.quest.depth ~= b.quest.depth then
            return a.quest.depth < b.quest.depth
        end
        if (a.quest.inLog and true or false) ~= (b.quest.inLog and true or false) then
            return a.quest.inLog and true or false
        end
        if a.rate ~= b.rate then
            return a.rate > b.rate
        end
        return a.quest.id < b.quest.id
    end)

    local route, totalValue, skipped, accepted = {}, 0, {}, {}

    -- Estabilidad: si hay un plan anterior (p.previous = lista de claves "id:tipo:índice"), se parte
    -- de su orden con las misiones que siguen siendo válidas. La mejora local solo lo cambia si
    -- ahorra tiempo, así la ruta no cambia de idea a cada paso.
    if p.previous and #p.previous > 0 then
        local nodeByKey = {}
        for _, entry in ipairs(entries) do
            for _, node in ipairs(entry.nodes) do
                nodeByKey[Planner.Key(node.q.id, node.kind, node.index)] = node
            end
        end
        local seeded = {}
        for _, key in ipairs(p.previous) do
            local node = nodeByKey[key]
            if node and not seeded[node] then
                local first, last = ValidRange(route, node)
                if first <= last then
                    table.insert(route, last, node)
                    seeded[node] = true
                end
            end
        end
        for _, entry in ipairs(entries) do
            local any = false
            for _, node in ipairs(entry.nodes) do
                if seeded[node] then
                    any = true
                end
            end
            if any then
                for _, node in ipairs(entry.nodes) do
                    if not seeded[node] then
                        local first, last = ValidRange(route, node)
                        local i = BestInsert(route, node, first, math.max(first, last), start, p)
                        table.insert(route, i, node)
                    end
                end
                accepted[entry.quest] = true
                totalValue = totalValue + entry.value
                entry.seeded = true
            end
        end
    end

    for _, entry in ipairs(entries) do
        local reason
        if entry.seeded then
            reason = "seeded"
        end
        for pred in pairs(entry.quest.afterSet or {}) do
            if not accepted[pred] or not pred.turnin then
                reason = "chain"
            end
        end
        local candidate, added
        if not reason then
            candidate, added = InsertQuest(route, entry.nodes, start, p)
            if not candidate then
                reason = "chain"
            end
        end
        if not reason then
            local cost = RouteCost(route, start, p)
            local routeRate = cost > 0 and totalValue / cost or 0
            local marginal = (entry.value + entry.bonus) / math.max(added or 0, 1)
            local threshold = routeRate * (entry.quest.inLog and p.keepRatio or p.minRatio)
            if cost + added > p.maxSeconds and #route > 0 then
                reason = "time"
            elseif marginal < threshold then
                reason = "rate"
            end
            entry.marginal = marginal
        end
        if reason == "seeded" then -- luacheck: ignore 542
            -- ya está en la ruta desde el plan anterior
        elseif reason then
            skipped[#skipped + 1] = { quest = entry.quest, reason = reason, rate = entry.marginal or 0 }
        elseif not entry.seeded then
            route, totalValue = candidate or route, totalValue + entry.value
            accepted[entry.quest] = true
        end
    end

    local cost
    route, cost = LocalSearch(route, start, p)
    route, cost, totalValue = Prune(route, cost, totalValue, entryOf, skipped, start, p)

    -- Pasos con tiempo acumulado (llegada estimada a cada uno).
    local steps, elapsed, prev = {}, 0, start
    for i, node in ipairs(route) do
        elapsed = elapsed + Distance(prev, node, p.w, p.h) / p.speed
        steps[i] = {
            kind = node.kind,
            questID = node.q.id,
            name = node.q.name,
            x = node.x,
            y = node.y,
            label = node.label,
            index = node.index,
            work = node.work,
            chained = node.q.afterSet ~= nil,
            key = Planner.Key(node.q.id, node.kind, node.index),
            arrive = elapsed,
        }
        elapsed = elapsed + node.work
        prev = node
    end

    return {
        steps = steps,
        seconds = cost,
        xp = totalValue,
        xpPerHour = cost > 0 and totalValue * 3600 / cost or 0,
        skipped = skipped,
    }
end

return Planner
