-- Capa de datos: lee QuestieDB (LibQuestieDB, API pública con contrato) y la traduce a puntos en
-- el mapa que el planificador entiende. No copia ni redistribuye datos de Questie: los consulta en
-- tiempo de ejecución si el addon QuestieDB está cargado.
--
-- Las coordenadas de QuestieDB van en porcentaje (0-100) por AreaID de zona. El mapa del jugador
-- se identifica por UiMapID; la tabla de conversión viene de la propia QuestieDB (Support ZoneDB).
local _, ns = ...

local Data = {}
ns.Data = Data
Data.__index = Data

local floor, sqrt = math.floor, math.sqrt

Data.CONTRACT = 4 -- versión del contrato de LibQuestieDB contra la que está escrito esto

-- Segundos estimados de trabajo por unidad de objetivo (sin datos de tasa de botín).
Data.WORK = { monster = 14, item = 24, object = 10, event = 15 }
Data.DEFAULT_COUNT = { monster = 8, item = 6, object = 5, event = 1 }

-- Categorías negativas de zoneOrSort que son eventos de temporada: no se proponen.
local SEASONAL_SORTS = {
    [-22] = true,
    [-41] = true,
    [-364] = true,
    [-366] = true,
    [-369] = true,
    [-370] = true,
    [-374] = true,
    [-375] = true,
    [-376] = true,
    [-1001] = true,
    [-1002] = true,
    [-1003] = true,
    [-1005] = true,
}

-- Las máscaras de raza de Forever pasan de 2^32 (Skyborne): bit.band trunca a 32 bits, así que
-- se comprueba el bit con aritmética.
local function HasBit(mask, bitValue)
    return floor(mask / bitValue) % 2 == 1
end
Data.HasBit = HasBit

function Data.New(lib)
    local self = setmetatable({}, Data)
    self.lib = lib
    self.areaToMap = {}
    self.mapAreas = {}
    self.startIndex = {}
    self.xpByLevel = nil
    local zone = lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
    local private = zone and zone.private or {}
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
        local source = private[key]
        local tbl = source
        if type(source) == "string" then
            local chunk = loadstring(source)
            tbl = chunk and chunk() or nil
        end
        if type(tbl) == "table" then
            for area, map in pairs(tbl) do
                self.areaToMap[area] = map
            end
        end
    end
    for area, map in pairs(self.areaToMap) do
        if map and map > 0 then
            self.mapAreas[map] = self.mapAreas[map] or {}
            self.mapAreas[map][area] = true
        end
    end
    local xp = lib.Support and lib.Support.Get and lib.Support.Get("QuestXP")
    self.xpDB = xp and xp.db or {}
    return self
end

-- Comprueba que la QuestieDB instalada habla el contrato que espera este addon.
function Data.CheckLibrary(lib)
    if type(lib) ~= "table" or not lib.Quest then
        return false, "missing"
    end
    if lib.RequireContract then
        local ok, message = lib.RequireContract(Data.CONTRACT)
        if not ok then
            return false, message
        end
    end
    return true
end

-- Puntos {x, y} de una lista de spawns que caen en el mapa `uiMap`.
function Data:PointsOnMap(spawnList, uiMap)
    local points = {}
    local areas = self.mapAreas[uiMap]
    if type(spawnList) ~= "table" or not areas then
        return points
    end
    for area, list in pairs(spawnList) do
        if areas[area] and type(list) == "table" then
            for _, coord in ipairs(list) do
                local x, y = coord[1], coord[2]
                if x and y and x >= 0 and y >= 0 then
                    points[#points + 1] = { x = x, y = y }
                end
            end
        end
    end
    return points
end

-- Centro de la zona con más puntos (rejilla de 4 %), desempatando por cercanía a `ref`.
function Data.Cluster(points, ref)
    if #points == 0 then
        return nil
    end
    if #points == 1 then
        return { x = points[1].x, y = points[1].y, n = 1 }
    end
    local cells, best, bestCount, bestDist = {}, nil, -1, math.huge
    for _, point in ipairs(points) do
        local key = floor(point.x / 4) * 1000 + floor(point.y / 4)
        cells[key] = (cells[key] or 0) + 1
    end
    for key, count in pairs(cells) do
        local cx, cy = floor(key / 1000) * 4 + 2, (key % 1000) * 4 + 2
        local d = ref and ((cx - ref.x) ^ 2 + (cy - ref.y) ^ 2) or 0
        if count > bestCount or (count == bestCount and d < bestDist) then
            best, bestCount, bestDist = { x = cx, y = cy }, count, d
        end
    end
    if not best then
        return nil
    end
    local sx, sy, n = 0, 0, 0
    for _, point in ipairs(points) do
        if sqrt((point.x - best.x) ^ 2 + (point.y - best.y) ^ 2) <= 6 then
            sx, sy, n = sx + point.x, sy + point.y, n + 1
        end
    end
    return { x = sx / n, y = sy / n, n = n }
end

local function EntityPoints(self, refs, uiMap)
    -- refs: { [1] = npcIds?, [2] = objectIds? }
    local points = {}
    if type(refs) ~= "table" then
        return points
    end
    for _, npc in ipairs(refs[1] or {}) do
        for _, p in ipairs(self:PointsOnMap(self.lib.Npc.spawns(npc), uiMap)) do
            points[#points + 1] = p
        end
    end
    for _, object in ipairs(refs[2] or {}) do
        for _, p in ipairs(self:PointsOnMap(self.lib.Object.spawns(object), uiMap)) do
            points[#points + 1] = p
        end
    end
    return points
end

function Data:StarterPoint(questID, uiMap, ref)
    return Data.Cluster(EntityPoints(self, self.lib.Quest.startedBy(questID), uiMap), ref)
end

function Data:FinisherPoint(questID, uiMap, ref)
    return Data.Cluster(EntityPoints(self, self.lib.Quest.finishedBy(questID), uiMap), ref)
end

local function AppendNpcs(self, npcs, uiMap, into)
    for _, npc in ipairs(npcs or {}) do
        for _, p in ipairs(self:PointsOnMap(self.lib.Npc.spawns(npc), uiMap)) do
            into[#into + 1] = p
        end
    end
end

local function AppendObjects(self, objects, uiMap, into)
    for _, object in ipairs(objects or {}) do
        for _, p in ipairs(self:PointsOnMap(self.lib.Object.spawns(object), uiMap)) do
            into[#into + 1] = p
        end
    end
end

-- Primer número del texto de objetivos («Mata 10 alimañas…» → 10), si solo hay un objetivo.
local function CountFromText(texts, groups)
    if groups ~= 1 or type(texts) ~= "table" then
        return nil
    end
    for _, line in ipairs(texts) do
        local n = tonumber(line:match("(%d+)"))
        if n and n > 0 and n <= 50 then
            return n
        end
    end
    return nil
end

-- Objetivos de una misión en este mapa: { kind, points, label?, dbIndex }.
-- dbIndex numera los objetivos de cada tipo en el orden de la base, para casarlos con el diario.
function Data:ObjectiveGroups(questID, uiMap)
    local lib = self.lib
    local groups = {}
    local objectives = lib.Quest.objectives(questID) or {}
    local seen = { monster = 0, object = 0, item = 0, event = 0 }
    local function Add(kind, points)
        seen[kind] = seen[kind] + 1
        groups[#groups + 1] = { kind = kind, points = points, dbIndex = seen[kind] }
    end
    for _, creature in ipairs(objectives[1] or {}) do
        local points = {}
        AppendNpcs(self, { creature[1] }, uiMap, points)
        Add("monster", points)
    end
    for _, object in ipairs(objectives[2] or {}) do
        local points = {}
        AppendObjects(self, { object[1] }, uiMap, points)
        Add("object", points)
    end
    for _, item in ipairs(objectives[3] or {}) do
        local points = {}
        local itemID = item[1]
        local npcDrops = lib.Item.npcDrops(itemID)
        AppendNpcs(self, npcDrops, uiMap, points)
        AppendObjects(self, lib.Item.objectDrops(itemID), uiMap, points)
        Add("item", points)
        -- Si cae de PNJ hay que matar para conseguirlo: cuenta como XP de muertes (Builder).
        groups[#groups].fromNpc = type(npcDrops) == "table" and #npcDrops > 0
    end
    for _, credit in ipairs(objectives[5] or {}) do
        local points = {}
        AppendNpcs(self, credit[1], uiMap, points)
        Add("monster", points)
    end
    local trigger = lib.Quest.triggerEnd(questID)
    if type(trigger) == "table" and trigger[2] then
        Add("event", self:PointsOnMap(trigger[2], uiMap))
    end
    local count = CountFromText(lib.Quest.objectivesText(questID), #groups)
    for _, group in ipairs(groups) do
        group.count = count or Data.DEFAULT_COUNT[group.kind]
    end
    return groups
end

-- XP de una misión ajustada al nivel (fórmula de Vanilla: 100 % hasta 5 niveles por debajo del
-- jugador y 20 % menos por cada nivel más, mínimo 10 %). Sin dato en la base (las misiones nuevas
-- de Forever no lo tienen) usa la mediana de las misiones de ese nivel.
function Data:MedianXP(level)
    if not self.xpByLevel then
        local byLevel = {}
        for _, entry in pairs(self.xpDB) do
            local lvl, xp = entry[1], entry[2]
            if lvl and xp and lvl > 0 and xp > 0 then
                byLevel[lvl] = byLevel[lvl] or {}
                table.insert(byLevel[lvl], xp)
            end
        end
        self.xpByLevel = {}
        for lvl, list in pairs(byLevel) do
            table.sort(list)
            self.xpByLevel[lvl] = list[floor((#list + 1) / 2)]
        end
    end
    local value = self.xpByLevel[level]
    local delta = 1
    while not value and delta < 10 do
        value = self.xpByLevel[level - delta] or self.xpByLevel[level + delta]
        delta = delta + 1
    end
    return value or (100 + 60 * level)
end

function Data.AdjustXP(xp, questLevel, playerLevel)
    local multiplier = 2 * (questLevel - playerLevel) + 20
    if multiplier < 1 then
        multiplier = 1
    elseif multiplier > 10 then
        multiplier = 10
    end
    return floor(xp * multiplier / 10)
end

function Data:EstimateXP(questID, playerLevel)
    local level = self.lib.Quest.questLevel(questID) or playerLevel
    if level <= 0 then
        level = playerLevel
    end
    local entry = self.xpDB[questID]
    local base = entry and entry[2] and entry[2] > 0 and entry[2] or self:MedianXP(level)
    return Data.AdjustXP(base, level, playerLevel), entry == nil
end

-- ¿Puede el jugador coger esta misión ahora? player = { level, raceMask, classMask,
-- completed = set, inLog = set, ignored = set }. Es una versión reducida de IsDoable de Questie;
-- si Questie está cargado, Route.lua usa además el suyo.
function Data:IsAvailable(questID, player)
    local Q = self.lib.Quest
    if player.completed[questID] or player.inLog[questID] or (player.ignored and player.ignored[questID]) then
        return false
    end
    local required = Q.requiredLevel(questID) or 1
    if required > player.level then
        return false
    end
    local maxLevel = Q.requiredMaxLevel(questID)
    if maxLevel and maxLevel > 0 and player.level > maxLevel then
        return false
    end
    local races = Q.requiredRaces(questID)
    if races and races > 0 and player.raceMask and not HasBit(races, player.raceMask) then
        return false
    end
    local classes = Q.requiredClasses(questID)
    if classes and classes > 0 and player.classMask and not HasBit(classes, player.classMask) then
        return false
    end
    local sort = Q.zoneOrSort(questID)
    if sort and SEASONAL_SORTS[sort] then
        return false
    end
    local flags = Q.specialFlags(questID)
    if flags and HasBit(flags, 1) then
        return false -- repetible
    end
    local specialization = Q.requiredSpecialization(questID)
    if Q.requiredSkill(questID) or Q.requiredMinRep(questID) or (specialization and specialization > 0) then
        return false -- profesión o reputación: fuera del alcance de la ruta de subida
    end
    local single = Q.preQuestSingle(questID)
    if single and #single > 0 then
        local any = false
        for _, pre in ipairs(single) do
            if player.completed[pre] then
                any = true
                break
            end
        end
        if not any then
            return false
        end
    else
        for _, pre in ipairs(Q.preQuestGroup(questID) or {}) do
            if not player.completed[pre] then
                return false
            end
        end
    end
    for _, other in ipairs(Q.exclusiveTo(questID) or {}) do
        if player.completed[other] or player.inLog[other] then
            return false
        end
    end
    local nextQuest = Q.nextQuestInChain(questID)
    if nextQuest and nextQuest ~= 0 and (player.completed[nextQuest] or player.inLog[nextQuest]) then
        return false
    end
    local parent = Q.parentQuest(questID)
    if parent and parent ~= 0 and not player.inLog[parent] then
        return false
    end
    local breadcrumbFor = Q.breadcrumbForQuestId(questID)
    if breadcrumbFor and breadcrumbFor ~= 0 and (player.completed[breadcrumbFor] or player.inLog[breadcrumbFor]) then
        return false
    end
    local untilDone = Q.availableUntilCompleted(questID)
    if untilDone and untilDone ~= 0 and player.completed[untilDone] then
        return false
    end
    return true
end

-- Índice «misiones cuyo dador está en este mapa». Recorre toda la base una vez por mapa; se puede
-- trocear con `budget` (misiones por llamada) para no congelar el cliente. Devuelve la lista
-- cuando termina y nil mientras sigue.
function Data:IndexStep(uiMap, budget)
    local state = self.startIndex[uiMap]
    if state and state.done then
        return state.list
    end
    if not state then
        state = { ids = self.lib.Quest.GetAllIds(), pos = 0, list = {}, done = false }
        self.startIndex[uiMap] = state
    end
    local areas = self.mapAreas[uiMap]
    local npcZone, objectZone = self.lib.Npc.zoneID, self.lib.Object.zoneID
    local stop = budget and math.min(#state.ids, state.pos + budget) or #state.ids
    for i = state.pos + 1, stop do
        local id = state.ids[i]
        local starters = self.lib.Quest.startedBy(id)
        local found = false
        if areas and type(starters) == "table" then
            for _, npc in ipairs(starters[1] or {}) do
                local zone = npcZone(npc)
                if zone and areas[zone] then
                    found = true
                    break
                end
            end
            if not found then
                for _, object in ipairs(starters[2] or {}) do
                    local zone = objectZone(object)
                    if zone and areas[zone] then
                        found = true
                        break
                    end
                end
            end
        end
        if found then
            state.list[#state.list + 1] = id
        end
    end
    state.pos = stop
    if stop >= #state.ids then
        state.done = true
        return state.list
    end
    return nil
end

-- Mapa (uiMap) donde empieza una misión, o nil. Usa el primer dador con zona conocida.
function Data:StartMap(questID)
    local starters = self.lib.Quest.startedBy(questID)
    if type(starters) ~= "table" then
        return nil
    end
    for kind, zoneOf in ipairs({ self.lib.Npc.zoneID, self.lib.Object.zoneID }) do
        for _, id in ipairs(starters[kind] or {}) do
            local zone = zoneOf(id)
            local map = zone and self.areaToMap[zone]
            if map and map > 0 then
                return map
            end
        end
    end
    return nil
end

-- Índice de TODOS los mapas en una sola pasada (para recomendar zona). Troceado como IndexStep;
-- al terminar rellena también el índice por mapa, así cambiar de zona ya no recorre la base.
function Data:IndexAllStep(budget)
    local state = self.allIndex
    if state and state.done then
        return state.byMap
    end
    if not state then
        state = { ids = self.lib.Quest.GetAllIds(), pos = 0, byMap = {}, done = false }
        self.allIndex = state
    end
    local stop = budget and math.min(#state.ids, state.pos + budget) or #state.ids
    for i = state.pos + 1, stop do
        local id = state.ids[i]
        local map = self:StartMap(id)
        if map then
            state.byMap[map] = state.byMap[map] or {}
            table.insert(state.byMap[map], id)
        end
    end
    state.pos = stop
    if stop < #state.ids then
        return nil
    end
    state.done = true
    for map, list in pairs(state.byMap) do
        if not self.startIndex[map] then
            self.startIndex[map] = { done = true, list = list }
        end
    end
    return state.byMap
end

-- ¿Algún dador de la misión es amistoso con la facción ("Alliance"/"Horde")? Los PNJ de QuestieDB
-- llevan friendlyToFaction = "A", "H", "AH" o nil. Si hay algún PNJ dador, manda él (las misiones
-- de libros de Season of Discovery tienen PNJ de la Horda y además objetos); si solo hay objetos, es neutral.
function Data:FriendlyStart(questID, faction)
    local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    local starters = self.lib.Quest.startedBy(questID)
    if not letter or type(starters) ~= "table" then
        return true
    end
    local npcs = starters[1] or {}
    if #npcs == 0 then
        return true -- solo objetos u objetos de botín: neutrales
    end
    for _, npc in ipairs(npcs) do
        local friendly = self.lib.Npc.friendlyToFaction(npc)
        if not friendly or friendly:find(letter, 1, true) then
            return true
        end
    end
    return false
end

-- Capitales (UiMapID): sus misiones son de clase, profesión o entregas de paso; no son zona de subida.
Data.CAPITALS = {
    [1453] = true, -- Ventormenta
    [1454] = true, -- Orgrimmar
    [1455] = true, -- Forjaz
    [1456] = true, -- Cima del Trueno
    [1457] = true, -- Darnassus
    [1458] = true, -- Entrañas
}

-- Segundos que se tarda en una misión media de subida (recoger, hacer y entregar, sin el viaje hasta
-- la zona). ESTIMACIÓN: solo sirve para traducir el tiempo de viaje a XP que dejas de ganar.
Data.ZONE_QUEST_SECONDS = 300

-- Zonas con más XP disponible para el jugador, sin contar `exclude` (el mapa actual) ni las capitales.
-- Devuelve { { map, count, xp, far } } de más a menos XP. Con `opts.continentOf` (mapa → continente)
-- y `opts.continent` (el del jugador), las del mismo continente van antes que cualquiera de otro
-- (`far = true`): sin eso, la suma de XP mandaba a un orco de nivel 8 a Tirisfal, la zona de inicio de
-- los no-muertos al otro lado del mar, antes que a Los Baldíos. Requiere IndexAllStep terminado.
-- Con `opts.travel(mapa, x, y)` (segundos de viaje hasta ese punto, o nil), a la XP de cada zona se
-- le resta lo que dejarías de ganar mientras viajas (`net`), y una zona de otro continente a la que
-- sabes llegar deja de ir detrás de las demás.
function Data:RecommendZones(player, opts)
    local byMap = self.allIndex and self.allIndex.done and self.allIndex.byMap
    if not byMap then
        return nil
    end
    local minLevel = player.level - (opts.below or 2)
    local maxLevel = player.level + (opts.above or 2)
    local list = {}
    -- XP que se deja de ganar por segundo de viaje: la de una misión media de tu nivel en el tiempo
    -- que se tarda en hacerla.
    local xpPerSecond = (self:MedianXP(player.level) or 0) / Data.ZONE_QUEST_SECONDS
    for map, ids in pairs(byMap) do
        if map ~= opts.exclude and not Data.CAPITALS[map] then
            local count, xp, points = 0, 0, {}
            for _, id in ipairs(ids) do
                local level = self.lib.Quest.questLevel(id) or 0
                local ok = level >= minLevel and level <= maxLevel and self:IsAvailable(id, player)
                if ok and self:FriendlyStart(id, player.faction) then
                    if not opts.isDoable or opts.isDoable(id) ~= false then
                        count = count + 1
                        xp = xp + (self:EstimateXP(id, player.level) or 0)
                        if opts.travel then
                            points[#points + 1] = self:StarterPoint(id, map)
                        end
                    end
                end
            end
            if count >= (opts.minCount or 3) then
                local onGuide = false
                for _, zone in ipairs(opts.guideZones or {}) do
                    if zone[1] == map and player.level >= zone[2] - 1 and player.level <= zone[3] + 1 then
                        onGuide = true
                    end
                end
                local far = false
                if opts.continentOf and opts.continent then
                    far = opts.continentOf(map) ~= opts.continent
                end
                -- Viaje hasta el campamento con más dadores de la zona (nil si no se sabe).
                local travel, flew
                local hub = opts.travel and Data.Cluster(points)
                if hub then
                    travel, flew = opts.travel(map, hub.x, hub.y)
                end
                local net = xp - (travel or 0) * xpPerSecond
                list[#list + 1] = {
                    map = map,
                    count = count,
                    xp = xp,
                    far = far and not travel,
                    onGuide = onGuide,
                    travel = travel,
                    flew = flew,
                    net = net,
                }
            end
        end
    end
    -- Primero las zonas que las guías hacen a tu nivel (ya cuentan la densidad de misiones, aunque
    -- estén en otro continente); después, las que se sabe cómo alcanzar (mismo continente, o con
    -- vuelos y barcos conocidos); y dentro de cada grupo, por XP neta del viaje. Sin datos de viaje
    -- (opts.travel), la XP neta es la total y el orden es el de siempre.
    table.sort(list, function(a, b)
        if a.onGuide ~= b.onGuide then
            return a.onGuide
        end
        if a.far ~= b.far then
            return not a.far
        end
        if a.net ~= b.net then
            return a.net > b.net
        end
        if a.xp ~= b.xp then
            return a.xp > b.xp
        end
        return a.map < b.map
    end)
    for i = #list, (opts.limit or 3) + 1, -1 do
        list[i] = nil
    end
    return list
end

return Data
