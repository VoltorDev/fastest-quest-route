-- Panel de opciones (Config.lua) con la API Settings: se registra DESPUÉS de cargar las
-- SavedVariables, queda enlazado a esa misma tabla y cada cambio se guarda y se aplica.
local WowEnv = require("wow_env")

local TOC = "RutaMisiones.toc"

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local EXPECTED = {
    enabled = "boolean",
    autoWaypoint = "boolean",
    useQuestie = "boolean",
    maxSteps = "number",
    maxAbove = "number",
    scale = "number",
}

describe("opciones en Settings", function()
    it("no registra nada al cargar los ficheros; sí tras el ADDON_LOADED propio", function()
        local env = WowEnv.new()
        env.RutaMisionesDB = { schema = 1, scale = 1.25 }
        local ns = env:LoadToc(TOC) or error("el addon no cargó")
        local registry = env:SettingsRegistry()
        assert.are.equal(0, countKeys(registry.settings))

        env:Fire("ADDON_LOADED", env:AddonName(), false)
        assert.are.equal(countKeys(EXPECTED), countKeys(registry.settings))
        assert.are.equal(1, #registry.addOnCategories)
        assert.are.equal(ns.settingsCategory, registry.addOnCategories[1])
        assert.are.equal(ns.L.ADDON_TITLE, ns.settingsCategory:GetName())

        for key, kind in pairs(EXPECTED) do
            local setting = registry.settings[env:AddonName() .. "_" .. key]
            assert(setting ~= nil, "falta el ajuste " .. key)
            assert.are.equal(env.RutaMisionesDB, setting.variableTbl) -- la tabla ya cargada, no otra
            assert.are.equal(key, setting.variableKey)
            assert.are.equal(kind, setting:GetVariableType())
        end
        assert.are.equal(1.25, registry.settings[env:AddonName() .. "_scale"]:GetValue()) -- no pisa lo guardado
    end)

    it("crea tres casillas y tres deslizadores con sus formatos", function()
        local env = WowEnv.boot(TOC)
        local kinds, sliders = {}, {}
        for _, control in ipairs(env:SettingsRegistry().controls) do
            kinds[#kinds + 1] = control.kind
            if control.kind == "Slider" then
                sliders[#sliders + 1] = control.options
            end
        end
        assert.are.same({ "Checkbox", "Checkbox", "Checkbox", "Slider", "Slider", "Slider" }, kinds)
        local right = env.MinimalSliderWithSteppersMixin.Label.Right
        assert.are.equal("12", sliders[1].formatters[right](12))
        assert.are.equal("+2", sliders[2].formatters[right](2))
        assert.are.equal("1.50", sliders[3].formatters[right](1.5))
    end)

    it("cambiar una opción la guarda y la aplica a la ventana", function()
        local env = WowEnv.boot(TOC)
        local settings = env:SettingsRegistry().settings
        settings[env:AddonName() .. "_maxAbove"]:SetValue(4)
        assert.are.equal(4, env.RutaMisionesDB.maxAbove)
        settings[env:AddonName() .. "_enabled"]:SetValue(false)
        assert.is_false(env.RutaMisionesDB.enabled)
    end)

    it("un valor de otro tipo se rechaza, como en el cliente", function()
        local env = WowEnv.boot(TOC)
        local scale = env:SettingsRegistry().settings[env:AddonName() .. "_scale"]
        assert.has_error(function()
            scale:SetValue("2")
        end)
        assert.are.equal(1, env.RutaMisionesDB.scale)
    end)
end)
