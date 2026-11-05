-- Mock de los valores secretos de Midnight (activos en WoW Forever) para tests fuera del juego.
-- Requiere Lua 5.1 o LuaJIT: usa newproxy(true) porque en Lua 5.1 __len no se aplica a tablas.
--
-- Reglas que reproduce para código de addon (tainted):
--   permitido: guardar, pasar a funciones, concatenar, string.format/strjoin/strconcat
--              (el resultado sigue siendo secreto), type() devuelve el tipo real,
--              igualdad entre tipos distintos (false) y nil == nil (true).
--   error:     aritmética, <, <=, >, >=, igualdad entre dos secretos del mismo tipo, #,
--              indexar, asignar campos, llamar, tonumber(secreto).
-- NO detecta (límite de Lua 5.1, no hay metamétodo posible):
--   secreto == 5 (da false sin error; en el cliente es error), usar un secreto como clave
--   de tabla (usa M.assertNoSecretKeys) y `if secretoBooleano then` (siempre verdadero).
local M = {}

local data = setmetatable({}, { __mode = "k" }) -- proxy -> { v = valor real, t = tipo real }
local base = newproxy(true)
local mt = getmetatable(base)

-- Nivel 3: el error señala la línea del addon que hizo la operación, no este fichero.
local function deny(what, level)
    error("secret value: " .. what .. " no permitido en código de addon", level or 3)
end

-- Crea secretos a partir de valores normales (equivale a secretwrap() del cliente).
-- Un valor que ya es secreto se devuelve tal cual.
function M.wrap(...)
    local n = select("#", ...)
    local out = { ... }
    for i = 1, n do
        local v = out[i]
        if v == nil or not data[v] then
            local p = newproxy(base)
            data[p] = { v = v, t = type(v) }
            out[i] = p
        end
    end
    return unpack(out, 1, n)
end

function M.is(v)
    return v ~= nil and data[v] ~= nil
end

-- Solo para aserciones de los tests: el valor real que esconde un secreto.
function M.reveal(v)
    local d = v ~= nil and data[v]
    if d then
        return d.v
    end
    return v
end

-- Tipo real de un valor, sea secreto o no (lo que devuelve type() en el cliente).
function M.rawtype(v)
    local d = v ~= nil and data[v]
    return d and d.t or type(v)
end

-- Texto legible para mensajes de los tests: "<secreto number: 5000>".
function M.describe(v)
    local d = v ~= nil and data[v]
    if d then
        return "<secreto " .. d.t .. ": " .. tostring(d.v) .. ">"
    end
    return tostring(v)
end

local function anySecret(...)
    for i = 1, select("#", ...) do
        if M.is((select(i, ...))) then
            return true
        end
    end
    return false
end
M.anySecret = anySecret

local function revealAll(...)
    local n = select("#", ...)
    local out = { ... }
    for i = 1, n do
        out[i] = M.reveal(out[i])
    end
    return unpack(out, 1, n)
end
M.revealAll = revealAll

for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
    mt[event] = function()
        deny("la aritmética (" .. event .. ")")
    end
end
mt.__lt = function()
    deny("la comparación de orden")
end
mt.__le = mt.__lt
mt.__eq = function(a, b) -- Lua 5.1 solo lo llama si los DOS operandos son secretos
    local da, db = data[a], data[b]
    if da.t ~= db.t then
        return false
    end
    if da.t == "nil" then
        return true
    end
    deny("la igualdad entre secretos del mismo tipo")
end
mt.__len = function()
    deny("el operador #")
end
mt.__index = function()
    deny("indexar un secreto")
end
mt.__newindex = function()
    deny("asignar un campo de un secreto")
end
mt.__call = function()
    deny("llamar a un secreto")
end
mt.__concat = function(a, b)
    local va, vb = M.reveal(a), M.reveal(b)
    local ta, tb = type(va), type(vb)
    if (ta ~= "string" and ta ~= "number") or (tb ~= "string" and tb ~= "number") then
        deny("concatenar un valor " .. ((ta ~= "string" and ta ~= "number") and ta or tb))
    end
    return M.wrap(va .. vb)
end
mt.__tostring = function(p) -- tostring(secreto) devuelve otro secreto (inferencia, ver informe 21)
    return M.wrap(tostring(data[p].v))
end
mt.__metatable = false

-- Recorre una tabla (p. ej. tus SavedVariables) y falla si algún secreto se usó como clave
-- o quedó guardado como valor. Lua 5.1 no permite detectar la clave en el momento.
function M.assertNoSecretKeys(tbl, path, seen)
    path, seen = path or "tabla", seen or {}
    if seen[tbl] then
        return
    end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if M.is(k) then
            error(path .. ": un secreto se usó como clave de tabla", 2)
        end
        if M.is(v) then
            error(path .. "." .. tostring(k) .. ": hay un secreto guardado", 2)
        end
        if type(v) == "table" then
            M.assertNoSecretKeys(v, path .. "." .. tostring(k), seen)
        end
    end
end

-- string.format admite secretos y devuelve un secreto. Se parchea la tabla global `string`
-- porque ("%d"):format(x) usa la metatabla de las cadenas, no el entorno del addon.
-- Sin secretos en los argumentos el comportamiento es idéntico al original.
-- El original se guarda en la propia tabla `string` porque busted recarga los módulos en cada
-- fichero de spec (insulate) pero no restaura los campos de `string`.
local originalFormat = rawget(string, "_originalFormat") or string.format
rawset(string, "_originalFormat", originalFormat)
function M.install()
    ---@diagnostic disable-next-line: duplicate-set-field
    string.format = function(fmt, ...)
        if M.is(fmt) or anySecret(...) then
            return M.wrap(originalFormat(M.reveal(fmt), revealAll(...)))
        end
        return originalFormat(fmt, ...)
    end
end

-- Funciones del cliente (FrameScript) sobre secretos, vistas desde código de addon.
-- wow_env.lua las pone como globales del entorno simulado.
function M.api()
    local api = {}
    api.issecretvalue = M.is
    api.canaccessvalue = function(v)
        return not M.is(v)
    end
    api.canaccesssecrets = function()
        return false
    end
    api.hasanysecretvalues = anySecret
    api.issecrettable = function()
        return false -- el mock no modela tablas secretas
    end
    api.secretwrap = M.wrap
    api.scrubsecretvalues = function(...)
        local n = select("#", ...)
        local out = { ... }
        for i = 1, n do
            if M.is(out[i]) then
                out[i] = nil
            end
        end
        return unpack(out, 1, n)
    end
    api.type = M.rawtype
    api.tonumber = function(v, b)
        if M.is(v) then
            deny("tonumber() sobre un secreto", 3)
        end
        return tonumber(v, b)
    end
    local function join(sep, ...) -- strjoin/strconcat de WoW: secreto si entra algún secreto
        local n = select("#", ...)
        local parts = { revealAll(...) }
        for i = 1, n do
            parts[i] = tostring(parts[i])
        end
        local s = table.concat(parts, M.reveal(sep), 1, n)
        if M.is(sep) or anySecret(...) then
            return M.wrap(s)
        end
        return s
    end
    api.strjoin = join
    api.strconcat = function(...)
        return join("", ...)
    end
    return api
end

-- Para busted (y el shim de probar_addon.py): que los fallos muestren "<secreto number: 5000>".
function M.registerFormatter(assertObject)
    if assertObject and assertObject.add_formatter then
        assertObject:add_formatter(function(v)
            if M.is(v) then
                return M.describe(v)
            end
        end)
    end
end

return M
