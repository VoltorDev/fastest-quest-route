-- Ciclo de vida (ADDON_LOADED -> PLAYER_LOGIN) y SavedVariables de Core.lua: valores por
-- defecto en el primer inicio, datos existentes en el segundo y migraciones de esquema.
local WowEnv = require("wow_env")

local TOC = "RutaMisiones.toc"

-- Arranca el addon con unas SavedVariables dadas (nil = primer inicio) y opciones del cliente.
local function bootWith(saved, charSaved, opts)
    local env = WowEnv.new(opts)
    env.RutaMisionesDB = saved
    env.RutaMisionesCharDB = charSaved
    local ns = env:LoadToc(TOC) or error("el addon no cargó")
    env:Login()
    return env, ns
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

describe("ciclo ADDON_LOADED -> PLAYER_LOGIN", function()
    it("las SavedVariables se preparan en el ADDON_LOADED propio, no antes ni con el de otro addon", function()
        local env = WowEnv.new()
        local ns = env:LoadToc(TOC) or error("el addon no cargó")
        assert.is_nil(ns.db)
        env:Fire("ADDON_LOADED", "OtroAddon", false)
        assert.is_nil(ns.db)
        env:Fire("ADDON_LOADED", env:AddonName(), false)
        assert.are.equal(env.RutaMisionesDB, ns.db)
        assert.are.equal(env.RutaMisionesCharDB, ns.charDB)
    end)

    it("los módulos se activan en PLAYER_LOGIN, con las SavedVariables ya cargadas", function()
        local env = WowEnv.new()
        local ns = env:LoadToc(TOC) or error("el addon no cargó")
        env:Fire("ADDON_LOADED", env:AddonName(), false)
        assert.are.equal("idle", ns.Route.status)
        env:Fire("PLAYER_LOGIN")
        -- Sin QuestieDB en el cliente simulado, la ruta lo detecta al activarse.
        assert.are.equal("nodb", ns.Route.status)
    end)

    it("PLAYER_LOGIN se atiende una sola vez (el manejador se desregistra)", function()
        local env = WowEnv.boot(TOC)
        local frames = #env:Widgets("Frame")
        env:Fire("PLAYER_LOGIN")
        assert.are.equal(frames, #env:Widgets("Frame"))
    end)
end)

describe("SavedVariables", function()
    it("primer inicio: crea las tablas con los valores por defecto (copias, no referencias)", function()
        local env, ns = WowEnv.boot(TOC)
        assert.are.same(ns.DEFAULTS, env.RutaMisionesDB)
        assert.are.same(ns.CHAR_DEFAULTS, env.RutaMisionesCharDB)
        assert.are_not.equal(ns.DEFAULTS.frame, env.RutaMisionesDB.frame)
    end)

    it("segundo inicio: conserva lo guardado y rellena lo que falta", function()
        local env = bootWith({ schema = 1, scale = 1.5, maxSteps = 15, frame = { x = 40 } }, { schema = 1 })
        local db = env.RutaMisionesDB
        assert.are.equal(1.5, db.scale)
        assert.are.equal(15, db.maxSteps)
        assert.are.equal(40, db.frame.x)
        assert.are.equal("RIGHT", db.frame.point)
        assert.are.equal(120, db.frame.y)
        assert.is_true(db.enabled)
        assert.are.equal(1, db.schema)
    end)

    it("una tabla sin schema (anterior a ese campo) se trata como esquema 1", function()
        local env = bootWith({ scale = 2 }, nil)
        assert.are.equal(1, env.RutaMisionesDB.schema)
        assert.are.equal(2, env.RutaMisionesDB.scale)
    end)

    it("unas SavedVariables corruptas (no son tabla) se sustituyen por los valores por defecto", function()
        local env, ns = bootWith("basura", 42)
        assert.are.same(ns.DEFAULTS, env.RutaMisionesDB)
        assert.are.same(ns.CHAR_DEFAULTS, env.RutaMisionesCharDB)
    end)
end)

-- Simula que el desarrollador sube el esquema a 2 y añade MIGRATIONS[2] (renombra el modo
-- "compact" a "minimal"). El código se añade al FINAL de Core.lua solo en memoria: el fichero
-- real no cambia y el resto de líneas conserva su número. MIGRATIONS es local de ese fichero.
local MIGRATION_2 = [[

ns.DEFAULTS.schema = 2
MIGRATIONS[2] = function(db)
    if db.marca == "compact" then
        db.marca = "minimal"
    end
end
]]

describe("migraciones de SavedVariables (Core.lua con un esquema 2 de ejemplo)", function()
    local opts = {
        patch = {
            ["Core.lua"] = function(source)
                return source .. MIGRATION_2
            end,
        },
    }

    it("migra una tabla del esquema 1 al 2 y conserva el resto", function()
        local env = bootWith({ schema = 1, marca = "compact", scale = 1.3 }, nil, opts)
        assert.are.equal(2, env.RutaMisionesDB.schema)
        assert.are.equal("minimal", env.RutaMisionesDB.marca)
        assert.are.equal(1.3, env.RutaMisionesDB.scale)
    end)

    it("una instalación nueva nace en el esquema actual sin pasar por la migración", function()
        local env = bootWith(nil, nil, opts)
        assert.are.equal(2, env.RutaMisionesDB.schema)
        assert.is_nil(env.RutaMisionesDB.marca)
    end)

    it("una tabla sin schema también se migra", function()
        local env = bootWith({ marca = "compact" }, nil, opts)
        assert.are.equal(2, env.RutaMisionesDB.schema)
        assert.are.equal("minimal", env.RutaMisionesDB.marca)
    end)

    it("es idempotente: un segundo inicio con la tabla migrada no cambia nada", function()
        local first = bootWith({ schema = 1, marca = "compact" }, nil, opts).RutaMisionesDB
        local copy = deepCopy(first)
        local second = bootWith(first, nil, opts).RutaMisionesDB
        assert.are.same(copy, second)
    end)

    it("la tabla por personaje sigue en su propio esquema", function()
        local env = bootWith({ schema = 1, marca = "compact" }, { schema = 1 }, opts)
        assert.are.equal(1, env.RutaMisionesCharDB.schema)
        assert.is_nil(env.RutaMisionesCharDB.marca)
    end)
end)

-- Las migraciones de personaje van en su propia tabla (CHAR_MIGRATIONS): subir el esquema de una
-- base de datos no ejecuta las migraciones de la otra.
local CHAR_MIGRATION_2 = [[

ns.CHAR_DEFAULTS.schema = 2
CHAR_MIGRATIONS[2] = function(db)
    db.migratedChar = true
end
]]

describe("migraciones por personaje separadas de las de cuenta", function()
    local opts = {
        patch = {
            ["Core.lua"] = function(source)
                return source .. CHAR_MIGRATION_2
            end,
        },
    }

    it("migra solo la tabla de personaje", function()
        local env = bootWith({ schema = 1, marca = "compact" }, { schema = 1 }, opts)
        assert.are.equal(2, env.RutaMisionesCharDB.schema)
        assert.is_true(env.RutaMisionesCharDB.migratedChar)
        assert.are.equal(1, env.RutaMisionesDB.schema)
        assert.is_nil(env.RutaMisionesDB.migratedChar)
    end)

    it("una tabla guardada por una versión más nueva del addon no se toca", function()
        local env = bootWith({ schema = 5, marca = "compact" }, nil, opts)
        assert.are.equal(5, env.RutaMisionesDB.schema)
        assert.are.equal("compact", env.RutaMisionesDB.marca)
    end)
end)
