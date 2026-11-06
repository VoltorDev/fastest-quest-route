-- Comando /ruta (alias /rutamisiones, Slash.lua): mostrar, ignorar, config, debug, reset y ayuda.
local WowEnv = require("wow_env")

local TOC = "RutaMisiones.toc"

local function contains(text, fragment)
    assert(text:find(fragment, 1, true), "no aparece «" .. fragment .. "» en:\n" .. text)
end

describe("/rutamisiones", function()
    local env, ns

    before_each(function()
        env, ns = WowEnv.boot(TOC)
        env:ClearPrinted()
    end)

    it("'config' y 'opciones' abren el panel del addon", function()
        env:RunSlash("/ruta config")
        env:RunSlash("/rutamisiones opciones")
        local id = ns.settingsCategory:GetID()
        assert.are.same({ id, id }, env:SettingsRegistry().opened)
    end)

    it("sin argumentos muestra u oculta la ventana y lo recuerda", function()
        assert.is_true(env.RutaMisionesDB.shown)
        env:RunSlash("/ruta")
        assert.is_false(env.RutaMisionesDB.shown)
        env:RunSlash("/ruta mostrar")
        assert.is_true(env.RutaMisionesDB.shown)
    end)

    it("'ignorar ID' guarda la misión por personaje y 'restaurar' la devuelve", function()
        env:RunSlash("/ruta ignorar 4641")
        assert.is_true(env.RutaMisionesCharDB.ignored[4641])
        env:RunSlash("/ruta restaurar")
        assert.is_nil(next(env.RutaMisionesCharDB.ignored))
        contains(env:Printed(), ns.L.UNIGNORED)
    end)

    it("'debug' informa de que falta QuestieDB", function()
        env:RunSlash("/ruta debug")
        contains(env:Printed(), "QuestieDB: no")
        contains(env:Printed(), "estado=nodb")
    end)

    it("en combate no abre el panel y lo explica", function()
        env:SetCombat(true)
        env:RunSlash("/rutamisiones config")
        assert.are.same({}, env:SettingsRegistry().opened)
        contains(env:Printed(), ns.L.ERR_COMBAT)
    end)

    it("'debug' imprime el diagnóstico de soporte, sin avisos en Forever", function()
        env:RunSlash("/rutamisiones debug")
        local out = env:Printed()
        contains(out, ns.L.DEBUG_HEADER)
        contains(out, env:AddonName() .. " " .. ns.version .. " | enUS")
        contains(out, "Forever | 1.60.1.70291 Interface 16001 | WOW_PROJECT_ID=18")
        contains(out, "GameMode=Standard")
        contains(out, "HasSecretRestrictions=true")
        contains(out, "Restricciones activas: ninguna")
        contains(out, "InCombatLockdown=false")
        assert.is_nil(out:find("AVISO", 1, true))
    end)

    it("'debug' lista las restricciones activas", function()
        env:SetRestriction(env.Enum.AddOnRestrictionType.Encounter, env.Enum.AddOnRestrictionState.Active)
        env:RunSlash("/rutamisiones debug")
        contains(env:Printed(), "Restricciones activas: Encounter")
    end)

    it("'reset' sin confirmar no toca nada y explica cómo confirmar", function()
        env.RutaMisionesDB.scale = 2
        env:RunSlash("/rutamisiones reset")
        assert.are.equal(2, env.RutaMisionesDB.scale)
        contains(env:Printed(), ns.L.RESET_CONFIRM)
    end)

    it("'reset confirm' y 'reset confirmar' restauran los valores por defecto y los aplican", function()
        for _, word in ipairs({ "confirm", "confirmar" }) do
            env.RutaMisionesDB.scale = 2
            env.RutaMisionesDB.frame.x = 99
            env:RunSlash("/rutamisiones reset " .. word)
            assert.are.same(ns.DEFAULTS, env.RutaMisionesDB)
            contains(env:Printed(), ns.L.RESET_DONE)
        end
        -- La misma tabla: los ajustes de Settings siguen enlazados a ella.
        assert.are.equal(env.RutaMisionesDB, ns.db)
    end)

    it("'zonas' lista las zonas con el tiempo de viaje cuando se conoce", function()
        ns.Route.ZoneName = function(map)
            return "Zona " .. map
        end
        ns.Route.zones = {
            { map = 1, count = 5, xp = 2000, travel = 250, flew = true },
            { map = 2, count = 4, xp = 1500, travel = 20, flew = false },
            { map = 3, count = 3, xp = 900 },
        }
        env:RunSlash("/ruta zonas")
        local out = env:Printed()
        contains(out, "Zona 1: 5 quests, ~2000 XP" .. ns.L.ZONES_FLIGHT:format(4))
        contains(out, "Zona 2: 4 quests, ~1500 XP" .. ns.L.ZONES_WALK:format(1))
        contains(out, "Zona 3: 3 quests, ~900 XP")
        assert.is_nil(out:find("~900 XP,", 1, true)) -- sin tiempo de viaje conocido, sin coletilla
    end)

    it("un subcomando desconocido muestra la ayuda", function()
        env:RunSlash("/rutamisiones foo")
        contains(env:Printed(), ns.L.SLASH_HELP)
    end)

    it("no distingue mayúsculas en el comando ni en el subcomando", function()
        env:RunSlash("/RUTAMISIONES DEBUG")
        contains(env:Printed(), ns.L.DEBUG_HEADER)
    end)

    it("en un cliente en español responde en español", function()
        local envES, nsES = WowEnv.boot(TOC, { locale = "esES" })
        envES:RunSlash("/rutamisiones reset")
        contains(envES:Printed(), nsES.L.RESET_CONFIRM)
        contains(nsES.L.RESET_CONFIRM, "/ruta reset confirmar")
    end)
end)
