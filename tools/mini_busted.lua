-- Shim MÍNIMO de busted + luassert para ejecutar los specs de un addon con el Lua 5.1 o el LuaJIT
-- de lupa (lo carga scripts/probar_addon.py). No sustituye a busted: implementa la parte de su
-- API que usan los specs de la plantilla y falla con un mensaje claro en lo demás (spy, stub, mock).
--
-- Fases como busted: primero se carga el fichero y se recoge el árbol de describe; después se
-- ejecutan los it. before_each corre de fuera hacia dentro, after_each de dentro hacia fuera y
-- setup/teardown una vez por bloque. Un fallo en un it no detiene los demás.
--
-- Aserciones (estilo luassert, con cadenas de modificadores: is, are, has, was, no, not):
--   equal/equals, same, near, truthy, falsy, true, false, nil, number, string, table, function,
--   boolean, userdata, error/errors (fn, mensaje esperado), error_matches (fn, patrón),
--   matches/match (patrón, texto). Ejemplos: assert.are.equal, assert.is_not_nil,
--   assert.has_no.errors, assert.has_error. El último argumento extra es el mensaje del fallo.
local M = {}

local formatters = {}

-- Texto de un valor para los mensajes: primero los formatters registrados (p. ej. el de secretos);
-- las tablas se muestran con su contenido (hasta 3 niveles y 20 claves por nivel).
local function show(v, depth)
    for _, formatter in ipairs(formatters) do
        local ok, text = pcall(formatter, v)
        if ok and text ~= nil then
            return text
        end
    end
    if type(v) == "string" then
        return ("%q"):format(v)
    end
    if type(v) == "table" and (depth or 0) < 3 then
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local parts = {}
        for i, k in ipairs(keys) do
            if i > 20 then
                parts[#parts + 1] = "..."
                break
            end
            local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. show(k, 3) .. "]")
            parts[#parts + 1] = key .. " = " .. show(v[k], (depth or 0) + 1)
        end
        return #parts == 0 and "{}" or "{ " .. table.concat(parts, ", ") .. " }"
    end
    local ok, text = pcall(tostring, v)
    if ok and type(text) == "string" then
        return type(v) == "number" and text or "(" .. type(v) .. ") " .. text
    end
    return "(" .. type(v) .. ") <?>"
end

-- Mensaje de un error capturado, sea cadena, tabla o secreto.
local function errorText(err)
    if type(err) == "string" then
        return err
    end
    return show(err)
end

local function deepSame(a, b, seen)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    seen = seen or {}
    if seen[a] == b then
        return true
    end
    seen[a] = b
    for k, v in pairs(a) do
        if not deepSame(v, b[k], seen) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- Quita "fichero:línea: " del principio, como luassert al comparar mensajes de error.
local function stripPosition(text)
    return (text:gsub("^.-:%d+: ", "", 1))
end

-- Cada aserción: número de argumentos propios (el siguiente es el mensaje) y una función que
-- devuelve si se cumple y el texto del fallo.
local ASSERTIONS = {
    equal = {
        2,
        function(expected, actual)
            return expected == actual, "Se esperaba igual a " .. show(expected) .. "\nObtenido: " .. show(actual)
        end,
    },
    same = {
        2,
        function(expected, actual)
            return deepSame(expected, actual),
                "Se esperaba el mismo contenido que " .. show(expected) .. "\nObtenido: " .. show(actual)
        end,
    },
    near = {
        3,
        function(expected, actual, tolerance)
            return math.abs(expected - actual) <= tolerance,
                "Se esperaba " .. show(actual) .. " a ±" .. tostring(tolerance) .. " de " .. show(expected)
        end,
    },
    truthy = {
        1,
        function(v)
            return v ~= nil and v ~= false, "Se esperaba un valor verdadero; obtenido " .. show(v)
        end,
    },
    falsy = {
        1,
        function(v)
            return v == nil or v == false, "Se esperaba nil o false; obtenido " .. show(v)
        end,
    },
    ["true"] = {
        1,
        function(v)
            return v == true, "Se esperaba true; obtenido " .. show(v)
        end,
    },
    ["false"] = {
        1,
        function(v)
            return v == false, "Se esperaba false; obtenido " .. show(v)
        end,
    },
    ["nil"] = {
        1,
        function(v)
            return v == nil, "Se esperaba nil; obtenido " .. show(v)
        end,
    },
    error = {
        2,
        function(fn, expected)
            local ok, err = pcall(fn)
            if ok then
                return false, "Se esperaba un error y la función terminó bien"
            end
            if expected ~= nil then
                local text = errorText(err)
                local same = type(err) == "string" and stripPosition(text) == expected or err == expected
                return same, "Error distinto del esperado.\nEsperado: " .. show(expected) .. "\nObtenido: " .. text
            end
            return true, "Se esperaba que NO hubiera error; obtenido: " .. errorText(err)
        end,
    },
    error_matches = {
        2,
        function(fn, pattern)
            local ok, err = pcall(fn)
            if ok then
                return false, "Se esperaba un error que casara con " .. show(pattern)
            end
            local text = errorText(err)
            return text:find(pattern) ~= nil, "El error no casa con " .. show(pattern) .. ": " .. text
        end,
    },
    matches = {
        2,
        function(pattern, actual)
            return type(actual) == "string" and actual:find(pattern) ~= nil,
                "Se esperaba que " .. show(actual) .. " casara con " .. show(pattern)
        end,
    },
}
ASSERTIONS.equals = ASSERTIONS.equal
ASSERTIONS.errors = ASSERTIONS.error
ASSERTIONS.match = ASSERTIONS.matches
for _, kind in ipairs({ "number", "string", "table", "function", "boolean", "userdata" }) do
    ASSERTIONS[kind] = {
        1,
        function(v)
            return type(v) == kind, "Se esperaba un " .. kind .. "; obtenido " .. show(v)
        end,
    }
end

local MODIFIERS = { is = true, are = true, was = true, has = true, does = true, to = true, be = true }
local NEGATIONS = { no = true, ["not"] = true }

-- assert.are.equal / assert.is_not_nil / assert.has_no.errors: cada clave añade palabras a la
-- cadena hasta llegar a una aserción conocida.
local function resolve(negated, key)
    local words = {}
    for word in tostring(key):lower():gmatch("[^_]+") do
        words[#words + 1] = word
    end
    for i, word in ipairs(words) do
        local rest = table.concat(words, "_", i)
        local entry = ASSERTIONS[rest]
        if entry then
            local nargs, check = entry[1], entry[2]
            return function(...)
                local passed, message = check(...)
                if negated then
                    passed = not passed
                    message = "(negada) " .. message
                end
                if not passed then
                    local custom = select(nargs + 1, ...)
                    error(custom ~= nil and tostring(custom) or message, 2)
                end
            end
        elseif NEGATIONS[word] then
            negated = not negated
        elseif not MODIFIERS[word] then
            break
        end
    end
    if #words > 0 and (MODIFIERS[words[#words]] or NEGATIONS[words[#words]]) then
        return nil, negated -- solo modificadores: la cadena continúa (assert.are.<...>)
    end
    error("aserción no soportada por el shim de probar_addon.py: assert." .. tostring(key), 3)
end

local function chainObject(negated)
    return setmetatable({}, {
        __index = function(_, key)
            local fn, nextNegated = resolve(negated, key)
            return fn or chainObject(nextNegated)
        end,
    })
end

local assertObject = setmetatable({}, {
    __index = function(_, key)
        local fn, negated = resolve(false, key)
        return fn or chainObject(negated)
    end,
    __call = function(_, value, message, ...) -- assert(v, msg) de Lua
        if not value then
            error(message or "assertion failed!", 2)
        end
        return value, message, ...
    end,
})
rawset(assertObject, "add_formatter", function(_, formatter)
    table.insert(formatters, 1, formatter)
end)
rawset(assertObject, "remove_formatter", function(_, formatter)
    for i = #formatters, 1, -1 do
        if formatters[i] == formatter then
            table.remove(formatters, i)
        end
    end
end)

-- Árbol de bloques ---------------------------------------------------------------------------
local function newBlock(name, parent)
    return {
        name = name,
        parent = parent,
        children = {},
        before_each = {},
        after_each = {},
        setup = {},
        teardown = {},
    }
end

local root = newBlock(nil, nil)
local current = root
local running -- test en ejecución (para finally)

local function traceback(err)
    return { message = errorText(err), trace = debug.traceback("", 2) }
end

local function describe(name, fn)
    local block = newBlock(name, current)
    current.children[#current.children + 1] = { kind = "describe", block = block }
    local previous = current
    current = block
    local ok, err = xpcall(fn, traceback)
    current = previous
    if not ok then
        block.loadError = err
    end
end

local function it(name, fn)
    if fn == nil then
        current.children[#current.children + 1] = { kind = "pending", name = name }
        return
    end
    current.children[#current.children + 1] = { kind = "it", name = name, fn = fn }
end

local function pending(name)
    current.children[#current.children + 1] = { kind = "pending", name = name }
end

local function adder(field)
    return function(fn)
        local list = current[field]
        list[#list + 1] = fn
    end
end

local function unsupported(name)
    return setmetatable({}, {
        __index = function()
            error(name .. " no está implementado en el shim de probar_addon.py; usa busted real", 2)
        end,
        __call = function()
            error(name .. " no está implementado en el shim de probar_addon.py; usa busted real", 2)
        end,
    })
end

-- Globales de busted.
function M.install(env)
    env.describe, env.context, env.insulate, env.expose = describe, describe, describe, describe
    env.it, env.spec, env.test = it, it, it
    env.pending = pending
    env.before_each, env.after_each = adder("before_each"), adder("after_each")
    env.setup, env.lazy_setup, env.strict_setup = adder("setup"), adder("setup"), adder("setup")
    env.teardown, env.lazy_teardown, env.strict_teardown = adder("teardown"), adder("teardown"), adder("teardown")
    env.finally = function(fn)
        if running then
            running.finally[#running.finally + 1] = fn
        end
    end
    env.randomize = function() end
    env.assert = assertObject
    env.spy, env.stub, env.mock, env.match =
        unsupported("spy"), unsupported("stub"), unsupported("mock"), unsupported("match")
end

-- Ejecución ------------------------------------------------------------------------------------
local results = {}

local function record(status, path, name, err)
    local full = {}
    for _, part in ipairs(path) do
        full[#full + 1] = part
    end
    full[#full + 1] = name
    results[#results + 1] = {
        status = status,
        name = table.concat(full, " / "),
        message = err and err.message or nil,
        trace = err and err.trace or nil,
    }
end

local function hasTests(block)
    for _, child in ipairs(block.children) do
        if child.kind == "it" or (child.kind == "describe" and hasTests(child.block)) then
            return true
        end
    end
    return false
end

local function fullName(path, name)
    local parts = { unpack(path) }
    parts[#parts + 1] = name
    return table.concat(parts, " / ")
end

local function runBlock(block, path, befores, afters, filter)
    if block.loadError then
        record("error", path, "(al cargar el bloque)", block.loadError)
        return
    end
    if not hasTests(block) then
        return
    end
    for _, fn in ipairs(block.setup) do
        local ok, err = xpcall(fn, traceback)
        if not ok then
            record("error", path, "(setup)", err)
            return
        end
    end
    local myBefores = { unpack(befores) }
    for _, fn in ipairs(block.before_each) do
        myBefores[#myBefores + 1] = fn
    end
    local myAfters = {}
    for _, fn in ipairs(block.after_each) do
        myAfters[#myAfters + 1] = fn
    end
    for _, fn in ipairs(afters) do
        myAfters[#myAfters + 1] = fn
    end
    for _, child in ipairs(block.children) do
        if child.kind == "describe" then
            local childPath = { unpack(path) }
            childPath[#childPath + 1] = child.block.name
            runBlock(child.block, childPath, myBefores, myAfters, filter)
        elseif child.kind == "pending" then
            record("pending", path, child.name)
        elseif not filter or fullName(path, child.name):find(filter, 1, true) then
            running = { finally = {} }
            local ok, err = xpcall(function()
                for _, fn in ipairs(myBefores) do
                    fn()
                end
                child.fn()
            end, traceback)
            for _, fn in ipairs(myAfters) do
                local okAfter, errAfter = xpcall(fn, traceback)
                if ok and not okAfter then
                    ok, err = false, errAfter
                end
            end
            for _, fn in ipairs(running.finally) do
                pcall(fn)
            end
            running = nil
            record(ok and "ok" or "fallo", path, child.name, not ok and err or nil)
        end
    end
    for _, fn in ipairs(block.teardown) do
        local ok, err = xpcall(fn, traceback)
        if not ok then
            record("error", path, "(teardown)", err)
        end
    end
end

-- Carga un spec (recoge su árbol) y ejecuta sus tests. Devuelve la lista de resultados:
-- { status = "ok" | "fallo" | "error" | "pending", name, message, trace }.
function M.runFile(path, filter)
    results = {}
    root = newBlock(nil, nil)
    current = root
    local chunk, loadErr = loadfile(path)
    if not chunk then
        record("error", {}, "(no compila)", { message = loadErr })
        return results
    end
    local ok, err = xpcall(chunk, traceback)
    if not ok then
        record("error", {}, "(al cargar el fichero)", err)
        return results
    end
    runBlock(root, {}, {}, {}, filter)
    return results
end

return M
