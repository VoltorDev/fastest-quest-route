-- C_Timer falso del cliente simulado (wow_env.lua) y un ejemplo de cómo probar código con
-- temporizadores: nada se dispara hasta env:Advance(segundos), que también mueve GetTime().
local WowEnv = require("wow_env")

describe("C_Timer simulado", function()
    it("After no dispara hasta que pasa el tiempo, y GetTime avanza con Advance", function()
        local env = WowEnv.new()
        local calls = {}
        env.C_Timer.After(1.5, function(...)
            calls[#calls + 1] = { n = select("#", ...), t = env.GetTime() }
        end)
        assert.are.equal(1000, env.GetTime())
        assert.are.equal(0, env:Advance(1))
        assert.are.equal(0, #calls)
        assert.are.equal(1, env:Advance(1))
        assert.are.same({ { n = 0, t = 1001.5 } }, calls)
        assert.are.equal(1002, env.GetTime())
        assert.are.equal(0, env:PendingTimers())
    end)

    it("dispara en orden de vencimiento y, si empatan, en orden de creación", function()
        local env = WowEnv.new()
        local order = {}
        env.C_Timer.After(2, function()
            order[#order + 1] = "b"
        end)
        env.C_Timer.After(1, function()
            order[#order + 1] = "a"
        end)
        env.C_Timer.After(2, function()
            order[#order + 1] = "c"
        end)
        env:Advance(5)
        assert.are.same({ "a", "b", "c" }, order)
    end)

    it("NewTimer pasa su handle al callback y Cancel lo anula", function()
        local env = WowEnv.new()
        local received
        local timer = env.C_Timer.NewTimer(1, function(handle)
            received = handle
        end)
        local cancelled = env.C_Timer.NewTimer(1, function()
            error("no debería dispararse")
        end)
        cancelled:Cancel()
        assert.is_true(cancelled:IsCancelled())
        assert.are.equal(1, env:PendingTimers())
        env:Advance(1)
        assert.are.equal(timer, received)
        assert.is_false(timer:IsCancelled())
    end)

    it("NewTicker con iteraciones llama ese número de veces, a intervalos", function()
        local env = WowEnv.new()
        local times = {}
        env.C_Timer.NewTicker(0.5, function()
            times[#times + 1] = env.GetTime()
        end, 3)
        assert.are.equal(3, env:Advance(10))
        assert.are.same({ 1000.5, 1001, 1001.5 }, times)
        assert.are.equal(0, env:PendingTimers())
    end)

    it("un ticker sin iteraciones sigue hasta que se cancela desde su callback", function()
        local env = WowEnv.new()
        local n = 0
        env.C_Timer.NewTicker(1, function(ticker)
            n = n + 1
            if n == 4 then
                ticker:Cancel()
            end
        end)
        env:Advance(100)
        assert.are.equal(4, n)
        assert.are.equal(0, env:PendingTimers())
    end)

    it("rechaza argumentos que no son (segundos, función), como el cliente", function()
        local env = WowEnv.new()
        assert.has_error(function()
            env.C_Timer.After("1", function() end)
        end)
        assert.has_error(function()
            env.C_Timer.NewTicker(1, nil)
        end)
    end)
end)

-- Ejemplo: vender la basura de una en una, cada 0,25 s, mientras el mercader siga abierto. El código
-- probado se carga con env:LoadString (en un addon real estaría en su fichero del TOC) y las API que
-- la plantilla no simula (C_Container) se sustituyen con opts.globals.
local SELL_JUNK = [[
local _, ns = ...
function ns.SellJunk()
    local queue = {}
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                queue[#queue + 1] = { bag, slot }
            end
        end
    end
    if #queue == 0 then
        return nil
    end
    local i = 0
    return C_Timer.NewTicker(0.25, function(ticker)
        i = i + 1
        local item = queue[i]
        if not ns.merchantOpen or not item then
            ticker:Cancel()
            return
        end
        C_Container.UseContainerItem(item[1], item[2])
    end, #queue)
end
]]

describe("ejemplo: venta lenta de basura con temporizador", function()
    local env, ns, sold

    before_each(function()
        sold = {}
        -- Mochila 0 con 4 huecos: basura, objeto normal, basura sin valor y basura.
        local bag0 = {
            { quality = 0, hasNoValue = false },
            { quality = 1, hasNoValue = false },
            { quality = 0, hasNoValue = true },
            { quality = 0, hasNoValue = false },
        }
        env = WowEnv.new({
            globals = {
                C_Container = {
                    GetContainerNumSlots = function(bag)
                        return bag == 0 and #bag0 or 0
                    end,
                    GetContainerItemInfo = function(bag, slot)
                        return bag == 0 and bag0[slot] or nil
                    end,
                    UseContainerItem = function(bag, slot)
                        sold[#sold + 1] = bag .. ":" .. slot
                    end,
                },
            },
        })
        env.Enum.ItemQuality = { Poor = 0, Common = 1 } -- ItemQualitiesDocumentation.lua
        ns = { merchantOpen = true }
        env:LoadString(SELL_JUNK, "VentaLenta.lua", "RutaMisiones", ns)
    end)

    it("vende un objeto cada 0,25 s y solo la basura con valor", function()
        ns.SellJunk()
        env:Advance(0.125)
        assert.are.same({}, sold)
        env:Advance(0.125)
        assert.are.same({ "0:1" }, sold)
        env:Advance(1)
        assert.are.same({ "0:1", "0:4" }, sold)
        assert.are.equal(0, env:PendingTimers())
        assert.are.same({}, env:Missing())
    end)

    it("si se cierra el mercader, deja de vender", function()
        local ticker = ns.SellJunk()
        env:Advance(0.25)
        ns.merchantOpen = false
        env:Advance(1)
        assert.are.same({ "0:1" }, sold)
        assert.is_true(ticker:IsCancelled())
    end)
end)
