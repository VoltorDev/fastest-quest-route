-- Identidad del personaje (Identity.lua, references/forever.md §9.3-9.4) en el Forever simulado
-- ("Nombre Apellido", sin reino) y en retail ("Nombre-Reino"). Se carga solo Identity.lua; en retail
-- con force = true, porque el TOC de la plantilla no carga allí pero el módulo debe funcionar igual.
local WowEnv = require("wow_env")
local Secret = require("secret_mock")

local TOC = "RutaMisiones.toc"

local function identity(opts)
    local env = WowEnv.new(opts)
    local ns = env:LoadToc(TOC, { force = true, only = { "Identity.lua" } }) or error("Identity.lua no cargó")
    return ns.Identity, env
end

describe("identidad en Forever (nombres regionales)", function()
    it("nombre completo y clave «Nombre Apellido», sin reino, y ruleset PvE por defecto", function()
        local Identity, env = identity({ realm = "ClassicBetaPvE" })
        assert.is_true(Identity.UsesRegionalNames())
        assert.are.equal("Nombre Apellido", Identity.GetPlayerFullName())
        assert.are.equal("Nombre Apellido", Identity.GetCharacterKey())
        assert.are.equal("PvE", Identity.GetRuleset())
        assert.are.same({}, env:Missing())
    end)

    it("no duplica el apellido si el primer retorno ya lo trae", function()
        local Identity = identity({ names = { player = { "Nombre Apellido" } } })
        assert.are.equal("Nombre Apellido", Identity.GetPlayerFullName())
        assert.are.equal("Nombre Apellido", Identity.GetCharacterKey())
    end)

    it("sin apellido, se queda con el nombre", function()
        local Identity = identity({ names = { player = { "Nombre" } } })
        assert.are.equal("Nombre", Identity.GetPlayerFullName())
        assert.are.equal("Nombre", Identity.GetCharacterKey())
    end)

    it("ruleset en el orden de AceDB 39: Hardcore, RP, PvP, PvE", function()
        local R = { Hardcore = 10, PvP = 213, RP = 214 } -- Enum.GameRule del volcado
        assert.are.equal("PvP", (identity({ rules = { [R.PvP] = true } })).GetRuleset())
        assert.are.equal("RP", (identity({ rules = { [R.PvP] = true, [R.RP] = true } })).GetRuleset())
        assert.are.equal("Hardcore", (identity({ rules = { [R.PvP] = true, [R.Hardcore] = true } })).GetRuleset())
    end)

    it("sin reglas de juego en el cliente, GetRuleset devuelve nil", function()
        local Identity = identity({ absent = { "C_GameRules" } })
        assert.is_nil(Identity.GetRuleset())
    end)

    it("NormalizeSender quita el sufijo de reino interno pero no convierte «Nombre-Apellido»", function()
        local Identity = identity()
        assert.are.equal("Otro Jugador", Identity.NormalizeSender("Otro Jugador"))
        assert.are.equal("Otro Jugador", Identity.NormalizeSender("Otro Jugador-ClassicBetaPvP2"))
        assert.are.equal("Otro-Jugador", Identity.NormalizeSender("Otro-Jugador"))
        assert.is_nil(Identity.NormalizeSender(Secret.wrap("Otro Jugador")))
        assert.is_nil(Identity.NormalizeSender(""))
    end)

    it("IsMe reconoce al jugador con y sin sufijo de reino, y nunca con un secreto", function()
        local Identity = identity()
        assert.is_true(Identity.IsMe("Nombre Apellido"))
        assert.is_true(Identity.IsMe("Nombre Apellido-ClassicBetaPvE"))
        assert.is_false(Identity.IsMe("Otro Jugador"))
        assert.is_false(Identity.IsMe(Secret.wrap("Nombre Apellido")))
    end)

    it("si el nombre llega secreto, no hay nombre ni clave", function()
        local Identity = identity({ secretIdentity = { player = true } })
        assert.is_nil(Identity.GetPlayerFullName())
        assert.is_nil(Identity.GetCharacterKey())
        assert.is_nil(Identity.GetCharEntry({}))
    end)
end)

describe("identidad en retail (nombre y reino)", function()
    it("«Nombre-Reino» para mostrar y «Nombre - Reino» como clave de AceDB", function()
        local Identity, env = identity({ client = "retail", realm = "Mi Reino" })
        assert.is_false(Identity.UsesRegionalNames())
        assert.are.equal("Nombre-MiReino", Identity.GetPlayerFullName())
        assert.are.equal("Nombre - Mi Reino", Identity.GetCharacterKey())
        assert.are.same({}, env:Missing())
    end)

    it("NormalizeSender añade el reino propio solo si falta", function()
        local Identity = identity({ client = "retail", realm = "Mi Reino" })
        assert.are.equal("Otro-MiReino", Identity.NormalizeSender("Otro"))
        assert.are.equal("Otro-OtroReino", Identity.NormalizeSender("Otro-OtroReino"))
        assert.is_true(Identity.IsMe("Nombre"))
        assert.is_true(Identity.IsMe("Nombre-MiReino"))
    end)
end)

describe("GetCharEntry: clave «Nombre Apellido» con GUID y ruleset como atributos", function()
    it("crea la entrada con guid, ruleset y fecha de conexión", function()
        local Identity = identity({ rules = { [213] = true } })
        local db = {}
        local entry = Identity.GetCharEntry(db)
        assert.are.equal(entry, db.chars["Nombre Apellido"])
        assert.are.equal("Player-5827-0ABCDEF1", entry.guid)
        assert.are.equal("PvP", entry.ruleset)
        assert.are.equal("number", type(entry.lastLogin))
        Secret.assertNoSecretKeys(db, "db")
    end)

    it("migra una entrada con el mismo GUID guardada con otra clave (beta o AceDB 36-38)", function()
        local Identity = identity()
        local db = {
            chars = {
                ["Nombre - PvE"] = { guid = "Player-5827-0ABCDEF1", gold = 42 },
                ["Otro Alt"] = { guid = "Player-5827-00000002", gold = 7 },
            },
        }
        local entry = Identity.GetCharEntry(db)
        assert.are.equal(42, entry.gold)
        assert.is_nil(db.chars["Nombre - PvE"])
        assert.are.equal(entry, db.chars["Nombre Apellido"])
        assert.are.equal(7, db.chars["Otro Alt"].gold)
    end)

    it("no migra si la clave actual ya existe", function()
        local Identity = identity()
        local db = {
            chars = {
                ["Nombre Apellido"] = { guid = "Player-5827-0ABCDEF1", gold = 1 },
                ["Nombre - PvE"] = { guid = "Player-5827-0ABCDEF1", gold = 42 },
            },
        }
        assert.are.equal(1, Identity.GetCharEntry(db).gold)
        assert.are.equal(42, db.chars["Nombre - PvE"].gold)
    end)

    it("con el GUID secreto (y el nombre legible) no migra ni guarda el GUID", function()
        local Identity, env = identity()
        rawset(env, "UnitGUID", function()
            return Secret.wrap("Player-5827-0ABCDEF1")
        end)
        local db = { chars = { ["Antigua"] = { guid = "Player-5827-0ABCDEF1" } } }
        local entry = Identity.GetCharEntry(db)
        assert.is_nil(entry.guid)
        assert.are.equal(entry, db.chars["Nombre Apellido"])
        assert.is_not_nil(db.chars["Antigua"])
        -- Si la entrada ya tenía GUID, lo conserva.
        db.chars["Nombre Apellido"].guid = "Player-5827-0ABCDEF1"
        assert.are.equal("Player-5827-0ABCDEF1", Identity.GetCharEntry(db).guid)
        Secret.assertNoSecretKeys(db, "db")
    end)
end)
