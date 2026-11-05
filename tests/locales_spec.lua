-- Traducciones: cada idioma solo define claves que existen en enUS y conserva sus placeholders
-- de string.format, para que una traducción no rompa un format en el juego.
local WowEnv = require("wow_env")

-- Placeholders en orden ("%s,%d").
local function placeholders(s)
    local list = {}
    for spec in s:gmatch("%%[%-%d%.]*[sdfgxXc]") do
        list[#list + 1] = spec
    end
    return table.concat(list, ",")
end

-- Carga enUS y después el fichero del idioma, como el TOC; devuelve la tabla inglesa y la final.
local function loadLocale(file, locale)
    local env = WowEnv.new({ locale = locale })
    local ns = {}
    env:LoadFile("Locales/enUS.lua", "RutaMisiones", ns)
    local english = {}
    for k, v in pairs(ns.L) do
        english[k] = v
    end
    env:LoadFile(file, "RutaMisiones", ns)
    return english, ns.L, env
end

describe("traducciones", function()
    for _, case in ipairs({ { "Locales/esES.lua", "esES" }, { "Locales/esES.lua", "esMX" } }) do
        it(case[2] .. ": solo claves de enUS, con los mismos placeholders", function()
            local english, translated, env = loadLocale(case[1], case[2])
            for key, text in pairs(translated) do
                assert(english[key] ~= nil, "clave sin texto en enUS: " .. key)
                assert.are.equal(placeholders(english[key]), placeholders(text), "placeholders en " .. key)
            end
            assert.are_not.equal(english.LOADED, translated.LOADED) -- de verdad se tradujo
            assert.are.same({}, env:Missing())
        end)
    end

    it("en inglés el fichero español no cambia nada", function()
        local english, final = loadLocale("Locales/esES.lua", "enUS")
        assert.are.same(english, final)
    end)

    it("una clave sin traducir devuelve la propia clave en vez de nil", function()
        local _, L = loadLocale("Locales/esES.lua", "esES")
        assert.are.equal("CLAVE_QUE_NO_EXISTE", L.CLAVE_QUE_NO_EXISTE)
    end)
end)
