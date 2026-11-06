-- Tiempo de viaje entre dos puntos del mundo: a pie en línea recta, o andando hasta un maestro de
-- vuelo conocido, volando (FlightData.lua) y andando desde el de llegada. Los barcos y zepelines
-- unen continentes con un tiempo estimado. Lógica pura: las posiciones y los nodos conocidos los
-- pone Route con la API del cliente.
local _, ns = ...
local Travel = {}
ns.Travel = Travel

-- Barco o zepelín, con la espera media incluida. ESTIMACIÓN, no medida: ~2-3 min de trayecto más
-- media vuelta de espera.
Travel.TRANSPORT_SECONDS = 360

-- Transportes entre maestros de vuelo (nodeID de C_TaxiMap) junto a cada muelle, por facción.
Travel.TRANSPORTS = {
    A = {
        { 7, 26 }, -- Puerto de Menethil - Auberdine
        { 7, 32 }, -- Puerto de Menethil - Theramore
        { 19, 80 }, -- Bahía del Botín - Trinquete
    },
    H = {
        { 23, 11 }, -- Orgrimmar - Entrañas
        { 23, 20 }, -- Orgrimmar - Grom'gol
        { 11, 20 }, -- Entrañas - Grom'gol
        { 18, 80 }, -- Bahía del Botín - Trinquete
    },
}

local function Walk(a, b, speed)
    if a.c ~= b.c then
        return nil
    end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy) / speed
end

-- Grafo de la facción: tramos de vuelo y transportes. Se construye una vez por tabla de tiempos.
local graphCache = setmetatable({}, { __mode = "k" })
function Travel.Graph(times, transports)
    local cached = times and graphCache[times]
    if cached and cached.transports == transports then
        return cached.edges
    end
    local edges = {}
    local function Add(a, b, seconds)
        edges[a] = edges[a] or {}
        if not edges[a][b] or seconds < edges[a][b] then
            edges[a][b] = seconds
        end
    end
    for from, list in pairs(times or {}) do
        for to, seconds in pairs(list) do
            Add(from, to, seconds)
            Add(to, from, seconds)
        end
    end
    for _, pair in ipairs(transports or {}) do
        Add(pair[1], pair[2], Travel.TRANSPORT_SECONDS)
        Add(pair[2], pair[1], Travel.TRANSPORT_SECONDS)
    end
    if times then
        graphCache[times] = { edges = edges, transports = transports }
    end
    return edges
end

-- Segundos de viaje de `from` a `to` ({ c = continente, x, y } en yardas del mundo).
-- opts: speed (yardas/s a pie), nodes ({ [nodeID] = { c, x, y } }, solo los conocidos),
-- times (FlightTimes de la facción), transports. Devuelve segundos y si conviene volar, o nil si
-- no hay forma conocida (otro continente sin nodos ni transporte).
function Travel.Seconds(from, to, opts)
    local speed = opts.speed or 7
    local best = Walk(from, to, speed)
    local nodes = opts.nodes or {}
    local edges = Travel.Graph(opts.times, opts.transports)
    -- Dijkstra desde el jugador: llegar andando a cada nodo conocido de su continente.
    local dist, done = {}, {}
    for id, node in pairs(nodes) do
        dist[id] = Walk(from, node, speed)
    end
    while true do
        local current, low
        for id, d in pairs(dist) do
            if not done[id] and (not low or d < low) then
                current, low = id, d
            end
        end
        if not current then
            break
        end
        done[current] = true
        for to_id, seconds in pairs(edges[current] or {}) do
            if nodes[to_id] and not done[to_id] then
                local candidate = low + seconds
                if not dist[to_id] or candidate < dist[to_id] then
                    dist[to_id] = candidate
                end
            end
        end
    end
    local flew = false
    for id, d in pairs(dist) do
        local tail = Walk(nodes[id], to, speed)
        if tail and (not best or d + tail < best) then
            best, flew = d + tail, true
        end
    end
    return best, flew
end

return Travel
