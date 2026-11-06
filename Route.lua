-- Pegamento con el cliente: lee el diario, la posición y las misiones completadas, llama al
-- constructor y al planificador, y pone la flecha de Blizzard en el siguiente paso.
-- Nada de esto lee datos de combate ni valores secretos; solo misiones y mapa.
local _, ns = ...
local L = ns.L
local module = ns:NewModule("Route")
ns.Route = module

local INDEX_BUDGET = 300 -- misiones de la base revisadas por fotograma al indexar un mapa
local DEFAULT_SIZE = { 4500, 3000 } -- yardas, si el cliente no da el tamaño del mapa

module.plan = nil
module.status = "idle" -- idle | nodb | indexing | nomap | ready
module.offMap = {}

local function GetLibrary()
    return rawget(_G, "LibQuestieDB")
end

-- IsDoable de Questie, si está cargado: añade sus listas negras (eventos, misiones retiradas) y
-- las reputaciones/profesiones que nuestra versión reducida no mira. Si falla, se ignora.
local function GetQuestieDoable()
    local loader = rawget(_G, "QuestieLoader")
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
        return nil
    end
    local ok, questieDB = pcall(loader.ImportModule, loader, "QuestieDB")
    if not ok or type(questieDB) ~= "table" or type(questieDB.IsDoable) ~= "function" then
        return nil
    end
    return function(questID)
        local success, result = pcall(questieDB.IsDoable, questID)
        if success then
            return result
        end
        return nil
    end
end

function module:OnEnable()
    local lib = GetLibrary()
    local ok, problem = ns.Data.CheckLibrary(lib)
    if not ok then
        self.status = "nodb"
        self.problem = problem
        ns:Print(problem == "missing" and L.ERR_NO_QUESTIEDB or problem)
        return
    end
    self.data = ns.Data.New(lib)
    self.completed = {}
    for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do
        self.completed[id] = true
    end
    for _, event in ipairs({
        "QUEST_ACCEPTED",
        "QUEST_REMOVED",
        "QUEST_LOG_UPDATE",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_LEVEL_UP",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_MOUNT_DISPLAY_CHANGED",
    }) do
        ns:RegisterEvent(event, function()
            module:RequestUpdate()
        end)
    end
    ns:RegisterEvent("QUEST_TURNED_IN", function(_, _, questID)
        if questID then
            module.completed[questID] = true
        end
        module.turnedIn = (module.turnedIn or 0) + 1
        module:RequestUpdate()
    end)
    self:RequestUpdate()
end

-- Agrupa las ráfagas de eventos (QUEST_LOG_UPDATE salta mucho) en un recálculo cada segundo.
function module:RequestUpdate()
    if self.status == "nodb" or self.pending then
        return
    end
    self.pending = true
    C_Timer.After(1, function()
        self.pending = false
        if InCombatLockdown() then
            return -- se recalcula al salir de combate (PLAYER_REGEN_ENABLED)
        end
        self:Update()
    end)
end

-- Diario de misiones en el formato que espera Builder.
function module:ReadLog(uiMap)
    local log = {}
    local poi = {}
    for _, entry in ipairs(C_QuestLog.GetQuestsOnMap(uiMap) or {}) do
        if entry.questID and entry.x and entry.y then
            poi[entry.questID] = { x = entry.x * 100, y = entry.y * 100 }
        end
    end
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
            local id = info.questID
            local objectives = {}
            for i, objective in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
                objectives[i] = {
                    type = objective.type,
                    finished = objective.finished,
                    numFulfilled = objective.numFulfilled,
                    numRequired = objective.numRequired,
                }
            end
            local xp = GetQuestLogRewardXP(id)
            log[id] = {
                title = info.title,
                level = type(info.level) == "number" and info.level or nil,
                complete = C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id) or false,
                objectives = objectives,
                xp = type(xp) == "number" and xp or nil,
                poi = poi[id],
            }
        end
    end
    return log
end

function module:ReadPlayer(log)
    local lib = self.data.lib
    -- Del propio jugador no son secretos, pero se comprueba antes de usarlos como clave.
    local _, raceFile, raceValue = UnitRace("player")
    local _, _, classValue = UnitClass("player")
    local secret = issecretvalue and (issecretvalue(raceValue) or issecretvalue(classValue))
    local raceID = not secret and raceValue or nil
    local raceToken = not (issecretvalue and issecretvalue(raceFile)) and raceFile or nil
    local classID = not secret and classValue or nil
    local inLog = {}
    for id in pairs(log) do
        inLog[id] = true
    end
    return {
        level = UnitLevel("player"),
        raceMask = raceID and lib.Enum.raceMaskById[raceID] or nil,
        classMask = classID and 2 ^ (classID - 1) or nil,
        classID = classID,
        raceToken = raceToken,
        faction = UnitFactionGroup("player"),
        completed = self.completed,
        inLog = inLog,
        ignored = ns.charDB.ignored,
    }
end

function module:Update()
    if not self.data then
        return
    end
    local uiMap = C_Map.GetBestMapForUnit("player")
    local position = uiMap and C_Map.GetPlayerMapPosition(uiMap, "player")
    if not position then
        self.status, self.plan = "nomap", nil
        ns:RefreshUI()
        return
    end
    local candidates = self.data:IndexStep(uiMap, INDEX_BUDGET)
    if not candidates then
        -- Indexar un mapa nuevo recorre toda la base: se trocea por fotogramas.
        self.status = "indexing"
        ns:RefreshUI()
        C_Timer.After(0, function()
            self:Update()
        end)
        return
    end

    local x, y = position:GetXY()
    local here = { x = x * 100, y = y * 100 }
    local width, height = C_Map.GetMapWorldSize(uiMap --[[@as number]])
    if not width or width <= 0 then
        width, height = DEFAULT_SIZE[1], DEFAULT_SIZE[2]
    end
    local log = self:ReadLog(uiMap)
    local player = self:ReadPlayer(log)
    if ns.Learned then
        ns.Learned:Observe(log, { map = uiMap, x = here.x, y = here.y })
    end
    local quests, offMap, tooHigh = ns.Builder.Build(self.data, {
        uiMap = uiMap,
        position = here,
        player = player,
        log = log,
        candidates = candidates,
        isDoable = ns.db.useQuestie and GetQuestieDoable() or nil,
        maxAbove = ns.db.maxAbove,
        learned = ns.db.useLearned and ns.db.learned or nil,
        guide = ns.db.useGuide and ns.GuideData or nil,
        titleOf = C_QuestLog.GetTitleForQuestID,
    })
    local previous = self.uiMap == uiMap and self.previousKeys or nil
    self.plan = ns.Planner.Plan(quests, {
        start = here,
        w = width,
        h = height,
        speed = module.Speed(),
        previous = previous,
    })
    self.uiMap, self.offMap, self.status = uiMap, offMap, "ready"
    self.tooHigh = tooHigh or {}
    self.previousKeys = {}
    for _, step in ipairs(self.plan.steps) do
        self.previousKeys[#self.previousKeys + 1] = step.key
    end
    self:UpdateWaypoint()
    self:UpdateZones(player, uiMap)
    ns:RefreshUI()
end

-- Siguiente zona recomendada: la que más XP disponible tiene para tu nivel. El índice de todos los
-- mapas se construye una vez, troceado por fotogramas, y la recomendación solo se recalcula al
-- cambiar de nivel, de mapa o al entregar una misión.
function module:UpdateZones(player, uiMap)
    local byMap = self.data:IndexAllStep(INDEX_BUDGET)
    if not byMap then
        if not self.zoneIndexing then
            self.zoneIndexing = true
            C_Timer.After(0, function()
                self.zoneIndexing = false
                self:RequestUpdate()
            end)
        end
        return
    end
    local key = player.level .. ":" .. (self.turnedIn or 0) .. ":" .. uiMap
    if key == self.zonesKey then
        return
    end
    self.zonesKey = key
    self.zones = self.data:RecommendZones(player, {
        exclude = uiMap,
        above = ns.db.maxAbove,
        isDoable = ns.db.useQuestie and GetQuestieDoable() or nil,
        continentOf = module.ContinentOf,
        continent = module.ContinentOf(uiMap),
        guideZones = ns.db.useGuide and module.GuideFor(ns.GuideZones, player.faction) or nil,
    })
end

-- Parte de una tabla de guías por facción (GuideZones) que toca a la facción del jugador.
function module.GuideFor(tables, faction)
    if type(tables) ~= "table" then
        return nil
    end
    return tables[faction == "Alliance" and "A" or faction == "Horde" and "H" or ""]
end

-- Continente (UiMapID) de un mapa, subiendo por los padres de C_Map.GetMapInfo. Se guarda en caché.
local continentCache = {}
function module.ContinentOf(map)
    if continentCache[map] ~= nil then
        return continentCache[map] or nil
    end
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local current, found = map, false
    for _ = 1, 10 do
        local info = current and C_Map.GetMapInfo(current)
        if not info then
            break
        end
        if info.mapType == continentType then
            found = current
            break
        end
        current = info.parentMapID
    end
    continentCache[map] = found
    return found or nil
end

function module.ZoneName(map)
    local info = C_Map.GetMapInfo(map)
    return info and info.name or ("#" .. map)
end

-- Flecha de TomTom, si está instalado: misma llamada que usa Questie en Forever
-- (TomTom:AddWaypoint(uiMapID, x 0-1, y 0-1, opciones) devuelve el identificador para quitarla).
function module:SetTomTom(step)
    local tomtom = rawget(_G, "TomTom")
    if not ns.db.useTomTom or type(tomtom) ~= "table" or type(tomtom.AddWaypoint) ~= "function" then
        return
    end
    if self.tomtomWaypoint and type(tomtom.RemoveWaypoint) == "function" then
        pcall(tomtom.RemoveWaypoint, tomtom, self.tomtomWaypoint)
    end
    local ok, uid = pcall(tomtom.AddWaypoint, tomtom, self.uiMap, step.x / 100, step.y / 100, {
        title = step.name,
        crazy = true,
        from = ns.name,
    })
    self.tomtomWaypoint = ok and uid or nil
end

-- Marcador y navegación de Blizzard (y TomTom) en el punto del paso.
function module:SetWaypoint(step)
    if not step or not step.x or not self.uiMap then
        return
    end
    if C_Map.CanSetUserWaypointOnMap(self.uiMap) then
        local point = UiMapPoint.CreateFromCoordinates(self.uiMap, step.x / 100, step.y / 100)
        C_Map.SetUserWaypoint(point)
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    self:SetTomTom(step)
end

-- Clic del jugador en un paso o en una misión a evitar: flecha y, si se quiere, el mapa abierto en
-- esa zona con el marcador puesto. El mapa no se abre en combate.
function module:GoTo(step)
    if not step or not step.x then
        return
    end
    self:SetWaypoint(step)
    if ns.db.openMapOnClick and not InCombatLockdown() and self.uiMap then
        OpenWorldMap(self.uiMap)
    end
end

-- La flecha solo se mueve cuando cambia el primer paso, para no pisar la que ponga el jugador.
function module:UpdateWaypoint()
    local step = self.plan and self.plan.steps[1]
    local key = step and step.key
    if key == self.waypointKey then
        return
    end
    self.waypointKey = key
    if step and ns.db.autoWaypoint then
        self:SetWaypoint(step)
    end
end

-- Velocidad para estimar tiempos: la de a pie de las opciones, o la real con montura. GetUnitSpeed
-- puede ser secreta con las estadísticas restringidas: entonces se queda la de las opciones.
function module.Speed()
    local base = ns.db.speed
    if IsMounted() then
        local _, runSpeed = GetUnitSpeed("player")
        if type(runSpeed) == "number" and not issecretvalue(runSpeed) and runSpeed > base then
            return runSpeed
        end
    end
    return base
end

function module:CurrentStep()
    return self.plan and self.plan.steps[1]
end

function module:Ignore(questID)
    if questID then
        ns.charDB.ignored[questID] = true
        self:RequestUpdate()
    end
end

function module:ClearIgnored()
    wipe(ns.charDB.ignored)
    self:RequestUpdate()
end
