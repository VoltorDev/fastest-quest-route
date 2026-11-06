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
    -- Una misión nueva debe dar al menos este % del ritmo de XP de la ruta. Calibrado contra las guías
    -- de RestedXP de Forever (Durotar 1-12 y Baldíos 12-22, 06-11-2026): con 0,4 descartaba misiones
    -- que la guía sí hace una vez que la ruta ganó ritmo con los objetivos solapados.
    minRatio = 0.25,
    keepRatio = 0.2, -- umbral (más bajo) para las del diario: ya están empezadas
    offMapFactor = 0.5, -- XP que se cuenta si la entrega está fuera de este mapa
    maxSeconds = 90 * 60, -- tope de duración de la ruta: lo que no quepa se deja para después
    passes = 25, -- pasadas máximas de mejora local
    -- Parte del valor de cada continuación que se suma a la misión que la abre, eslabón a eslabón:
    -- una cadena vale Σ valor_k · chainBonus^k (las guías deciden por cadena entera, no por misión).
    chainBonus = 0.5,
    -- Peso del momento medio (ponderado por XP) de las entregas listas en la mejora local. En las guías
    -- de RestedXP de Forever solo el 2,6 % de las entregas se retrasa tras pasar junto al PNJ.
    turninDelay = 1.0,
    -- Objetivos de misiones distintas a menos de overlapYards se hacen a la vez (las guías hacen así un
    -- tercio de los objetivos): el que va detrás cuesta overlapFactor de su trabajo.
    overlapYards = 150,
    overlapFactor = 0.7,
    hubYards = 40, -- dadores a menos de esta distancia forman un campamento (RetryHubs)
}

local KIND_ORDER = { pickup = 1, objective = 2, turnin = 3 }

local function Distance(a, b, w, h)
    local dx = (a.x - b.x) * w / 100
    local dy = (a.y - b.y) * h / 100
    return sqrt(dx * dx + dy * dy)
end
Planner.Distance = Distance

-- Segundos de ir de `prev` a `node` y hacer `node`. Dos objetivos seguidos de misiones distintas
-- en la misma zona de caza se solapan: el segundo cuesta una parte de su trabajo.
local function StepCost(prev, node, p)
    local distance = Distance(prev, node, p.w, p.h)
    local work = node.work
    if
        node.kind == "objective"
        and prev.kind == "objective"
        and prev.q ~= node.q
        and distance <= (p.overlapYards or 0)
    then
        work = work * (p.overlapFactor or 1)
    end
    return distance / p.speed + work
end
Planner.StepCost = StepCost

-- Coste total (segundos) de una ruta: desplazamientos + trabajo en cada paso.
local function RouteCost(route, start, p)
    local total, prev = 0, start
    for i = 1, #route do
        local node = route[i]
        total = total + StepCost(prev, node, p)
        prev = node
    end
    return total
end
Planner.RouteCost = RouteCost

-- Coste de meter `node` entre route[i-1] (o la partida) y route[i] (o nada).
local function InsertDelta(route, i, node, start, p)
    local prev = route[i - 1] or start
    local nextNode = route[i]
    local add = StepCost(prev, node, p)
    if nextNode then
        add = add + StepCost(node, nextNode, p) - StepCost(prev, nextNode, p)
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

-- Entrega de una misión ya completa: su único nodo es la entrega (ver BuildNodes).
local function IsReadyTurnin(node)
    return node.kind == "turnin" and not node.q.pickup and #(node.q.objectives or {}) == 0
end

-- Puntuación de la mejora local: tiempo total más el momento medio, ponderado por XP, en que se
-- entregan las misiones ya completas. Con solo el tiempo total, aplazar una entrega cercana hasta
-- la vuelta de un objetivo lejano sale gratis o incluso ahorra unos segundos, y la ruta pasaba de
-- largo por el PNJ.
local function RouteScore(route, start, p)
    local total, prev, weighted, value = 0, start, 0, 0
    for i = 1, #route do
        local node = route[i]
        total = total + StepCost(prev, node, p)
        if IsReadyTurnin(node) then
            local v = math.max(QuestValue(node.q, p), 1)
            weighted, value = weighted + v * total, value + v
        end
        prev = node
    end
    if value > 0 then
        total = total + p.turninDelay * weighted / value
    end
    return total
end

-- Mejor hueco para una entrega lista según la puntuación (no solo el tiempo): prueba cada posición válida.
local function BestScoreInsert(route, node, first, last, start, p)
    -- Sin recorrer la ruta por cada hueco: meter el nodo en i retrasa en `delta` todo lo que va
    -- detrás, así que la puntuación nueva sale de los tiempos de llegada y del XP de las entregas
    -- listas que quedan a partir de i (calculados una vez).
    local n = #route
    local finish, total, prev, weighted, value = {}, 0, start, 0, 0
    for i = 1, n do
        local other = route[i]
        total = total + StepCost(prev, other, p)
        finish[i] = total
        if IsReadyTurnin(other) then
            local v = math.max(QuestValue(other.q, p), 1)
            weighted, value = weighted + v * total, value + v
        end
        prev = other
    end
    local after = { [n + 1] = 0 }
    for i = n, 1, -1 do
        local other = route[i]
        after[i] = after[i + 1] + (IsReadyTurnin(other) and math.max(QuestValue(other.q, p), 1) or 0)
    end
    local v = math.max(QuestValue(node.q, p), 1)
    local bestI, bestScore = first, huge
    for i = first, last do
        local delta = InsertDelta(route, i, node, start, p)
        local arrive = (finish[i - 1] or 0) + StepCost(route[i - 1] or start, node, p)
        local score = total + delta + p.turninDelay * (weighted + delta * after[i] + v * arrive) / (value + v)
        if score < bestScore then
            bestI, bestScore = i, score
        end
    end
    return bestI
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
    local score = RouteScore(route, start, p)
    while improved and pass < p.passes do
        improved, pass = false, pass + 1
        local seen = {}
        for i = 1, #route do
            local quest = route[i] and route[i].q
            if quest and not seen[quest] then
                seen[quest] = true
                local candidate = MoveQuest(route, quest, start, p)
                if candidate then
                    local newScore = RouteScore(candidate, start, p)
                    if newScore < score - 0.5 then
                        route, score, improved = candidate, newScore, true
                    end
                end
            end
        end
        for i = 1, #route do
            local node = table.remove(route, i)
            local first, last = ValidRange(route, node)
            local bestI
            if IsReadyTurnin(node) then
                bestI = BestScoreInsert(route, node, first, last, start, p)
            else
                bestI = BestInsert(route, node, first, last, start, p)
            end
            table.insert(route, bestI, node)
            local newScore = RouteScore(route, start, p)
            if newScore < score - 0.5 then
                score, improved = newScore, true
            else
                table.remove(route, bestI)
                table.insert(route, i, node)
            end
        end
    end
    return route, RouteCost(route, start, p)
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

-- Campamentos: misión a misión, la primera de un campamento lejano carga con todo el viaje y se
-- descarta, y la segunda también. Las guías deciden por campamento (recogen 3 o más de golpe en el
-- 42 % de las aceptaciones), así que las descartadas por ritmo que comparten dador (a menos de
-- hubYards) se prueban juntas: entran si entre todas compensan el viaje.
local function RetryHubs(route, totalValue, skipped, entryOf, accepted, start, p)
    local hubs = {}
    for _, entry in ipairs(skipped) do
        local quest = entry.quest
        if entry.reason == "rate" and quest.pickup and not quest.inLog and not quest.afterSet then
            local hub
            for _, other in ipairs(hubs) do
                if Distance(other[1].pickup, quest.pickup, p.w, p.h) <= p.hubYards then
                    hub = other
                    break
                end
            end
            if not hub then
                hub = {}
                hubs[#hubs + 1] = hub
            end
            hub[#hub + 1] = quest
        end
    end
    local taken = {}
    for _, hub in ipairs(hubs) do
        if #hub >= 2 then
            local candidate, value, ok = route, 0, true
            for _, quest in ipairs(hub) do
                local entry = entryOf[quest]
                local nextRoute = InsertQuest(candidate, entry.nodes, start, p)
                if not nextRoute then
                    ok = false
                    break
                end
                candidate, value = nextRoute, value + entry.value + (entry.bonus or 0)
            end
            if ok then
                local cost = RouteCost(route, start, p)
                local added = RouteCost(candidate, start, p) - cost
                local routeRate = cost > 0 and totalValue / cost or 0
                if cost + added <= p.maxSeconds and value / math.max(added, 1) >= routeRate * p.minRatio then
                    route = candidate
                    for _, quest in ipairs(hub) do
                        totalValue = totalValue + entryOf[quest].value
                        accepted[quest] = true
                        taken[quest] = true
                    end
                end
            end
        end
    end
    for i = #skipped, 1, -1 do
        if taken[skipped[i].quest] then
            table.remove(skipped, i)
        end
    end
    return route, totalValue
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
    -- Toda la cadena, no solo el siguiente eslabón: de las más profundas a las primeras, cada una
    -- pasa a su previa su valor más lo que ya acumuló de las suyas.
    local byDepth = {}
    for i, entry in ipairs(entries) do
        byDepth[i] = entry
    end
    table.sort(byDepth, function(a, b)
        return a.quest.depth > b.quest.depth
    end)
    for _, entry in ipairs(byDepth) do
        for pred in pairs(entry.quest.afterSet or {}) do
            local predEntry = entryOf[pred]
            if predEntry and pred.depth < entry.quest.depth then
                predEntry.bonus = predEntry.bonus + (entry.value + entry.bonus) * p.chainBonus
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

    route, totalValue = RetryHubs(route, totalValue, skipped, entryOf, accepted, start, p)

    local cost
    route, cost = LocalSearch(route, start, p)
    route, cost, totalValue = Prune(route, cost, totalValue, entryOf, skipped, start, p)

    -- Pasos con tiempo acumulado (llegada estimada a cada uno).
    local steps, elapsed, prev = {}, 0, start
    for i, node in ipairs(route) do
        local stepCost = StepCost(prev, node, p)
        local travel = Distance(prev, node, p.w, p.h) / p.speed
        elapsed = elapsed + travel
        steps[i] = {
            kind = node.kind,
            questID = node.q.id,
            name = node.q.name,
            x = node.x,
            y = node.y,
            label = node.label,
            index = node.index,
            work = stepCost - travel,
            chained = node.q.afterSet ~= nil,
            key = Planner.Key(node.q.id, node.kind, node.index),
            arrive = elapsed,
        }
        elapsed = elapsed + stepCost - travel
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
