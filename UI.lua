-- Ventana de la ruta, con dos estilos a elegir en Ajustes (db.style):
--   "tracker": seguidor sin marco, como el seguimiento de misiones de Blizzard; agrupa los pasos por misión.
--   "card":    tarjeta con el siguiente paso en grande y los demás debajo, en pequeño.
-- Los avisos (misiones fuera del mapa, demasiado altas, siguiente zona) van en una sola línea con
-- tooltip. Debajo, las misiones que conviene evitar. Se mueve arrastrando el título; clic en un paso
-- pone la flecha allí; clic derecho en un paso o en una misión a evitar la ignora.
local _, ns = ...
local L = ns.L
local module = ns:NewModule("UI")

local WIDTH = { tracker = 250, card = 270 }
local MAX_AVOID = 5
local PAD = 10
local WARN_ICON = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:12:12|t"

local KIND_MARK = {
    pickup = "|cffffd100!|r",
    objective = "|cff66bbff•|r",
    turnin = "|cffffd100?|r",
}

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return ("%dh %02dmin"):format(seconds / 3600, (seconds % 3600) / 60)
    end
    return ("%d min"):format(math.max(1, math.floor(seconds / 60 + 0.5)))
end
ns.FormatTime = FormatTime

-- «1 misión» / «3 misiones»: cada texto con número tiene su forma en singular (sufijo _ONE).
local function Count(key, n, ...)
    local text = (n == 1 and L[key .. "_ONE"]) or L[key]
    return text:format(n, ...)
end
ns.Count = Count

-- Qué hay que hacer en un paso, sin el nombre de la misión: «Recoger», «Matar», «Entregar»...
local function StepVerb(step)
    if step.kind == "objective" then
        return (step.label and L["DO_" .. step.label:upper()]) or L.STEP_OBJECTIVE
    end
    return L["STEP_" .. step.kind:upper()] or step.kind
end
ns.StepVerb = StepVerb

local function QuestName(step)
    return step.name or ("#" .. step.questID)
end

-- Paso completo en una línea (chat y tooltips): «! Recoger: Nombre».
local function StepText(step)
    return ("%s %s: %s"):format(KIND_MARK[step.kind] or "", StepVerb(step), QuestName(step))
end
ns.StepText = StepText

-- Pasos seguidos de la misma misión, juntos: Zalazane (matar) + Zalazane (conseguir) = un grupo.
local function Groups(steps, first, last)
    local groups = {}
    for i = first, last do
        local step = steps[i]
        local group = groups[#groups]
        if not group or group.questID ~= step.questID then
            group = { questID = step.questID, name = QuestName(step), chained = step.chained, steps = {} }
            groups[#groups + 1] = group
        end
        group.steps[#group.steps + 1] = step
    end
    return groups
end
ns.GroupSteps = Groups

-- Avisos de la ruta: van juntos en una línea y se leen en su tooltip.
local function Warnings(route)
    local list = {}
    if route.status ~= "ready" or not route.plan then
        return list
    end
    if #route.offMap > 0 then
        list[#list + 1] = Count("OFFMAP", #route.offMap)
    end
    if route.tooHigh and #route.tooHigh > 0 then
        list[#list + 1] = Count("TOO_HIGH", #route.tooHigh)
    end
    local zone = route.zones and route.zones[1]
    if zone and #route.plan.steps <= 3 then
        list[#list + 1] = Count("NEXT_ZONE_HINT", zone.count, route.ZoneName(zone.map))
    end
    return list
end
ns.RouteWarnings = Warnings

local function AvoidText(entry)
    local format = entry.inLog and L.AVOID_LOG or L.AVOID_NEAR
    return "|cffff5555x|r " .. format:format(entry.name or ("#" .. entry.questID), AbbreviateNumbers(entry.xpPerHour))
end
ns.AvoidText = AvoidText

-- Construcción ------------------------------------------------------------------------------------------------

function module:OnEnable()
    local db = ns.db
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH.tracker, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(moved)
        moved:StopMovingOrSizing()
        local point, _, relativePoint, x, y = moved:GetPoint()
        db.frame.point, db.frame.relativePoint, db.frame.x, db.frame.y = point, relativePoint, x, y
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        db.shown = false
        module:Refresh()
    end)

    local refresh = CreateFrame("Button", nil, frame)
    refresh:SetSize(14, 14)
    refresh:SetPoint("RIGHT", close, "LEFT", -1, 0)
    refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    refresh:SetHighlightTexture("Interface\\Buttons\\UI-RefreshButton", "ADD")
    refresh:SetScript("OnClick", function()
        ns.Route:RequestUpdate()
    end)
    refresh:SetScript("OnEnter", function(hovered)
        GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.BUTTON_REFRESH)
        GameTooltip:Show()
    end)
    refresh:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Cabecera: título a la izquierda y PX/h a la derecha (seguidor), o «Paso 1 de 26» (tarjeta).
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetJustifyH("LEFT")
    local rate = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rate:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
    rate:SetJustifyH("RIGHT")
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.35)
    rule:SetHeight(1)
    -- Marca grande del paso actual en la tarjeta (! ? •).
    local bigMark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    bigMark:SetWidth(22)

    self.frame, self.close, self.refresh = frame, close, refresh
    self.title, self.rate, self.rule, self.bigMark = title, rate, rule, bigMark
    self.lines = {}
    self:Refresh()
end

local function IgnoreFromLine(entry)
    ns.Route:Ignore(entry.questID)
    ns:Print(L.IGNORED:format(entry.name or entry.questID))
end

-- Tooltip de cada tipo de línea.
local TOOLTIP = {
    step = function(line)
        local step = line.target
        GameTooltip:SetText(QuestName(step))
        GameTooltip:AddLine(StepText(step), 1, 1, 1)
        if step.chained then
            GameTooltip:AddLine(L.TT_CHAIN, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(L.TT_ARRIVE:format(FormatTime(step.arrive)), 1, 1, 1)
        GameTooltip:AddLine(L.TT_CLICK, 0.7, 0.7, 0.7)
    end,
    avoid = function(line)
        local entry, plan = line.target, ns.Route.plan
        GameTooltip:SetText(entry.name or "")
        GameTooltip:AddLine(entry.inLog and L.TT_AVOID_LOG or L.TT_AVOID_NEAR, 1, 1, 1, true)
        GameTooltip:AddLine(
            L.TT_AVOID_RATE:format(AbbreviateNumbers(entry.xpPerHour), AbbreviateNumbers(plan and plan.xpPerHour or 0)),
            1,
            0.82,
            0
        )
        GameTooltip:AddLine(L.TT_AVOID_CLICK, 0.7, 0.7, 0.7)
    end,
    warn = function(line)
        GameTooltip:SetText(L.WARN_TITLE)
        for _, text in ipairs(line.target) do
            GameTooltip:AddLine(text, 1, 1, 1, true)
        end
    end,
}

function module:GetLine(index)
    local line = self.lines[index]
    if line then
        return line
    end
    line = CreateFrame("Button", nil, self.frame)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    line.text = text
    line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    line:SetScript("OnClick", function(clicked, button)
        local target = clicked.target
        if not target or (clicked.kind ~= "step" and clicked.kind ~= "avoid") then
            return
        end
        if button == "RightButton" then
            IgnoreFromLine(target)
        else
            ns.Route:GoTo(target)
        end
    end)
    line:SetScript("OnEnter", function(hovered)
        local show = hovered.target and TOOLTIP[hovered.kind]
        if not show then
            return
        end
        GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
        show(hovered)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.lines[index] = line
    return line
end

-- Coloca la siguiente línea libre a `x` del borde y `self.y` de arriba, y baja el cursor.
-- kind: "step" y "avoid" (clic y tooltip), "warn" (solo tooltip) o nil (texto sin más).
function module:Put(x, height, font, text, kind, target)
    self.used = self.used + 1
    local line = self:GetLine(self.used)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
    line:SetPoint("RIGHT", self.frame, "RIGHT", -PAD, 0)
    line:SetHeight(height)
    line.text:SetFontObject(font)
    line.text:SetWordWrap(false)
    line.text:SetText(text)
    line.kind, line.target = kind, target
    line:EnableMouse(kind ~= nil)
    line:Show()
    self.y = self.y + height
    return line
end

-- Estilos -----------------------------------------------------------------------------------------------------

-- Pasos agrupados por misión: título de la misión y, debajo, lo que hay que hacer en ella.
function module:PutGroups(groups)
    for g, group in ipairs(groups) do
        local name = group.name .. (group.chained and (" |cff999999" .. L.CHAIN_MARK .. "|r") or "")
        local current = g == 1
        self:Put(
            PAD,
            15,
            current and "GameFontHighlight" or "GameFontNormal",
            (current and "|cff00ff00>|r " or "") .. name,
            "step",
            group.steps[1]
        )
        for _, step in ipairs(group.steps) do
            local text = (KIND_MARK[step.kind] or "-") .. " " .. StepVerb(step)
            self:Put(PAD + 12, 13, "GameFontHighlightSmall", text, "step", step)
        end
        self.y = self.y + 4
    end
end

function module:LayoutTracker(route, steps, shown)
    local title, rate, rule = self.title, self.rate, self.rule
    self.frame:ClearBackdrop()
    self.bigMark:Hide()
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetPoint("RIGHT", rate, "LEFT", -4, 0)
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", 0, -20)
    rule:SetPoint("TOPRIGHT", 0, -20)
    rule:Show()
    local plan = route.status == "ready" and route.plan
    if plan then
        title:SetText(L.TRACKER_TITLE:format(FormatTime(plan.seconds)))
        rate:SetText(L.RATE:format(AbbreviateNumbers(plan.xpPerHour)))
    else
        title:SetText(L.ADDON_TITLE)
        rate:SetText("")
    end
    self.y = 25
    self:PutGroups(Groups(steps, 1, shown))
end

function module:LayoutCard(route, steps, shown)
    local title, rate, frame, mark = self.title, self.rate, self.frame, self.bigMark
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.25, 1)
    self.rule:Hide()
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetPoint("RIGHT", rate, "LEFT", -4, 0)
    rate:SetText("")
    self.y = 24
    local current = shown > 0 and steps[1]
    if not current then
        title:SetText(L.ADDON_TITLE)
        mark:Hide()
        return
    end
    title:SetText(L.CARD_STEP:format(1, #steps))
    -- Paso actual: marca grande, nombre de la misión y qué hacer en ella.
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", PAD, -self.y - 2)
    mark:SetText(KIND_MARK[current.kind] or "")
    mark:Show()
    self:Put(PAD + 26, 18, "GameFontNormalLarge", QuestName(current), "step", current)
    local how = StepVerb(current) .. " |cff999999· " .. L.CARD_ARRIVE:format(FormatTime(current.arrive)) .. "|r"
    self:Put(PAD + 26, 14, "GameFontHighlight", how, "step", current)
    self.y = self.y + 6
    if shown > 1 then
        self:Put(PAD, 13, "GameFontDisableSmall", L.CARD_NEXT)
        for _, group in ipairs(Groups(steps, 2, shown)) do
            local verbs = {}
            for _, step in ipairs(group.steps) do
                verbs[#verbs + 1] = StepVerb(step):lower()
            end
            local text = group.name .. " |cff999999(" .. table.concat(verbs, ", ") .. ")|r"
            self:Put(PAD, 13, "GameFontHighlightSmall", text, "step", group.steps[1])
        end
        self.y = self.y + 4
    end
    local plan = route.plan
    local summary = L.SUMMARY_SHORT:format(#steps, FormatTime(plan.seconds), AbbreviateNumbers(plan.xpPerHour))
    self:Put(PAD, 13, "GameFontDisableSmall", summary)
end

function module:Refresh()
    local frame, db = self.frame, ns.db
    if not frame then
        return
    end
    if not db.enabled or not db.shown then
        frame:Hide()
        return
    end
    local style = WIDTH[db.style] and db.style or "tracker"
    frame:SetScale(db.scale)
    frame:ClearAllPoints()
    frame:SetPoint(db.frame.point, UIParent, db.frame.relativePoint, db.frame.x, db.frame.y)
    frame:SetWidth(WIDTH[style])

    local route = ns.Route
    local ready = route.status == "ready" and route.plan
    local steps = ready and route.plan.steps or {}
    local shown = math.min(#steps, db.maxSteps)
    self.used = 0
    if style == "card" then
        self:LayoutCard(route, steps, shown)
    else
        self:LayoutTracker(route, steps, shown)
    end
    local x = style == "card" and PAD or 2

    if not ready then
        self:Put(x, 13, "GameFontDisableSmall", L["STATUS_" .. route.status:upper()] or "")
    elseif #steps == 0 then
        self:Put(x, 26, "GameFontDisableSmall", L.EMPTY).text:SetWordWrap(true)
    elseif style == "tracker" and #steps > shown then
        self:Put(x, 13, "GameFontDisableSmall", Count("MORE_STEPS", #steps - shown))
    end
    local warnings = Warnings(route)
    if #warnings > 0 then
        local text = WARN_ICON .. " |cffff9a3c" .. Count("WARNINGS", #warnings) .. "|r"
        self:Put(x, 14, "GameFontNormalSmall", text, "warn", warnings)
    end

    -- Misiones a evitar, debajo de todo.
    local avoid = (db.showAvoid and ready) and ns.Planner.AvoidList(route.plan, MAX_AVOID) or {}
    self.avoidList = avoid
    if #avoid > 0 then
        self.y = self.y + 4
        self:Put(x, 14, "GameFontNormalSmall", "|cffff6666" .. L.AVOID_HEADER:format(#avoid) .. "|r")
        for _, entry in ipairs(avoid) do
            self:Put(x, 14, "GameFontHighlightSmall", AvoidText(entry), "avoid", entry)
        end
    end

    for i = self.used + 1, #self.lines do
        local line = self.lines[i]
        line.kind, line.target = nil, nil
        line.text:SetText("")
        line:Hide()
    end
    frame:SetHeight(self.y + (style == "card" and 8 or 2))
    frame:Show()
end

function module:ApplySettings()
    self:Refresh()
end

function ns:RefreshUI()
    module:Refresh()
end

function ns:ToggleFrame()
    self.db.shown = not self.db.shown
    module:Refresh()
end
