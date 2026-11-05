-- Aceptar y entregar misiones sin clics: lo que hacen las guías de pago, pero solo con lo que la
-- ruta quiere. Mantener Mayús al hablar con el PNJ lo desactiva para esa conversación.
--
-- Se acepta una misión si no es gris ni repetible, no está ignorada y la ruta no la tiene en
-- «Evitar». Las que la ruta propone se aceptan aunque sean grises. Se entrega toda misión
-- completable, salvo que haya que elegir recompensa o pagar: eso lo decide el jugador.
--
-- Las funciones del diálogo (AcceptQuest, CompleteQuest, GetQuestReward…) no llevan marca de
-- restricción en Forever y son las mismas que usa el botón de Blizzard (QuestFrame.lua). Es una
-- comodidad sobre un diálogo que el jugador ha abierto, no juega por él (EULA 1.C).
local _, ns = ...
local L = ns.L
local module = ns:NewModule("AutoQuest")
ns.AutoQuest = module

local RESELECT_GUARD = 5 -- s sin volver a elegir la misma misión en un saludo (evita bucles)

module.recent = {}

local function Now()
    return GetTime()
end

-- Conjuntos de la ruta actual: misiones que propone y misiones que desaconseja.
function module:RouteSets()
    local planned, avoided = {}, {}
    local route = ns.Route
    local plan = route and route.status == "ready" and route.plan
    if plan then
        for _, step in ipairs(plan.steps or {}) do
            planned[step.questID] = true
        end
        for _, entry in ipairs(ns.Planner.AvoidList(plan) or {}) do
            avoided[entry.questID] = true
        end
    end
    return planned, avoided
end

-- ¿Conviene aceptar `questID`? isTrivial e isRepeatable pueden venir a nil (diálogo de detalle).
function module:Wanted(questID, isTrivial, isRepeatable)
    if not questID or questID <= 0 then
        return not isTrivial and not isRepeatable
    end
    if ns.charDB.ignored[questID] then
        return false
    end
    local planned, avoided = self:RouteSets()
    if avoided[questID] then
        return false
    end
    if planned[questID] then
        return true
    end
    return not isTrivial and not isRepeatable
end

function module:Paused()
    return not ns.db.enabled or IsShiftKeyDown()
end

-- Marca una misión como elegida hace poco; devuelve false si ya se eligió dentro de la ventana.
function module:Claim(questID)
    local last = self.recent[questID]
    local now = Now()
    if last and now - last < RESELECT_GUARD then
        return false
    end
    self.recent[questID] = now
    return true
end

function module:OnGossipShow()
    if ns.db.autoTurnIn then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and q.questID and self:Claim(q.questID) then
                C_GossipInfo.SelectActiveQuest(q.questID) -- aquí es el questID, no el índice
                return
            end
        end
    end
    if ns.db.autoAccept then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if self:Wanted(q.questID, q.isTrivial, q.repeatable) and self:Claim(q.questID) then
                C_GossipInfo.SelectAvailableQuest(q.questID)
                return
            end
        end
    end
end

function module:OnQuestGreeting()
    if ns.db.autoTurnIn then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            local questID = GetActiveQuestID and GetActiveQuestID(i) or -i
            if isComplete and self:Claim(questID) then
                ---@diagnostic disable-next-line: redundant-parameter
                SelectActiveQuest(i) -- en el saludo sí es el índice (las anotaciones de retail no lo dicen)
                return
            end
        end
    end
    if ns.db.autoAccept then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial, _, isRepeatable, _, questID = GetAvailableQuestInfo(i)
            if self:Wanted(questID, isTrivial, isRepeatable) and self:Claim(questID or (-100 - i)) then
                ---@diagnostic disable-next-line: redundant-parameter
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

function module:OnQuestDetail(questStartItemID)
    if not ns.db.autoAccept then
        return
    end
    if questStartItemID and questStartItemID ~= 0 then
        return -- la ofrece un objeto: Blizzard la convierte en aviso
    end
    if QuestGetAutoAccept() then
        if not QuestIsFromAreaTrigger() then
            AcknowledgeAutoAcceptQuest() -- el servidor ya la aceptó
        end
        return
    end
    if QuestFlagsPVP() then
        return -- las de JcJ piden confirmación al jugador
    end
    if self:Wanted(GetQuestID()) then
        AcceptQuest()
    end
end

function module:OnQuestProgress()
    if ns.db.autoTurnIn and IsQuestCompletable() then
        CompleteQuest()
    end
end

function module:OnQuestComplete()
    if not ns.db.autoTurnIn then
        return
    end
    local numChoices = GetNumQuestChoices() or 0
    if (GetQuestMoneyToGet() or 0) > 0 then
        return
    end
    if numChoices > 1 then
        ns:Print(L.AUTO_CHOOSE)
        return
    end
    GetQuestReward(numChoices) -- 0 sin elección, 1 con una sola
end

local HANDLERS = {
    GOSSIP_SHOW = "OnGossipShow",
    QUEST_GREETING = "OnQuestGreeting",
    QUEST_DETAIL = "OnQuestDetail",
    QUEST_PROGRESS = "OnQuestProgress",
    QUEST_COMPLETE = "OnQuestComplete",
}

function module:OnEnable()
    for event, method in pairs(HANDLERS) do
        ns:RegisterEvent(event, function(_, _, ...)
            if not module:Paused() then
                module[method](module, ...)
            end
        end)
    end
end
