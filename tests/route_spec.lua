-- Flujo completo en el cliente simulado: eventos → diario → plan → flecha → ventana, con una
-- QuestieDB falsa con la forma de la real y un mapa/diario de juguete.
package.path = "tests/support/?.lua;" .. package.path
local WowEnv = require("wow_env")
local Fake = require("fake_questiedb")

local TOC = "RutaMisiones.toc"

-- Cliente de misiones y mapa simulado. `world` es mutable desde el test.
local function Client(world)
    local function Vector(x, y)
        return {
            GetXY = function()
                return x, y
            end,
        }
    end
    return {
        LibQuestieDB = Fake.durotar(),
        OpenWorldMap = function(map)
            world.openedMap = map
        end,
        TomTom = world.tomtom,
        UnitLevel = function()
            return world.level
        end,
        UnitRace = function()
            return "Orc", "Orc", 2
        end,
        UnitClass = function()
            return "Warlock", "WARLOCK", 9
        end,
        GetQuestLogRewardXP = function(id)
            return world.log[id] and world.log[id].xp or 0
        end,
        C_Map = {
            GetBestMapForUnit = function()
                return world.map
            end,
            GetPlayerMapPosition = function(_, _)
                return world.map and Vector(world.x / 100, world.y / 100) or nil
            end,
            GetMapWorldSize = function()
                return 5287.5, 3525
            end,
            -- Mundo de juguete: 1 yarda = 0,0001 del mapa; Kalimdor y sus zonas en la instancia 1.
            GetWorldPosFromMapPos = function(map, position)
                local x, y = position:GetXY()
                local continent = (map == 1414 or map == 1411 or map == 1413) and 1 or 0
                return continent, Vector(x * 10000, y * 10000)
            end,
            CanSetUserWaypointOnMap = function()
                return true
            end,
            SetUserWaypoint = function(point)
                world.waypoint = point
            end,
            GetMapInfo = function(map)
                local maps = {
                    [1411] = { mapID = 1411, name = "Durotar", mapType = 3, parentMapID = 1414 },
                    [1413] = { mapID = 1413, name = "Los Baldíos", mapType = 3, parentMapID = 1414 },
                    [1414] = { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 },
                    [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 946 },
                }
                return maps[map]
            end,
        },
        CreateVector2D = Vector,
        -- Maestros de vuelo: posiciones en el mapa de continente (0-1).
        C_TaxiMap = {
            GetTaxiNodesForMap = function(map)
                local list = {}
                for _, node in ipairs(world.taxi or {}) do
                    if node.map == map then
                        list[#list + 1] = {
                            nodeID = node.id,
                            position = Vector(node.x, node.y),
                            faction = node.faction,
                            isUndiscovered = node.undiscovered or false,
                        }
                    end
                end
                return list
            end,
        },
        C_SuperTrack = {
            SetSuperTrackedUserWaypoint = function(on)
                world.supertracked = on
            end,
        },
        UiMapPoint = {
            CreateFromCoordinates = function(map, x, y)
                return { uiMapID = map, x = x, y = y }
            end,
        },
        C_QuestLog = {
            GetAllCompletedQuestIDs = function()
                local ids = {}
                for id in pairs(world.completed) do
                    ids[#ids + 1] = id
                end
                return ids
            end,
            GetQuestsOnMap = function()
                return world.pois or {}
            end,
            GetNumQuestLogEntries = function()
                return #world.order, #world.order
            end,
            GetInfo = function(index)
                local id = world.order[index]
                return id and { questID = id, title = world.log[id].title, isHeader = false, isHidden = false }
            end,
            GetQuestObjectives = function(id)
                return world.log[id].objectives
            end,
            ReadyForTurnIn = function(id)
                return world.log[id].complete
            end,
            IsComplete = function(id)
                return world.log[id].complete
            end,
            GetTitleForQuestID = function(id)
                return world.titles and world.titles[id]
            end,
        },
    }
end

-- Primer paso de la ruta que pertenece a `questID`.
local function StepFor(ns, questID)
    for _, step in ipairs(ns.Route.plan.steps) do
        if step.questID == questID then
            return step
        end
    end
end

local function NewWorld()
    return { level = 2, map = 1411, x = 42, y = 68, log = {}, order = {}, completed = {} }
end

local function Boot(world, opts)
    opts = opts or {}
    opts.globals = Client(world)
    local env, ns = WowEnv.boot(TOC, opts)
    env:Advance(1.1)
    return env, ns
end

local function Accept(env, world, id, title)
    world.log[id] = {
        title = title,
        complete = false,
        xp = 200,
        objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } },
    }
    world.order[#world.order + 1] = id
    env:Fire("QUEST_ACCEPTED", id)
    env:Advance(1.1)
end

describe("ruta en el cliente simulado: continente y nombres del cliente", function()
    it("sube por los mapas padre hasta el continente y usa el título que da el cliente", function()
        local world = NewWorld()
        world.titles = { [100] = "Jabalíes (cliente)" }
        local env, ns = Boot(world)
        assert.are.same({}, env:Missing())
        assert.are.equal(1414, ns.Route.ContinentOf(1411))
        assert.are.equal(1414, ns.Route.ContinentOf(1413))
        assert.is_nil(ns.Route.ContinentOf(4242)) -- mapa desconocido
        assert.are.equal("Jabalíes (cliente)", ns.Route:CurrentStep().name)
    end)

    it("toma de las guías las zonas de la facción del jugador", function()
        local world = NewWorld()
        local _, ns = Boot(world)
        local tables = { A = { { 1429, 1, 13 } }, H = { { 1411, 1, 10 } } }
        assert.are.same({ { 1429, 1, 13 } }, ns.Route.GuideFor(tables, "Alliance"))
        assert.are.same({ { 1411, 1, 10 } }, ns.Route.GuideFor(tables, "Horde"))
        assert.is_nil(ns.Route.GuideFor(tables, "Neutral"))
        assert.is_nil(ns.Route.GuideFor(nil, "Horde"))
        assert.are.equal(1436, ns.GuideZones.A[1][1]) -- el fichero real carga con el addon
    end)
end)

describe("viaje hasta la siguiente zona", function()
    it("lee los maestros de vuelo que conoces y los relee al abrir el mapa de vuelo", function()
        local world = NewWorld()
        world.taxi = {
            { id = 23, map = 1414, x = 0.5, y = 0.1, faction = 1 }, -- Orgrimmar, de la Horda
            { id = 25, map = 1414, x = 0.5, y = 0.5, faction = 0, undiscovered = true },
            { id = 2, map = 1415, x = 0.5, y = 0.5, faction = 2 }, -- de la Alianza: no cuenta
        }
        local env, ns = Boot(world)
        assert.are.same({}, env:Missing())
        local nodes = ns.Route.KnownNodes("Horde")
        assert.are.same({ c = 1, x = 5000, y = 1000 }, nodes[23])
        assert.is_nil(nodes[25])
        assert.is_nil(nodes[2])
        world.taxi[2].undiscovered = false
        assert.is_nil(ns.Route.KnownNodes("Horde")[25]) -- en caché hasta abrir el mapa de vuelo
        env:Fire("TAXIMAP_OPENED", 1)
        assert.is_truthy(ns.Route.KnownNodes("Horde")[25])
        -- Viaje desde donde estás (42, 68 en Durotar) a pie: 0,01 del mapa son 100 yardas.
        local travel = ns.Route.TravelFrom(1411, { x = 42, y = 68 }, "Horde")
        local seconds = travel(1411, 42, 69)
        assert.is_true(math.abs(seconds - 100 / ns.db.speed) < 1e-6)
        assert.is_nil(ns.Route.TravelFrom(1411, nil, "Horde"))
    end)
end)

describe("ruta en el cliente simulado", function()
    it("al entrar calcula la ruta, pone la flecha en el primer paso y lo lista", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        assert.are.same({}, env:Missing())
        assert.are.equal("ready", ns.Route.status)
        local first = ns.Route:CurrentStep()
        assert.are.equal("pickup", first.kind)
        assert.are.equal(100, first.questID)
        assert.are.equal(1411, world.waypoint.uiMapID)
        assert.is_true(math.abs(world.waypoint.x - 0.42) < 1e-6)
        assert.is_true(world.supertracked)
        -- La ventana muestra el paso con su verbo y el resumen de la ruta.
        local texts = {}
        for _, fs in ipairs(env:Widgets("FontString")) do
            texts[#texts + 1] = fs:GetText() or ""
        end
        local all = table.concat(texts, "\n")
        assert.is_truthy(all:find("Matar jabalíes", 1, true)) -- título de la misión, en el seguidor
        assert.is_truthy(all:find("!|r Pick up", 1, true)) -- y debajo, qué hacer en ella
        assert.is_truthy(all:find("XP/h", 1, true))
    end)

    it("al aceptar la misión avanza al objetivo y mueve la flecha", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        Accept(env, world, 100, "Matar jabalíes")
        assert.are.equal("objective", StepFor(ns, 100).kind)
        local current = ns.Route:CurrentStep()
        assert.is_true(math.abs(world.waypoint.x * 100 - current.x) < 1e-6)
    end)

    it("al completar los objetivos propone entregar y luego la continuación", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        Accept(env, world, 100, "Matar jabalíes")
        world.log[100].complete = true
        world.log[100].objectives[1].finished = true
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(1.1)
        assert.are.equal("turnin", StepFor(ns, 100).kind)
        -- Entregada: sale del diario, cuenta como completada y aparece la 101 (cadena).
        world.log[100], world.order = nil, {}
        world.completed[100] = true
        env:Fire("QUEST_TURNED_IN", 100, 200, 0)
        env:Advance(1.1)
        assert.is_nil(StepFor(ns, 100))
        assert.are.equal("pickup", StepFor(ns, 101).kind)
    end)

    it("en combate no recalcula; lo hace al salir", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        env:SetCombat(true)
        Accept(env, world, 100, "Matar jabalíes")
        assert.are.equal("pickup", StepFor(ns, 100).kind)
        env:SetCombat(false)
        env:Fire("PLAYER_REGEN_ENABLED")
        env:Advance(1.1)
        assert.are.equal("objective", StepFor(ns, 100).kind)
    end)

    it("ignorar una misión la saca de la ruta y lo guarda por personaje", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        env:RunSlash("/ruta ignorar")
        env:Advance(1.1)
        assert.is_true(env.RutaMisionesCharDB.ignored[100])
        for _, step in ipairs(ns.Route.plan.steps) do
            assert.are_not.equal(100, step.questID)
        end
    end)

    it("sin flecha automática no toca el marcador del jugador", function()
        local world = NewWorld()
        local env = WowEnv.new({ globals = Client(world) })
        env.RutaMisionesDB = { schema = 1, autoWaypoint = false }
        env:LoadToc(TOC)
        env:Login()
        env:Advance(1.1)
        assert.is_nil(world.waypoint)
    end)

    it("la ventana lista para evitar una misión del diario lejana y con poca XP", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        -- Misión nueva (la base no la conoce) con su punto de interés en la otra punta del mapa.
        world.pois = { { questID = 99999, x = 0.02, y = 0.02 } }
        world.log[99999] = {
            title = "Recado lejano",
            complete = false,
            xp = 10,
            objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } },
        }
        world.order[#world.order + 1] = 99999
        env:Fire("QUEST_ACCEPTED", 99999)
        env:Advance(1.1)
        local function Texts()
            local texts = {}
            for _, fs in ipairs(env:Widgets("FontString")) do
                if fs:IsShown() then
                    texts[#texts + 1] = fs:GetText() or ""
                end
            end
            return table.concat(texts, "\n")
        end
        local all = Texts()
        assert.is_truthy(all:find("Avoid (1):", 1, true))
        assert.is_truthy(all:find("Recado lejano: abandon it or leave it for later", 1, true))
        for _, step in ipairs(ns.Route.plan.steps) do
            assert.are_not.equal(99999, step.questID)
        end
        -- Con la opción apagada, la sección desaparece.
        env:SettingsRegistry().settings[env:AddonName() .. "_showAvoid"]:SetValue(false)
        assert.is_falsy(Texts():find("Avoid (", 1, true))
    end)

    -- Botones de línea visibles cuyo texto contiene `fragment`.
    local function LineWith(env, fragment)
        for _, button in ipairs(env:Widgets("Button")) do
            local text = button.text and button.text:GetText()
            if button:IsShown() and text and text:find(fragment, 1, true) then
                return button
            end
        end
    end

    it("clic en un paso: flecha en su punto y mapa abierto en la zona; en combate, sin mapa", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        local step = ns.Route.plan.steps[2]
        local line = LineWith(env, step.name)
        assert.is_not_nil(line)
        world.waypoint = nil
        line:GetScript("OnClick")(line, "LeftButton")
        assert.are.equal(1411, world.openedMap)
        assert.is_true(math.abs(world.waypoint.x * 100 - line.target.x) < 1e-6)
        world.openedMap = nil
        env:SetCombat(true)
        line:GetScript("OnClick")(line, "LeftButton")
        assert.is_nil(world.openedMap)
        assert.is_not_nil(world.waypoint)
    end)

    it("clic en una misión de «Evitar» también pone la flecha allí", function()
        local world = NewWorld()
        local env = Boot(world)
        world.pois = { { questID = 99999, x = 0.02, y = 0.02 } }
        world.log[99999] = {
            title = "Recado lejano",
            complete = false,
            xp = 10,
            objectives = { { type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } },
        }
        world.order[#world.order + 1] = 99999
        env:Fire("QUEST_ACCEPTED", 99999)
        env:Advance(1.1)
        local line = LineWith(env, "Recado lejano")
        assert.is_not_nil(line)
        line:GetScript("OnClick")(line, "LeftButton")
        assert.is_true(math.abs(world.waypoint.x - 0.02) < 1e-6)
        assert.is_nil(env.RutaMisionesCharDB.ignored[99999])
        line:GetScript("OnClick")(line, "RightButton")
        assert.is_true(env.RutaMisionesCharDB.ignored[99999])
    end)

    it("con TomTom instalado pone también su flecha y quita la anterior al cambiar de paso", function()
        local world = NewWorld()
        local calls = { added = {}, removed = {} }
        world.tomtom = {
            AddWaypoint = function(_, map, x, y, opts)
                local uid = { map, x, y, title = opts.title }
                calls.added[#calls.added + 1] = uid
                assert.is_true(opts.crazy)
                return uid
            end,
            RemoveWaypoint = function(_, uid)
                calls.removed[#calls.removed + 1] = uid
            end,
        }
        local env = Boot(world)
        assert.are.equal(1, #calls.added)
        assert.are.equal(1411, calls.added[1][1])
        assert.is_true(math.abs(calls.added[1][2] - 0.42) < 1e-6)
        Accept(env, world, 100, "Matar jabalíes")
        assert.is_true(#calls.added >= 2)
        assert.are.equal(calls.added[1], calls.removed[1])
    end)

    it("con la opción de TomTom apagada no lo toca", function()
        local world = NewWorld()
        local added = 0
        world.tomtom = {
            AddWaypoint = function()
                added = added + 1
            end,
        }
        local env = WowEnv.new({ globals = Client(world) })
        env.RutaMisionesDB = { schema = 1, useTomTom = false }
        env:LoadToc(TOC)
        env:Login()
        env:Advance(1.1)
        assert.are.equal(0, added)
        assert.is_not_nil(world.waypoint)
    end)

    it("en una estancia sin mapa lo dice en vez de fallar", function()
        local world = NewWorld()
        world.map = nil
        local _, ns = Boot(world)
        assert.are.equal("nomap", ns.Route.status)
    end)

    it("con montura usa la velocidad real para estimar tiempos", function()
        local world = NewWorld()
        local globals = Client(world)
        globals.IsMounted = function()
            return world.mounted
        end
        globals.GetUnitSpeed = function()
            return 0, 14, 0, 0
        end
        local _, ns = WowEnv.boot(TOC, { globals = globals })
        assert.are.equal(7, ns.Route.Speed())
        world.mounted = true
        assert.are.equal(14, ns.Route.Speed())
    end)
end)

-- Diálogo de misiones simulado: lo que ofrece el PNJ y lo que el addon pulsa.
local function Dialog(world)
    world.calls = {}
    world.gossip = { active = {}, available = {} }
    world.detail = { questID = 0, auto = false, pvp = false }
    world.reward = { choices = 0, money = 0 }
    local function Call(name)
        return function(...)
            world.calls[#world.calls + 1] = { name, ... }
        end
    end
    return {
        IsShiftKeyDown = function()
            return world.shift or false
        end,
        C_GossipInfo = {
            GetActiveQuests = function()
                return world.gossip.active
            end,
            GetAvailableQuests = function()
                return world.gossip.available
            end,
            SelectActiveQuest = Call("SelectActiveQuest"),
            SelectAvailableQuest = Call("SelectAvailableQuest"),
        },
        GetQuestID = function()
            return world.detail.questID
        end,
        QuestGetAutoAccept = function()
            return world.detail.auto
        end,
        QuestIsFromAreaTrigger = function()
            return false
        end,
        QuestFlagsPVP = function()
            return world.detail.pvp
        end,
        AcceptQuest = Call("AcceptQuest"),
        AcknowledgeAutoAcceptQuest = Call("AcknowledgeAutoAcceptQuest"),
        IsQuestCompletable = function()
            return true
        end,
        CompleteQuest = Call("CompleteQuest"),
        GetNumQuestChoices = function()
            return world.reward.choices
        end,
        GetQuestMoneyToGet = function()
            return world.reward.money
        end,
        GetQuestReward = Call("GetQuestReward"),
    }
end

local function BootDialog(world, savedDB)
    local globals = Client(world)
    for k, v in pairs(Dialog(world)) do
        globals[k] = v
    end
    local env = WowEnv.new({ globals = globals })
    env.RutaMisionesDB = savedDB
    local ns = env:LoadToc(TOC)
    env:Login()
    env:Advance(1.1)
    return env, ns
end

local function Called(world, name)
    for _, call in ipairs(world.calls) do
        if call[1] == name then
            return call
        end
    end
end

describe("aceptar y entregar solo", function()
    it("en el gossip elige la misión de la ruta y la acepta en el detalle", function()
        local world = NewWorld()
        local env = BootDialog(world)
        assert.are.same({}, env:Missing())
        world.gossip.available = { { questID = 100, isTrivial = false, repeatable = false } }
        env:Fire("GOSSIP_SHOW")
        assert.are.equal(100, Called(world, "SelectAvailableQuest")[2])
        world.detail.questID = 100
        env:Fire("QUEST_DETAIL", 0)
        assert.is_not_nil(Called(world, "AcceptQuest"))
    end)

    it("no acepta grises ni repetibles que la ruta no pide, ni las ignoradas", function()
        local world = NewWorld()
        local env, ns = BootDialog(world)
        assert(ns)
        world.gossip.available = {
            { questID = 900, isTrivial = true, repeatable = false },
            { questID = 901, isTrivial = false, repeatable = true },
        }
        env:Fire("GOSSIP_SHOW")
        assert.is_nil(Called(world, "SelectAvailableQuest"))
        ns.charDB.ignored[100] = true
        world.detail.questID = 100
        env:Fire("QUEST_DETAIL", 0)
        assert.is_nil(Called(world, "AcceptQuest"))
    end)

    it("una gris que la ruta propone sí se acepta", function()
        local world = NewWorld()
        local env = BootDialog(world)
        world.gossip.available = { { questID = 100, isTrivial = true, repeatable = false } }
        env:Fire("GOSSIP_SHOW")
        assert.are.equal(100, Called(world, "SelectAvailableQuest")[2])
    end)

    it("con Mayús pulsada no hace nada", function()
        local world = NewWorld()
        local env = BootDialog(world)
        world.shift = true
        world.gossip.available = { { questID = 100, isTrivial = false, repeatable = false } }
        env:Fire("GOSSIP_SHOW")
        world.detail.questID = 100
        env:Fire("QUEST_DETAIL", 0)
        assert.are.equal(0, #world.calls)
    end)

    it("no vuelve a elegir la misma misión en bucle", function()
        local world = NewWorld()
        local env = BootDialog(world)
        world.gossip.available = { { questID = 100, isTrivial = false, repeatable = false } }
        env:Fire("GOSSIP_SHOW")
        env:Fire("GOSSIP_SHOW")
        assert.are.equal(1, #world.calls)
        env:Advance(6)
        env:Fire("GOSSIP_SHOW")
        assert.are.equal(2, #world.calls)
    end)

    it("las de JcJ y las que da un objeto se dejan al jugador; las automáticas se confirman", function()
        local world = NewWorld()
        local env = BootDialog(world)
        world.detail = { questID = 100, auto = false, pvp = true }
        env:Fire("QUEST_DETAIL", 0)
        world.detail.pvp = false
        env:Fire("QUEST_DETAIL", 5555)
        assert.are.equal(0, #world.calls)
        world.detail = { questID = 100, auto = true, pvp = false }
        env:Fire("QUEST_DETAIL", 0)
        assert.is_not_nil(Called(world, "AcknowledgeAutoAcceptQuest"))
        assert.is_nil(Called(world, "AcceptQuest"))
    end)

    it("entrega: completa y cobra con una sola recompensa; con varias o con pago, no", function()
        local world = NewWorld()
        local env = BootDialog(world)
        world.gossip.active = { { questID = 100, isComplete = true } }
        env:Fire("GOSSIP_SHOW")
        assert.are.equal(100, Called(world, "SelectActiveQuest")[2])
        env:Fire("QUEST_PROGRESS")
        assert.is_not_nil(Called(world, "CompleteQuest"))
        world.reward = { choices = 1, money = 0 }
        env:Fire("QUEST_COMPLETE")
        assert.are.equal(1, Called(world, "GetQuestReward")[2])
        world.calls = {}
        world.reward = { choices = 3, money = 0 }
        env:Fire("QUEST_COMPLETE")
        world.reward = { choices = 0, money = 500 }
        env:Fire("QUEST_COMPLETE")
        assert.is_nil(Called(world, "GetQuestReward"))
    end)

    it("con las opciones apagadas no toca el diálogo", function()
        local world = NewWorld()
        local env = BootDialog(world, { schema = 1, autoAccept = false, autoTurnIn = false })
        world.gossip.available = { { questID = 100, isTrivial = false, repeatable = false } }
        world.gossip.active = { { questID = 101, isComplete = true } }
        env:Fire("GOSSIP_SHOW")
        env:Fire("QUEST_PROGRESS")
        env:Fire("QUEST_COMPLETE")
        assert.are.equal(0, #world.calls)
    end)
end)

local function PlannedIDs(ns)
    local ids = {}
    for _, step in ipairs(ns.Route.plan.steps) do
        ids[step.questID] = ids[step.questID] or step.kind
    end
    return ids
end

describe("misiones aprendidas", function()
    it("aprende una misión que QuestieDB no tiene y la propone a otro personaje de la cuenta", function()
        local world = NewWorld()
        local env, ns = Boot(world)
        -- Personaje 1: acepta la 900 (nueva de Forever) en 42,66, la termina en 43,66 y la entrega en 42,67.
        world.x, world.y = 42, 66
        world.log[900] = { title = "Nueva de Forever", complete = false, xp = 0, objectives = {} }
        world.order[#world.order + 1] = 900
        env:Fire("QUEST_ACCEPTED", 900)
        env:Advance(1.1)
        local entry = env.RutaMisionesDB.learned[900]
        assert.are.equal(1411, entry.map)
        assert.are.equal(66, math.floor(entry.pickup.y + 0.5))
        assert.are.equal("Horde", entry.faction)
        assert.is_true(entry.classes[9])
        world.x, world.y = 43, 66
        world.log[900].complete = true
        env:Fire("QUEST_LOG_UPDATE")
        env:Advance(1.1)
        assert.are.equal(43, math.floor(entry.done.x + 0.5))
        world.x, world.y = 42, 67
        world.log[900], world.order = nil, {}
        world.completed[900] = true
        env:Fire("QUEST_TURNED_IN", 900, 600, 0)
        env:Advance(1.1)
        assert.are.equal(600, entry.xp)
        assert.is_nil(PlannedIDs(ns)[900]) -- este personaje ya la hizo
        -- Otro personaje de la misma clase y facción, con las SavedVariables de cuenta: se le propone.
        local world2 = NewWorld()
        local env2 = WowEnv.new({ globals = Client(world2) })
        env2.RutaMisionesDB = env.RutaMisionesDB
        local ns2 = env2:LoadToc(TOC)
        env2:Login()
        env2:Advance(1.1)
        assert.are.equal("pickup", PlannedIDs(ns2)[900])
    end)

    it("las conocidas por QuestieDB no se aprenden", function()
        local world = NewWorld()
        local env = Boot(world)
        world.log[100] = { title = "Matar jabalíes", complete = false, xp = 200, objectives = {} }
        world.order[#world.order + 1] = 100
        env:Fire("QUEST_ACCEPTED", 100)
        env:Advance(1.1)
        assert.is_nil(env.RutaMisionesDB.learned[100])
    end)
end)

describe("Builder.BuildLearnedQuest", function()
    local function LoadBuilder()
        local ns = { Data = {
            AdjustXP = function(xp)
                return xp
            end,
        } }
        assert(loadfile("Builder.lua"))("RutaMisiones", ns)
        return ns.Builder
    end
    local Builder = LoadBuilder()
    local data = {
        MedianXP = function()
            return 111
        end,
    }
    local function Player(extra)
        local player = { level = 10, classID = 9, faction = "Horde", completed = {}, inLog = {}, ignored = {} }
        for k, v in pairs(extra or {}) do
            player[k] = v
        end
        return player
    end
    local function Entry(extra)
        local entry =
            { map = 1411, pickup = { x = 10, y = 10 }, level = 8, faction = "Horde", classes = { [9] = true } }
        for k, v in pairs(extra or {}) do
            entry[k] = v
        end
        return entry
    end

    it("propone con la XP mediana si no hay dato, y con la cobrada si la hay", function()
        assert.are.equal(111, Builder.BuildLearnedQuest(data, 900, Entry(), 1411, Player()).xp)
        local quest = Builder.BuildLearnedQuest(data, 900, Entry({ xp = 300, xpLevel = 10 }), 1411, Player())
        assert.are.equal(300, quest.xp)
        assert.is_true(quest.learned)
    end)

    it("filtra por mapa, nivel, facción y clase (hasta que la acepte otra clase)", function()
        assert.is_nil(Builder.BuildLearnedQuest(data, 900, Entry(), 1412, Player()))
        assert.is_nil(Builder.BuildLearnedQuest(data, 900, Entry({ level = 12 }), 1411, Player()))
        assert.is_nil(Builder.BuildLearnedQuest(data, 900, Entry(), 1411, Player({ faction = "Alliance" })))
        assert.is_nil(Builder.BuildLearnedQuest(data, 900, Entry(), 1411, Player({ classID = 1 })))
        local any = Entry({ anyClass = true })
        assert.is_not_nil(Builder.BuildLearnedQuest(data, 900, any, 1411, Player({ classID = 1 })))
    end)

    it("pone objetivo y entrega solo si están en el mismo mapa", function()
        local entry = Entry({ done = { map = 1411, x = 20, y = 20 }, turnin = { map = 1, x = 5, y = 5 } })
        local quest = Builder.BuildLearnedQuest(data, 900, entry, 1411, Player())
        assert.are.equal(1, #quest.objectives)
        assert.is_nil(quest.turnin)
    end)
end)
