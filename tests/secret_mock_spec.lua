-- Reglas del mock de valores secretos, incluidos sus límites conocidos: si alguien cambia el
-- mock, estos tests lo delatan. Las reglas del cliente están en el informe 21 (§3.5).
local Secret = require("secret_mock")
Secret.install()
Secret.registerFormatter(assert)
local api = Secret.api()

describe("mock de valores secretos", function()
    local hp, maxHp, name, flag

    before_each(function()
        hp, maxHp, name, flag = Secret.wrap(5000, 8000, "Thrall", true)
    end)

    it("type() del cliente da el tipo real y issecretvalue lo reconoce", function()
        assert.are.equal("number", api.type(hp))
        assert.are.equal("string", api.type(name))
        assert.is_true(api.issecretvalue(hp))
        assert.is_false(api.issecretvalue(5000))
        assert.is_false(api.canaccessvalue(hp))
        assert.is_true(api.hasanysecretvalues(1, hp))
    end)

    it("aritmética, orden, # e indexación fallan", function()
        assert.has_error(function()
            return hp + 1
        end)
        assert.has_error(function()
            return -hp
        end)
        assert.has_error(function()
            return hp < maxHp
        end)
        assert.has_error(function()
            return hp > 0
        end)
        assert.has_error(function()
            return #name
        end)
        assert.has_error(function()
            return name.len
        end)
        assert.has_error(function()
            return name:upper()
        end)
        assert.has_error(function()
            return api.tonumber(hp)
        end)
    end)

    it("igualdad: mismo tipo falla, tipos distintos da false", function()
        assert.has_error(function()
            return hp == maxHp
        end)
        assert.is_false(hp == name)
        assert.is_false(hp == nil)
    end)

    it("concatenar y formatear devuelven secretos", function()
        assert.are.equal("HP: 5000", Secret.reveal("HP: " .. hp))
        local f = ("%d / %d"):format(hp, maxHp)
        assert.is_true(Secret.is(f))
        assert.are.equal("5000 / 8000", Secret.reveal(f))
        assert.are.equal("plain 7", ("plain %d"):format(7)) -- sin secretos, igual que siempre
        assert.is_true(Secret.is(tostring(hp)))
    end)

    it("strjoin, strconcat y scrubsecretvalues", function()
        local joined = api.strjoin(", ", name, "Jaina")
        assert.is_true(Secret.is(joined))
        assert.are.equal("Thrall, Jaina", Secret.reveal(joined))
        assert.are.equal("ab", api.strconcat("a", "b"))
        local a, b, c = api.scrubsecretvalues(1, hp, "x")
        assert.are.equal(1, a)
        assert.is_nil(b)
        assert.are.equal("x", c)
    end)

    it("detecta a posteriori un secreto usado como clave o guardado", function()
        local db = { byName = {} }
        db.byName[name] = 1 -- Lua 5.1 no lo detecta aquí (el cliente sí)
        assert.error_matches(function()
            Secret.assertNoSecretKeys(db, "db")
        end, "clave de tabla")
        assert.error_matches(function()
            Secret.assertNoSecretKeys({ last = hp }, "db")
        end, "hay un secreto guardado")
        assert.has_no_error(function()
            Secret.assertNoSecretKeys({ a = { b = 1 } }, "db")
        end)
    end)

    it("límites conocidos: no detecta secreto == número ni el test de un booleano secreto", function()
        assert.is_false(hp == 5000) -- en el cliente sería un error
        assert.are.equal("sí", flag and "sí" or "no") -- en el cliente sería un error
    end)
end)
