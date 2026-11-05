-- Ventana con los próximos pasos de la ruta y, debajo, las misiones que conviene evitar. Se mueve
-- arrastrando el título; clic en un paso pone la flecha allí; clic derecho en un paso o en una
-- misión a evitar la ignora.
local _, ns = ...
local L = ns.L
local module = ns:NewModule("UI")

local WIDTH, LINE = 330, 16
local MAX_AVOID = 5

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

local function StepText(step)
    local verb = L["STEP_" .. step.kind:upper()] or step.kind
    local detail = ""
    if step.kind == "objective" and step.label and L["OBJ_" .. step.label:upper()] then
        detail = " (" .. L["OBJ_" .. step.label:upper()] .. ")"
    end
    local chain = step.chained and (" |cff999999" .. L.CHAIN_MARK .. "|r") or ""
    return ("%s %s: %s%s%s |cff999999%.0f, %.0f|r"):format(
        KIND_MARK[step.kind] or "",
        verb,
        step.name or ("#" .. step.questID),
        detail,
        chain,
        step.x,
        step.y
    )
end
ns.StepText = StepText

local function AvoidText(entry)
    local format = entry.inLog and L.AVOID_LOG or L.AVOID_NEAR
    return "|cffff5555x|r " .. format:format(entry.name or ("#" .. entry.questID), AbbreviateNumbers(entry.xpPerHour))
end
ns.AvoidText = AvoidText

function module:OnEnable()
    local db = ns.db
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 80)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(moved)
        moved:StopMovingOrSizing()
        local point, _, relativePoint, x, y = moved:GetPoint()
        db.frame.point, db.frame.relativePoint, db.frame.x, db.frame.y = point, relativePoint, x, y
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L.ADDON_TITLE)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        db.shown = false
        module:Refresh()
    end)

    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(80, 18)
    refresh:SetPoint("TOPRIGHT", -26, -6)
    refresh:SetText(L.BUTTON_REFRESH)
    refresh:SetScript("OnClick", function()
        ns.Route:RequestUpdate()
    end)

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    summary:SetPoint("RIGHT", -10, 0)
    summary:SetJustifyH("LEFT")

    local avoidHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avoidHeader:SetJustifyH("LEFT")
    avoidHeader:SetTextColor(1, 0.4, 0.4)

    self.frame, self.summary, self.lines = frame, summary, {}
    self.avoidHeader, self.avoidLines = avoidHeader, {}
    self:Refresh()
end

local function NewLine(parent)
    local line = CreateFrame("Button", nil, parent)
    line:SetHeight(LINE)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints()
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    line.text = text
    line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    line:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return line
end

local function IgnoreFromLine(entry)
    ns.Route:Ignore(entry.questID)
    ns:Print(L.IGNORED:format(entry.name or entry.questID))
end

function module:GetLine(index)
    local line = self.lines[index]
    if line then
        return line
    end
    line = NewLine(self.frame)
    line:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -4 - (index - 1) * LINE)
    line:SetPoint("RIGHT", self.frame, "RIGHT", -10, 0)
    line:SetScript("OnClick", function(clicked, button)
        if not clicked.step then
            return
        end
        if button == "RightButton" then
            IgnoreFromLine(clicked.step)
        else
            ns.Route:SetWaypoint(clicked.step)
        end
    end)
    line:SetScript("OnEnter", function(hovered)
        if not hovered.step then
            return
        end
        GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
        GameTooltip:SetText(hovered.step.name or "")
        GameTooltip:AddLine(L.TT_ARRIVE:format(FormatTime(hovered.step.arrive)), 1, 1, 1)
        GameTooltip:AddLine(L.TT_CLICK, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    self.lines[index] = line
    return line
end

function module:GetAvoidLine(index)
    local line = self.avoidLines[index]
    if line then
        return line
    end
    line = NewLine(self.frame)
    line:SetPoint("TOPLEFT", self.avoidHeader, "BOTTOMLEFT", 0, -2 - (index - 1) * LINE)
    line:SetPoint("RIGHT", self.frame, "RIGHT", -10, 0)
    line:SetScript("OnClick", function(clicked, button)
        if clicked.entry and button == "RightButton" then
            IgnoreFromLine(clicked.entry)
        end
    end)
    line:SetScript("OnEnter", function(hovered)
        local entry = hovered.entry
        if not entry then
            return
        end
        local plan = ns.Route.plan
        GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.name or "")
        GameTooltip:AddLine(entry.inLog and L.TT_AVOID_LOG or L.TT_AVOID_NEAR, 1, 1, 1, true)
        GameTooltip:AddLine(
            L.TT_AVOID_RATE:format(AbbreviateNumbers(entry.xpPerHour), AbbreviateNumbers(plan and plan.xpPerHour or 0)),
            1,
            0.82,
            0
        )
        GameTooltip:AddLine(L.TT_AVOID_CLICK, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    self.avoidLines[index] = line
    return line
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
    frame:SetScale(db.scale)
    frame:ClearAllPoints()
    frame:SetPoint(db.frame.point, UIParent, db.frame.relativePoint, db.frame.x, db.frame.y)

    local route = ns.Route
    local steps = route.plan and route.plan.steps or {}
    local shown = math.min(#steps, db.maxSteps)
    if route.status == "ready" and route.plan then
        local plan = route.plan
        local text = L.SUMMARY:format(#steps, FormatTime(plan.seconds), AbbreviateNumbers(plan.xpPerHour))
        if #route.offMap > 0 then
            text = text .. "\n" .. L.OFFMAP:format(#route.offMap)
        end
        if #steps == 0 then
            text = text .. "\n" .. L.EMPTY
        end
        self.summary:SetText(text)
    else
        self.summary:SetText(L["STATUS_" .. route.status:upper()] or "")
    end
    for i = 1, math.max(shown, #self.lines) do
        local line = self:GetLine(i)
        local step = i <= shown and steps[i] or nil
        line.step = step
        if step then
            line.text:SetText((i == 1 and "|cff00ff00> |r" or "   ") .. StepText(step))
            line:Show()
        else
            line:Hide()
        end
    end
    -- Misiones a evitar, debajo de los pasos.
    local avoid = (db.showAvoid and route.status == "ready") and ns.Planner.AvoidList(route.plan, MAX_AVOID) or {}
    self.avoidList = avoid
    local header = self.avoidHeader
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -8 - shown * LINE)
    if #avoid > 0 then
        header:SetText(L.AVOID_HEADER:format(#avoid))
        header:Show()
    else
        header:Hide()
    end
    for i = 1, math.max(#avoid, #self.avoidLines) do
        local line = self:GetAvoidLine(i)
        local entry = avoid[i]
        line.entry = entry
        if entry then
            line.text:SetText(AvoidText(entry))
            line:Show()
        else
            line:Hide()
        end
    end
    local avoidHeight = #avoid > 0 and (8 + LINE + #avoid * LINE) or 0
    frame:SetHeight(46 + (self.summary:GetStringHeight() or 12) + shown * LINE + avoidHeight)
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
