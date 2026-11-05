local addonName, ns = ...
local L = ns.L
local module = ns:NewModule("Config")

-- Panel en Opciones > AddOns con la API nativa Settings (Blizzard_Settings_Shared).
-- Se registra en OnInitialize porque Settings.RegisterAddOnSetting escribe el valor por defecto
-- en la tabla si la clave es nil: hay que hacerlo DESPUÉS de cargar las SavedVariables.
function module:OnInitialize()
    local db = ns.db
    local category = Settings.RegisterVerticalLayoutCategory(L.ADDON_TITLE)

    local function OnSettingChanged()
        ns:ApplySettings()
    end

    local function Checkbox(key, label, tooltip)
        local setting = Settings.RegisterAddOnSetting(
            category,
            addonName .. "_" .. key,
            key,
            db,
            Settings.VarType.Boolean,
            label,
            ns.DEFAULTS[key]
        )
        setting:SetValueChangedCallback(OnSettingChanged)
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    local function Slider(key, label, tooltip, minValue, maxValue, step, fmt)
        local setting = Settings.RegisterAddOnSetting(
            category,
            addonName .. "_" .. key,
            key,
            db,
            Settings.VarType.Number,
            label,
            ns.DEFAULTS[key]
        )
        setting:SetValueChangedCallback(OnSettingChanged)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return fmt:format(value)
        end)
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    Checkbox("enabled", L.OPT_ENABLED, L.OPT_ENABLED_TT)
    Checkbox("autoWaypoint", L.OPT_WAYPOINT, L.OPT_WAYPOINT_TT)
    Checkbox("openMapOnClick", L.OPT_OPENMAP, L.OPT_OPENMAP_TT)
    Checkbox("useTomTom", L.OPT_TOMTOM, L.OPT_TOMTOM_TT)
    Checkbox("useQuestie", L.OPT_QUESTIE, L.OPT_QUESTIE_TT)
    Checkbox("showAvoid", L.OPT_AVOID, L.OPT_AVOID_TT)
    Checkbox("autoAccept", L.OPT_AUTOACCEPT, L.OPT_AUTOACCEPT_TT)
    Checkbox("autoTurnIn", L.OPT_AUTOTURNIN, L.OPT_AUTOTURNIN_TT)
    Checkbox("useLearned", L.OPT_LEARNED, L.OPT_LEARNED_TT)
    Slider("maxSteps", L.OPT_STEPS, L.OPT_STEPS_TT, 3, 25, 1, "%d")
    Slider("maxAbove", L.OPT_ABOVE, L.OPT_ABOVE_TT, 0, 5, 1, "+%d")
    Slider("scale", L.OPT_SCALE, L.OPT_SCALE_TT, 0.5, 2, 0.05, "%.2f")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

-- Abrir el panel está restringido en combate (C_SettingsUtil.OpenSettingsPanel lleva HasRestrictions).
function ns:OpenSettings()
    if InCombatLockdown() then
        self:Print(L.ERR_COMBAT)
        return
    end
    Settings.OpenToCategory(self.settingsCategory:GetID())
end

-- Compartimento de addons (botón del minimapa). Los nombres coinciden con el TOC.
-- El cliente llama a la función de clic con (addonName, buttonName) y a las de ratón
-- con (addonName, menuButtonFrame).
function RutaMisiones_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        ns:OpenSettings()
    else
        ns:ToggleFrame()
    end
end

function RutaMisiones_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText(L.ADDON_TITLE)
    GameTooltip:AddLine(L.COMPARTMENT_TOOLTIP, 1, 1, 1)
    GameTooltip:Show()
end

function RutaMisiones_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
