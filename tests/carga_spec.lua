-- Carga del addon en el cliente simulado de Forever: todos los ficheros del TOC, sin globales
-- que falten y sin globales inesperadas. También comprueba en qué clientes carga el TOC.
local WowEnv = require("wow_env")

local TOC = "RutaMisiones.toc"

local function contains(text, fragment)
    assert(text:find(fragment, 1, true), "no aparece «" .. fragment .. "» en:\n" .. text)
end

describe("carga en el cliente simulado de Forever", function()
    local env, ns

    before_each(function()
        env, ns = WowEnv.boot(TOC)
    end)

    it("carga todos los ficheros del TOC, en orden", function()
        -- LoadedFiles incluye además los .lua que traen los <Script file> de cada .xml.
        local toc, loaded, i = env:TocFiles(), env:LoadedFiles(), 0
        assert.is_true(#toc > 0)
        for _, file in ipairs(toc) do
            repeat
                i = i + 1
            until loaded[i] == file or loaded[i] == nil
            assert(loaded[i] == file, "no se cargó (o no en el orden del TOC): " .. file)
        end
    end)

    it("no lee ninguna global que el cliente simulado no tenga", function()
        assert.are.same({}, env:Missing())
    end)

    it("solo crea las globales que declara: SavedVariables, /comando y funciones del TOC", function()
        local allowed = {}
        for _, field in ipairs({
            "SavedVariables",
            "SavedVariablesPerCharacter",
            "AddonCompartmentFunc",
            "AddonCompartmentFuncOnEnter",
            "AddonCompartmentFuncOnLeave",
        }) do
            for name in (env:TocMeta(field) or ""):gmatch("[%w_]+") do
                allowed[name] = true
            end
        end
        for _, name in ipairs(env:CreatedGlobals()) do
            local isSlash = name:match("^SLASH_[%u%d_]+%d$") ~= nil
            assert(allowed[name] == true or isSlash, "global inesperada: " .. name)
        end
    end)

    it("las funciones del compartimento que nombra el TOC existen", function()
        local fields = { "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }
        for _, field in ipairs(fields) do
            local name = env:TocMeta(field)
            assert(name ~= nil, "falta ## " .. field .. " en el TOC")
            assert.are.equal("function", type(env[name]), field .. " -> " .. name)
        end
    end)

    it("clic en el compartimento: izquierdo muestra/oculta la ruta, derecho abre las opciones", function()
        local click = env[env:TocMeta("AddonCompartmentFunc")]
        click(env:AddonName(), "LeftButton")
        assert.is_false(env.RutaMisionesDB.shown)
        assert.are.same({}, env:SettingsRegistry().opened)
        click(env:AddonName(), "RightButton")
        assert.are.same({ ns.settingsCategory:GetID() }, env:SettingsRegistry().opened)
    end)

    it("el tooltip del compartimento se muestra con el título y se oculta al salir", function()
        env[env:TocMeta("AddonCompartmentFuncOnEnter")](env:AddonName(), env.UIParent)
        assert.is_true(env.GameTooltip:IsShown())
        assert.are.equal(ns.L.ADDON_TITLE, env.GameTooltip:GetText())
        env[env:TocMeta("AddonCompartmentFuncOnLeave")](env:AddonName(), env.UIParent)
        assert.is_false(env.GameTooltip:IsShown())
    end)

    it("anuncia la carga en el chat con la versión", function()
        contains(env:Printed(), ns.L.LOADED)
        contains(env:Printed(), ns.version)
    end)
end)

describe("en qué clientes carga el TOC", function()
    it("no carga en retail (AllowLoadGameType no incluye standard)", function()
        local env = WowEnv.new({ client = "retail" })
        local ns, reason = env:LoadToc(TOC)
        assert.is_nil(ns)
        contains(reason, "LoadGameType")
        assert.are.same({}, env:LoadedFiles())
    end)

    it("no carga en Classic Era", function()
        local env = WowEnv.new({ client = "classic_era" })
        local ns, reason = env:LoadToc(TOC)
        assert.is_nil(ns)
        contains(reason, "LoadGameType")
    end)

    it("carga en un Forever renombrado (AllowLoadGameType incluye forever)", function()
        local env, ns = WowEnv.boot(TOC, { client = "forever_renamed" })
        assert.is_true(ns.isForever)
        assert.are.same({}, env:Missing())
    end)

    it("un Interface distinto del del cliente sale como desactualizado", function()
        local env = WowEnv.new({ build = { "1.60.2", "71000", "Nov 1 2026", 16002 } })
        local ns, reason = env:LoadToc(TOC)
        assert.is_nil(ns)
        contains(reason, "desactualizado")
    end)
end)
