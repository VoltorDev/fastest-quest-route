-- Cliente WoW simulado para tests fuera del juego (busted o scripts/probar_addon.py de la skill).
-- Requiere Lua 5.1 o LuaJIT (setfenv). Carga los ficheros de un TOC como el juego: cada chunk
-- recibe (addonName, ns) y corre en un entorno aislado con marcos, eventos, Settings y el mock
-- de secretos. Simula SOLO lo que usa la plantilla: si el addon lee una global que no existe
-- aquí, aparece en env:Missing() y el test de carga falla; añádela al perfil o a opts.globals.
--
-- Uso típico (desde la carpeta del addon, que es donde se ejecutan los tests):
--   local env = WowEnv.new({ health = { player = { 5000, 8000 } } })
--   env:LoadToc("RutaMisiones.toc")
--   env:Login()                      -- ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD
--   assert.are.same({}, env:Missing())
--   env:Advance(1.5)                 -- C_Timer falso: el tiempo (y GetTime) solo avanza así
local Secret = require("secret_mock")
local ALLOWED = require("secret_args_forever") -- generado por scripts/exportar_secret_args.py

Secret.install()

local M = {}

-- Perfiles de cliente --------------------------------------------------------------------------
-- forever: beta 1.60.1.70291 del clon de wow-ui-source (el lanzamiento puede cambiarlos).
-- forever_renamed: hipótesis de renombrado "camelot" -> "forever" (INFERENCIA, no existe aún).
-- retail y classic_era: valores plausibles SOLO para probar el detector (INFERENCIA; build ficticio).
--   gameTypes: tokens que casan en AllowLoadGameType/ExcludeLoadGameType (tipo de juego + familia,
--              como en los TOC de Blizzard: [AllowLoadGameType mainline] carga en Forever).
--   tocVars:   cómo expande el cliente [Game] y [Family] en rutas y metadatos del TOC.
--   absent:    globales que ese cliente NO define y que un detector sondea a propósito
--              (leerlas no cuenta como "sin simular").
--   regionalNames, player: nombres "Nombre Apellido" únicos por región (Forever) o "Nombre" + reino;
--              player = lo que devuelven UnitName/UnitNameUnmodified("player") si no hay opts.names.
-- Separadores de nombre de Forever: volcado de Ketho, LuaEnum.lua:9485-9489 (build 70205).
local NAME_SEPARATORS = {
    CHARACTERNAME_LINK_SEPARATOR = "-",
    CHARACTERNAME_REALMNAME_SEPARATOR = "-",
    CHARACTERNAME_SURNAME_SEPARATOR = " ",
}
-- stylua: ignore start
local PROFILES = {
    forever = {
        build = { "1.60.1", "70291", "Oct 8 2026", 16001 },
        gameTypes = { "camelot", "mainline" },
        tocVars = { Game = "Camelot", Family = "Mainline" },
        globals = { WOW_PROJECT_ID = 18, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
            WOW_PROJECT_CAMELOT = 18, LE_EXPANSION_CLASSIC = 0, LE_EXPANSION_LEVEL_CURRENT = 0,
            Constants = { CharacterNameSeparatorConsts = NAME_SEPARATORS } },
        absent = { "WOW_PROJECT_FOREVER" },
        secrets = true,
        regionalNames = true,
        player = { "Nombre", "Apellido" },
    },
    forever_renamed = {
        build = { "1.60.1", "70291", "Oct 8 2026", 16001 },
        gameTypes = { "forever", "mainline" },
        tocVars = { Game = "Forever", Family = "Mainline" },
        globals = { WOW_PROJECT_ID = 18, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
            WOW_PROJECT_FOREVER = 18, LE_EXPANSION_CLASSIC = 0, LE_EXPANSION_LEVEL_CURRENT = 0,
            Constants = { CharacterNameSeparatorConsts = NAME_SEPARATORS } },
        absent = { "WOW_PROJECT_CAMELOT" },
        secrets = true,
        regionalNames = true,
        player = { "Nombre", "Apellido" },
    },
    -- retail y classic_era: Constants sin CharacterNameSeparatorConsts (INFERENCIA: obliga a usar
    -- los separadores de respaldo; el volcado disponible es solo el de Forever).
    retail = {
        build = { "12.0.1", "99999", "Sep 1 2026", 120001 },
        gameTypes = { "standard", "mainline" },
        tocVars = { Game = "Standard", Family = "Mainline" },
        globals = { WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
            LE_EXPANSION_CLASSIC = 0, LE_EXPANSION_LEVEL_CURRENT = 11, Constants = {} },
        absent = { "WOW_PROJECT_CAMELOT", "WOW_PROJECT_FOREVER" },
        secrets = true,
        regionalNames = false,
        player = { "Nombre" },
    },
    classic_era = {
        build = { "1.15.7", "99999", "Sep 1 2026", 11507 },
        gameTypes = { "vanilla", "classic" },
        tocVars = { Game = "Vanilla", Family = "Classic" },
        globals = { WOW_PROJECT_ID = 2, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
            LE_EXPANSION_CLASSIC = 0, LE_EXPANSION_LEVEL_CURRENT = 0, Constants = {} },
        absent = { "WOW_PROJECT_CAMELOT", "WOW_PROJECT_FOREVER", "C_Secrets", "issecretvalue",
            "canaccessvalue", "hasanysecretvalues", "scrubsecretvalues", "secretwrap" },
        secrets = false,
        regionalNames = false,
        player = { "Nombre" },
    },
}
-- stylua: ignore end
M.PROFILES = PROFILES

-- Comprobación de SecretArguments ----------------------------------------------------------------
-- Cadenas de herencia de la API de widgets (nombres de los ScriptObject de la documentación).
-- stylua: ignore start
local REGION = { "SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI",
    "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local FRAME = { "SimpleFrameAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI",
    "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local function chain(extra, rest)
    local t = {}
    for _, v in ipairs(extra) do t[#t + 1] = v end
    for _, v in ipairs(rest) do t[#t + 1] = v end
    return t
end
local CHAINS = {
    Frame = FRAME,
    Button = chain({ "SimpleButtonAPI" }, FRAME),
    CheckButton = chain({ "SimpleCheckboxAPI", "SimpleButtonAPI" }, FRAME),
    StatusBar = chain({ "SimpleStatusBarAPI" }, FRAME),
    Slider = chain({ "SimpleSliderAPI" }, FRAME),
    EditBox = chain({ "SimpleEditBoxAPI" }, FRAME),
    ScrollFrame = chain({ "SimpleScrollFrameAPI" }, FRAME),
    MessageFrame = chain({ "SimpleMessageFrameAPI" }, FRAME),
    Cooldown = chain({ "FrameAPICooldown" }, FRAME),
    GameTooltip = chain({ "FrameAPITooltip" }, FRAME),
    FontString = chain({ "SimpleFontStringAPI" }, REGION),
    Texture = chain({ "SimpleTextureAPI", "SimpleTextureBaseAPI" }, REGION),
    MaskTexture = chain({ "SimpleMaskTextureAPI", "SimpleTextureBaseAPI" }, REGION),
    Line = chain({ "SimpleLineAPI", "SimpleTextureBaseAPI" }, REGION),
}
-- stylua: ignore end

-- Un método solo acepta secretos si su documentación dice AllowedWhenTainted.
-- Nivel 3: el error señala la línea del addon que llamó al método.
local function checkSecretArgs(kind, method, ...)
    if not Secret.anySecret(...) then
        return
    end
    for _, api in ipairs(CHAINS[kind] or FRAME) do
        if ALLOWED[api .. ":" .. method] then
            return
        end
    end
    error(kind .. ":" .. method .. " no acepta argumentos secretos desde código de addon", 3)
end

-- Envuelve una función simulada del cliente para que rechace secretos salvo si está en la lista.
local function guardApi(name, fn)
    if ALLOWED[name] then
        return fn
    end
    return function(...)
        if Secret.anySecret(...) then
            error(name .. "() no acepta argumentos secretos desde código de addon", 2)
        end
        return fn(...)
    end
end

-- Tabla que acepta cualquier acceso o llamada. Úsala solo (vía opts.globals) para subsistemas
-- que no son objeto del test: devuelve algo "verdadero" para todo y no comprueba nada.
local function autostub()
    return setmetatable({}, {
        __index = function(t, k)
            local child = autostub()
            rawset(t, k, child)
            return child
        end,
        __call = function()
            return autostub()
        end,
    })
end
M.autostub = autostub

-- Sustituye `old` por `new` en el código fuente (texto literal, sin patrones). Falla si `old` no
-- aparece exactamente una vez: así una mutación nunca se aplica en silencio sobre otra línea.
function M.replace(source, old, new)
    local first = source:find(old, 1, true)
    if not first then
        error("no encuentro el texto a sustituir: " .. old, 2)
    end
    if source:find(old, first + 1, true) then
        error("el texto a sustituir aparece más de una vez: " .. old, 2)
    end
    return source:sub(1, first - 1) .. new .. source:sub(first + #old)
end

-- Línea (1, 2...) en la que empieza un texto literal dentro de un fichero.
function M.lineOf(path, text)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a")
    f:close()
    local first = source:find(text, 1, true)
    if not first then
        error("no encuentro '" .. text .. "' en " .. path, 2)
    end
    local _, newlines = source:sub(1, first):gsub("\n", "")
    return newlines + 1
end

-- Marcos y regiones ------------------------------------------------------------------------------
local function newWidget(env, kind, name, parent, template)
    local w = { _kind = kind, _name = name, _parent = parent, _template = template }
    w._calls, w._scripts, w._events, w._points, w._shown = {}, {}, {}, {}, true
    local m = {}
    -- stylua: ignore start
    function m:GetObjectType() return kind end
    function m:IsObjectType(t) return t == kind end
    function m:GetName() return self._name end
    function m:GetParent() return self._parent end
    function m:SetScript(script, fn) self._scripts[script] = fn end
    function m:GetScript(script) return self._scripts[script] end
    function m:HookScript(script, fn)
        local old = self._scripts[script]
        self._scripts[script] = function(...) if old then old(...) end fn(...) end
    end
    function m:RegisterEvent(event) self._events[event] = true end
    function m:RegisterUnitEvent(event, ...) self._events[event] = { ... } end
    function m:UnregisterEvent(event) self._events[event] = nil end
    function m:UnregisterAllEvents() self._events = {} end
    function m:IsEventRegistered(event) return self._events[event] ~= nil end
    function m:Show() self._shown = true end
    function m:Hide() self._shown = false end
    function m:IsShown() return self._shown end
    function m:SetShown(shown) checkSecretArgs(kind, "SetShown", shown); self._shown = not not shown end
    function m:SetPoint(...)
        checkSecretArgs(kind, "SetPoint", ...)
        self._points[#self._points + 1] = { n = select("#", ...), ... }
    end
    function m:ClearAllPoints() self._points = {} end
    function m:GetNumPoints() return #self._points end
    function m:GetPoint(i) local p = self._points[i or 1]; if p then return unpack(p, 1, p.n) end end
    function m:SetScale(scale) checkSecretArgs(kind, "SetScale", scale); self._scale = scale end
    function m:GetScale() return self._scale or 1 end
    function m:CreateTexture(n, _, tpl) return env:_NewWidget("Texture", n, self, tpl) end
    function m:CreateFontString(n, _, tpl) return env:_NewWidget("FontString", n, self, tpl) end
    -- Barras y textos guardan lo recibido: un secreto entregado sigue siendo secreto al leerlo.
    function m:SetMinMaxValues(lo, hi)
        checkSecretArgs(kind, "SetMinMaxValues", lo, hi)
        self._min, self._max = lo, hi
    end
    function m:GetMinMaxValues() return self._min, self._max end
    function m:SetValue(v) checkSecretArgs(kind, "SetValue", v); self._value = v end
    function m:GetValue() return self._value end
    function m:SetText(t) checkSecretArgs(kind, "SetText", t); self._text = t end
    function m:SetFormattedText(fmt, ...)
        checkSecretArgs(kind, "SetFormattedText", fmt, ...)
        self._text = string.format(fmt, ...)
    end
    function m:GetText() return self._text end
    -- Solo para los tests: llamadas recibidas por los métodos no simulados.
    function m:Calls(method) return self._calls[method] or {} end
    function m:LastCall(method)
        local list = self._calls[method]
        local last = list and list[#list]
        if last then return unpack(last, 1, last.n) end
    end
    -- stylua: ignore end

    return setmetatable(w, {
        __index = function(_, key)
            if m[key] then
                return m[key]
            end
            if type(key) ~= "string" or not key:match("^%u") then
                return nil
            end
            -- Método no simulado (SetSize, SetStatusBarColor...): comprueba secretos y registra.
            -- No comprueba que el método exista en Forever: una errata no falla aquí.
            return function(self, ...)
                checkSecretArgs(kind, key, ...)
                local list = self._calls[key] or {}
                self._calls[key] = list
                list[#list + 1] = { n = select("#", ...), ... }
            end
        end,
    })
end

-- Settings (Blizzard_Settings_Shared) ------------------------------------------------------------
-- Imita lo que el addon puede observar del original (Blizzard_Setting.lua y Blizzard_Settings.lua
-- del clon): RegisterAddOnSetting escribe el valor por defecto en la tabla si la clave es nil,
-- rechaza una variable repetida y SetValue exige el tipo declarado y avisa a los callbacks.
local function newSettings(state)
    local registry = { categories = {}, addOnCategories = {}, settings = {}, controls = {}, opened = {} }
    local S = {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        Default = { True = true, False = false },
    }

    local function newCategory(name, parent)
        local category = { name = name, parent = parent, id = #registry.categories + 1 }
        function category:GetID()
            return self.id
        end
        function category:GetName()
            return self.name
        end
        registry.categories[#registry.categories + 1] = category
        return category
    end
    function S.RegisterVerticalLayoutCategory(name)
        return newCategory(name)
    end
    function S.RegisterVerticalLayoutSubcategory(parent, name)
        return newCategory(name, parent)
    end
    function S.RegisterAddOnCategory(category)
        registry.addOnCategories[#registry.addOnCategories + 1] = category
    end

    function S.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
        assert(type(variableTbl) == "table", "'variableTbl' argument must be a table.")
        if registry.settings[variable] then
            error(("Setting variable '%s' was previously registered."):format(variable), 2)
        end
        if variableTbl[variableKey] == nil then
            variableTbl[variableKey] = defaultValue
        end
        local setting = {
            category = category,
            variable = variable,
            variableKey = variableKey,
            variableTbl = variableTbl,
            variableType = variableType or type(defaultValue),
            name = name,
            defaultValue = defaultValue,
            callbacks = {},
        }
        function setting:GetVariable()
            return self.variable
        end
        function setting:GetName()
            return self.name
        end
        function setting:GetVariableType()
            return self.variableType
        end
        function setting:GetValue()
            return self.variableTbl[self.variableKey]
        end
        function setting:SetValue(value)
            if self.variableTbl[self.variableKey] ~= value then
                if type(value) ~= self.variableType then
                    error(
                        ("SetValue '%s' requires '%s' type, not '%s' type."):format(
                            self.name,
                            self.variableType,
                            type(value)
                        )
                    )
                end
                self.variableTbl[self.variableKey] = value
            end
            for _, callback in ipairs(self.callbacks) do
                callback(self, value)
            end
        end
        function setting:SetValueChangedCallback(callback)
            self.callbacks[#self.callbacks + 1] = callback
        end
        registry.settings[variable] = setting
        return setting
    end

    local function control(kind, category, setting, options, tooltip)
        local c = { kind = kind, category = category, setting = setting, options = options, tooltip = tooltip }
        registry.controls[#registry.controls + 1] = c
        return c
    end
    function S.CreateCheckbox(category, setting, tooltip)
        return control("Checkbox", category, setting, nil, tooltip)
    end
    function S.CreateSlider(category, setting, options, tooltip)
        return control("Slider", category, setting, options, tooltip)
    end
    function S.CreateDropdown(category, setting, options, tooltip)
        return control("Dropdown", category, setting, options, tooltip)
    end
    function S.CreateSliderOptions(minValue, maxValue, rate)
        local options = { minValue = minValue or 0, maxValue = maxValue or 1, formatters = {} }
        options.steps = (rate and (options.maxValue - options.minValue) / rate) or 100
        function options:SetLabelFormatter(labelType, formatter)
            self.formatters[labelType] = formatter
        end
        return options
    end
    function S.CreateControlTextContainer()
        local container = { data = {} }
        function container:Add(value, label, tooltip)
            local entry = { value = value, label = label, text = label, tooltip = tooltip }
            self.data[#self.data + 1] = entry
            return entry
        end
        function container:GetData()
            return self.data
        end
        return container
    end
    -- C_SettingsUtil.OpenSettingsPanel lleva HasRestrictions: en combate se trata como bloqueado
    -- (INFERENCIA sobre el efecto exacto; el addon debe comprobar InCombatLockdown antes).
    function S.OpenToCategory(categoryID)
        if state.combat then
            error("Settings.OpenToCategory en combate: acción bloqueada (HasRestrictions)", 2)
        end
        registry.opened[#registry.opened + 1] = categoryID
    end
    function S.GetSetting(variable)
        return registry.settings[variable]
    end
    function S.GetValue(variable)
        local setting = registry.settings[variable]
        return setting and setting:GetValue()
    end
    function S.SetValue(variable, value)
        local setting = registry.settings[variable]
        if not setting then
            error(("Setting for variable '%s' did not exist."):format(variable), 2)
        end
        setting:SetValue(value)
    end
    return S, registry
end

-- TOC --------------------------------------------------------------------------------------------
local function tokenSet(list)
    local set = {}
    for token in (list or ""):lower():gmatch("[%w_]+") do
        set[token] = true
    end
    return set
end

local function matchesAny(list, gameTypes)
    local set = tokenSet(list)
    for _, token in ipairs(gameTypes) do
        if set[token] then
            return true
        end
    end
    return false
end

-- ¿Pasa este texto sus condiciones en línea [AllowLoadGameType ...] / [ExcludeLoadGameType ...]?
local function inlineConditionsOk(text, profile)
    for directive, list in text:gmatch("%[(%a+)%s+([^%]]*)%]") do
        if directive == "AllowLoadGameType" and not matchesAny(list, profile.gameTypes) then
            return false
        elseif directive == "ExcludeLoadGameType" and matchesAny(list, profile.gameTypes) then
            return false
        end
    end
    return true
end

-- Directivas en línea que el cliente interpreta (y no forman parte del valor ni de la ruta).
local DIRECTIVES = {
    AllowLoadGameType = true,
    ExcludeLoadGameType = true,
    AllowLoad = true,
    AllowLoadEnvironment = true,
    LoadIntoEnvironment = true,
}

local function stripDirectives(text)
    return (
        text:gsub("%s*%[(%a+)%s[^%]]*%]", function(directive)
            if DIRECTIVES[directive] then
                return ""
            end
        end)
    )
end

-- Sustituye [Game], [Family] y [TextLocale]. En rutas (stripRest) quita además el resto de
-- corchetes, como [Bootstrap]; en metadatos deja intacto el texto que no es variable.
local function expandVariables(text, vars, stripRest)
    text = text:gsub("%[(%a+)%]", function(var)
        return vars[var]
    end)
    if stripRest then
        text = text:gsub("%s*%[[^%]]*%]", "")
    end
    return text
end

-- Lee un TOC como el cliente del perfil: metadatos (con variables expandidas si el cliente lo
-- hace) y la lista de ficheros que cargaría.
local function parseToc(path, profile, vars, expandMetadata)
    local toc = { meta = {}, files = {} }
    for raw in io.lines(path) do
        local line = raw:gsub("^\239\187\191", ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local key, value = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)$")
        if key then
            if inlineConditionsOk(value, profile) then
                value = stripDirectives(value)
                toc.meta[key:lower()] = expandMetadata and expandVariables(value, vars) or value
            end
        elseif line ~= "" and not line:match("^#") then
            if inlineConditionsOk(line, profile) then
                local file = expandVariables(stripDirectives(line), vars, true)
                toc.files[#toc.files + 1] = (file:gsub("\\", "/"))
            end
        end
    end
    return toc
end

-- ¿Cargaría el cliente este addon? Devuelve false y el motivo si no (como la lista de addons).
local function tocLoads(toc, profile, interface)
    local allow, exclude = toc.meta.allowloadgametype, toc.meta.excludeloadgametype
    if allow and not matchesAny(allow, profile.gameTypes) then
        return false, "AllowLoadGameType: " .. allow .. " no incluye " .. table.concat(profile.gameTypes, "/")
    end
    if exclude and matchesAny(exclude, profile.gameTypes) then
        return false, "ExcludeLoadGameType: " .. exclude .. " excluye " .. table.concat(profile.gameTypes, "/")
    end
    local declared = toc.meta.interface
    if declared and not tokenSet(declared)[tostring(interface)] then
        return false, "Interface " .. declared .. " no coincide con el cliente (" .. interface .. "): desactualizado"
    end
    return true
end

-- Entorno ----------------------------------------------------------------------------------------
-- opts (todas opcionales):
--   client          perfil: "forever" (defecto), "forever_renamed", "retail", "classic_era"
--   build           { versión, número, fecha, interface } en lugar del del perfil
--   tocVars         { Game =, Family = } en lugar de las del perfil
--   expandMetadata  false = el cliente NO expande [Game]/[Family] en los metadatos (## X-Game)
--   secrets         false = UnitHealth devuelve números normales (por defecto, lo del perfil)
--   locale          "enUS" por defecto; gameMode, preset, rules = { [id de Enum.GameRule] = true }
--   health          { player = { actual, máximo } }; secretMaxHealth = true -> UnitHealthMax secreto
--   addons          { { name =, loaded =, version = } } para C_AddOns.GetNumAddOns/GetAddOnInfo
--   names           { player = { "Nombre", "Apellido" }, target = { "Otro" } } para UnitName y
--                   UnitNameUnmodified (por defecto, el `player` del perfil); realm = GetRealmName()
--   guids           { player = "Player-...", target = ... } para UnitGUID (player tiene uno ficticio)
--   secretIdentity  { target = true } -> UnitName/UnitNameUnmodified/UnitGUID de esa unidad, secretos
--   regionalNames   true/false en lugar del valor del perfil (RegionalUniqueNamesEnabled)
--   time            valor inicial de GetTime() (1000); C_Timer y GetTime avanzan con env:Advance
--   globals         globales extra o sustituidas; absent = { "NOMBRE" } quita globales del perfil
--   patch           { ["Modules/HealthBar.lua"] = function(source) return source2 end } (mutaciones)
function M.new(opts)
    opts = opts or {}
    local profile = PROFILES[opts.client or "forever"]
    if not profile then
        error("perfil de cliente desconocido: " .. tostring(opts.client), 2)
    end
    local build = opts.build or profile.build
    local vars = { TextLocale = opts.locale or "enUS" }
    for k, v in pairs(opts.tocVars or profile.tocVars) do
        vars[k] = v
    end
    local secretsOn = profile.secrets
    if opts.secrets ~= nil then
        secretsOn = opts.secrets
    end

    -- Estado privado: nada de esto es visible para el addon como global.
    local state = {
        widgets = {},
        printed = {},
        missing = {},
        expectedNil = {},
        created = {},
        loaded = {},
        meta = {},
        restriction = {},
        dispatchingRestriction = false,
        combat = false,
        health = opts.health or {},
        time = opts.time or 1000,
        timers = {},
        timerSeq = 0,
    }
    local env = {}

    -- Lua de WoW: biblioteca estándar de Lua 5.1 sin io/os/debug/require/loadfile/setfenv.
    -- stylua: ignore start
    local std = {
        assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, pcall = pcall,
        select = select, tostring = tostring, unpack = unpack, xpcall = xpcall, rawequal = rawequal,
        rawget = rawget, rawset = rawset, setmetatable = setmetatable, getmetatable = getmetatable,
        loadstring = loadstring, collectgarbage = collectgarbage,
        math = math, string = string, table = table, coroutine = coroutine, bit = rawget(_G, "bit"),
        format = string.format, strfind = string.find, strmatch = string.match, strsub = string.sub,
        strlen = string.len, strlower = string.lower, strupper = string.upper, strrep = string.rep,
        strbyte = string.byte, strchar = string.char, gsub = string.gsub, gmatch = string.gmatch,
        tinsert = table.insert, tremove = table.remove, sort = table.sort,
        floor = math.floor, ceil = math.ceil, max = math.max, min = math.min, abs = math.abs,
        date = os.date, time = os.time,
    }
    -- stylua: ignore end
    for k, v in pairs(Secret.api()) do -- issecretvalue, type, tonumber, strjoin... con secretos
        std[k] = v
    end

    local absent = {}
    for _, name in ipairs(profile.absent or {}) do
        absent[name] = true
    end
    for _, name in ipairs(opts.absent or {}) do
        absent[name] = true
    end

    env._G = env

    function env:_NewWidget(kind, name, parent, template)
        local w = newWidget(self, kind, name, parent, template)
        state.widgets[#state.widgets + 1] = w
        if name then
            rawset(self, name, w) -- los marcos con nombre son globales, como en el cliente
        end
        return w
    end

    -- Funciones de utilidad de FrameXML que usan muchos addons.
    local G = {}
    -- stylua: ignore start
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    G.strsplit = function(sep, s, limit)
        local out, pos, n = {}, 1, 0
        while true do
            n = n + 1
            local a, b = s:find("[" .. sep:gsub("[%%%]%^%-]", "%%%0") .. "]", pos)
            if not a or (limit and n >= limit) then out[n] = s:sub(pos) break end
            out[n] = s:sub(pos, a - 1)
            pos = b + 1
        end
        return unpack(out, 1, n)
    end
    G.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
    G.CopyTable = function(t)
        local copy = {}
        for k, v in pairs(t) do copy[k] = type(v) == "table" and G.CopyTable(v) or v end
        return copy
    end
    G.Mixin = function(object, ...)
        for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do object[k] = v end end
        return object
    end
    G.CreateFromMixins = function(...) return G.Mixin({}, ...) end
    local function pack(...) return { n = select("#", ...), ... } end
    G.hooksecurefunc = function(tbl, name, hook) -- el gancho corre después y no cambia el resultado
        if type(tbl) == "string" then tbl, name, hook = env, tbl, name end
        local original = tbl[name]
        tbl[name] = function(...) local r = pack(original(...)) hook(...) return unpack(r, 1, r.n) end
    end
    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = Secret.describe((select(i, ...))) end
        state.printed[#state.printed + 1] = table.concat(parts, " ")
    end
    G.GetTime = function() return state.time end

    -- Identidad del cliente.
    G.GetBuildInfo = function() return build[1], build[2], build[3], build[4] end
    G.GetLocale = function() return opts.locale or "enUS" end
    G.Enum = {
        AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
        AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
        GameMode = { Standard = 1, Plunderstorm = 2, WoWHack = 3 },
        ForeverExperiencePreset = { Classic = 0, Modern = 1 },
        GameRule = { HardcoreRuleset = 10, UserAddonsDisabled = 29, PvPRuleset = 213, RPRuleset = 214 },
    }
    G.C_GameRules = {
        GetActiveGameMode = function() return opts.gameMode or 1 end, -- Standard: inferencia sin cliente
        GetForeverExperiencePreset = function() return opts.preset end,
        IsGameRuleActive = function(rule) return (opts.rules or {})[rule] == true end,
        IsHardcoreActive = function() return (opts.rules or {})[10] == true end,
        IsSelfFoundAllowed = function() return false end,
    }
    G.C_Secrets = { HasSecretRestrictions = function() return secretsOn end }
    G.C_RestrictedActions = {
        -- Documentación: "always return false during dispatch of ADDON_RESTRICTION_STATE_CHANGED".
        IsAddOnRestrictionActive = function(k)
            return not state.dispatchingRestriction and state.restriction[k] == 2
        end,
        GetAddOnRestrictionState = function(k) return state.restriction[k] or 0 end,
    }
    G.InCombatLockdown = function() return state.combat end
    -- Montura, modificadores y facción (RutaMisiones: velocidad y Mayús para el modo manual).
    G.IsMounted = function() return state.mounted or false end
    G.GetUnitSpeed = function() return 0, state.runSpeed or 7, 0, 0 end
    G.IsShiftKeyDown = function() return state.shift or false end
    G.UnitFactionGroup = function() return opts.faction or "Horde", opts.faction or "Horde" end
    G.C_ChatInfo = { InChatMessagingLockdown = function() return state.restriction[5] == 2 end }
    G.C_CVar = { GetCVar = function(name) return (opts.cvars or {})[name] or "0" end }
    G.GetRealmName = function() return opts.realm or "Forever PvP" end -- valor ficticio
    G.GetCurrentRegionName = function() return opts.region or "" end -- "" en la beta (informe 05)

    -- Identidad del personaje (forever.md §9). En Forever el 2.º retorno de UnitName es el APELLIDO.
    -- Para "player" nada es secreto (inferencia); opts.secretIdentity hace secreta otra unidad.
    local function identity(unit, ...)
        if (opts.secretIdentity or {})[unit] then
            local n, out = select("#", ...), { ... }
            for i = 1, n do
                if out[i] ~= nil then out[i] = Secret.wrap(out[i]) end
            end
            return unpack(out, 1, n)
        end
        return ...
    end
    local function nameOf(unit)
        local entry = (opts.names or {})[unit]
        if entry == nil and unit == "player" then entry = profile.player end
        if entry then return identity(unit, entry[1], entry[2]) end
        return nil
    end
    G.UnitName = nameOf
    G.UnitNameUnmodified = nameOf
    G.UnitGUID = function(unit)
        local guid = (opts.guids or {})[unit]
        if guid == nil and unit == "player" then guid = "Player-5827-0ABCDEF1" end -- valor ficticio
        if guid == nil then return nil end
        return identity(unit, guid)
    end
    G.RegionalUniqueNamesEnabled = function()
        if opts.regionalNames ~= nil then return opts.regionalNames end
        return profile.regionalNames == true
    end
    G.GetNormalizedRealmName = function() return ((opts.realm or "Forever PvP"):gsub("[%s%-]", "")) end

    -- C_Timer falso (UITimerDocumentation.lua): nada se dispara hasta env:Advance(segundos), que
    -- avanza también GetTime(). After llama a callback(); NewTimer y NewTicker, a callback(handle),
    -- y su handle tiene Cancel() e IsCancelled(). Un ticker que agota sus iteraciones no queda
    -- cancelado (como la versión Lua antigua de C_TimerAugment; INFERENCIA para el cliente actual).
    local function newHandle()
        local handle = { _cancelled = false }
        function handle:Cancel() self._cancelled = true end
        function handle:IsCancelled() return self._cancelled end
        return handle
    end
    local function schedule(api, seconds, callback, handle, interval, iterations)
        if type(seconds) ~= "number" or type(callback) ~= "function" then
            error("Usage: C_Timer." .. api .. "(seconds, callback): argumentos no válidos", 3)
        end
        state.timerSeq = state.timerSeq + 1
        state.timers[#state.timers + 1] = { due = state.time + math.max(seconds, 0), seq = state.timerSeq,
            callback = callback, handle = handle, interval = interval, remaining = iterations }
    end
    G.C_Timer = {
        After = function(seconds, callback) schedule("After", seconds, callback) end,
        NewTimer = function(seconds, callback)
            local handle = newHandle()
            schedule("NewTimer", seconds, callback, handle)
            return handle
        end,
        NewTicker = function(seconds, callback, iterations)
            local handle = newHandle()
            schedule("NewTicker", seconds, callback, handle, math.max(seconds, 0), iterations)
            return handle
        end,
    }
    G.C_AddOns = {
        -- Metadatos del addon cargado (claves sin distinguir mayúsculas) o de opts.addons.
        GetAddOnMetadata = function(addon, field)
            if addon == state.addonName then return state.meta[tostring(field):lower()] end
            for i, a in ipairs(opts.addons or {}) do
                if addon == i or addon == a.name then
                    return tostring(field):lower() == "version" and a.version or nil
                end
            end
            return nil
        end,
        GetNumAddOns = function() return #(opts.addons or {}) end,
        GetAddOnInfo = function(i)
            local a = (opts.addons or {})[i]
            if a then return a.name, a.name, "", true, nil, "INSECURE" end
        end,
        IsAddOnLoaded = function(i)
            local a = (opts.addons or {})[i]
            return (a and a.loaded) or false, (a and a.loaded) or false
        end,
    }
    -- UnitHealth: SecretReturns = True (siempre secreto). UnitHealthMax: secreto según predicado.
    local function healthOf(unit) return state.health[unit] or { 100, 100 } end
    G.UnitHealth = function(unit)
        local value = healthOf(unit)[1]
        if secretsOn then return Secret.wrap(value) end
        return value
    end
    G.UnitHealthMax = function(unit)
        local value = healthOf(unit)[2]
        if secretsOn and opts.secretMaxHealth then return Secret.wrap(value) end
        return value
    end
    G.AbbreviateNumbers = function(n) -- AllowedWhenTainted; formato simplificado (sin K/M)
        if Secret.is(n) then return Secret.wrap(tostring(Secret.reveal(n))) end
        return tostring(n)
    end
    G.CreateFrame = function(kind, name, parent, template)
        return env:_NewWidget(kind, name, parent, template)
    end
    -- stylua: ignore end

    -- Las funciones del cliente (las de G que no son utilidades Lua) rechazan secretos salvo las
    -- de la lista blanca. Las tablas C_* se envuelven función a función.
    local LUA_HELPERS = {
        wipe = true,
        strtrim = true,
        strsplit = true,
        tContains = true,
        CopyTable = true,
        Mixin = true,
        CreateFromMixins = true,
        hooksecurefunc = true,
        print = true,
    }
    for name, value in pairs(G) do
        if type(value) == "function" and not LUA_HELPERS[name] then
            value = guardApi(name, value)
        elseif type(value) == "table" and name:match("^C_") then
            for fname, fn in pairs(value) do
                value[fname] = guardApi(name .. "." .. fname, fn)
            end
        end
        rawset(env, name, value)
    end

    for name, value in pairs(profile.globals) do
        rawset(env, name, value)
    end
    local Settings, settingsRegistry = newSettings(state)
    rawset(env, "Settings", Settings)
    rawset(env, "MinimalSliderWithSteppersMixin", {
        Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 }, -- EnumUtil.MakeEnum del clon
    })
    rawset(env, "SlashCmdList", {})
    env:_NewWidget("Frame", "UIParent")
    env:_NewWidget("GameTooltip", "GameTooltip", env.UIParent):Hide()
    local chat = env:_NewWidget("MessageFrame", "DEFAULT_CHAT_FRAME", env.UIParent)
    function chat:AddMessage(text)
        state.printed[#state.printed + 1] = Secret.describe(text)
    end
    for name in pairs(absent) do
        rawset(env, name, nil)
    end
    for k, v in pairs(opts.globals or {}) do
        rawset(env, k, v)
    end

    -- API para los tests -----------------------------------------------------------------------

    -- Carga un fichero .lua (o sigue los <Script file>/<Include file> de un .xml) en el entorno.
    -- `path` relativo a la carpeta del addon, con / o \. opts.patch puede modificar su código.
    function env:LoadFile(path, addonName, ns)
        path = path:gsub("\\", "/"):gsub("^%./", "")
        if path:match("%.xml$") then -- no crea los marcos del XML: solo sigue Script e Include
            local dir = path:match("^(.*)/") or "."
            local f = io.open(path, "r")
            if not f then
                error("el TOC lista " .. path .. " pero el fichero no existe", 2)
            end
            local xml = f:read("*a")
            f:close()
            state.loaded[#state.loaded + 1] = path
            for tag, file in xml:gmatch('<(%a+)%s+file="([^"]+)"') do
                if tag == "Script" or tag == "Include" then
                    self:LoadFile(dir .. "/" .. expandVariables(file, vars, true), addonName, ns)
                end
            end
            return
        end
        local f = io.open(path, "rb")
        if not f then
            error("el TOC lista " .. path .. " pero el fichero no existe", 2)
        end
        local source = f:read("*a"):gsub("^\239\187\191", "")
        f:close()
        local patch = opts.patch and opts.patch[path]
        if patch then
            source = patch(source)
        end
        local chunk, err = loadstring(source, "@" .. path)
        if not chunk then
            error(err, 0)
        end
        setfenv(chunk, self)
        chunk(addonName, ns)
        state.loaded[#state.loaded + 1] = path
    end

    -- Carga un addon a partir de su TOC, como el cliente del perfil. Devuelve la tabla privada
    -- (ns) o, si el cliente no cargaría el addon, nil y el motivo.
    -- loadOpts: force = true (carga aunque el TOC lo excluya: código multi-versión),
    --           only = { "Detect.lua" } (solo esos ficheros), addonName = "Otro".
    function env:LoadToc(tocPath, loadOpts)
        loadOpts = loadOpts or {}
        local dir = tocPath:match("^(.*)[/\\]")
        local toc = parseToc(tocPath, profile, vars, opts.expandMetadata ~= false)
        state.meta = toc.meta
        state.addonName = loadOpts.addonName or (tocPath:match("([^/\\]+)%.toc$"):gsub("[_%-]%a+$", ""))
        state.files = toc.files
        local ok, reason = tocLoads(toc, profile, build[4])
        if not ok and not loadOpts.force then
            return nil, reason
        end
        -- Las SavedVariables son nil en el primer inicio: no cuentan como globales sin simular.
        for _, field in ipairs({ "savedvariables", "savedvariablespercharacter" }) do
            for name in (toc.meta[field] or ""):gmatch("[%w_]+") do
                state.expectedNil[name] = true
            end
        end
        local only
        if loadOpts.only then
            only = {}
            for _, file in ipairs(loadOpts.only) do
                only[file] = true
            end
        end
        local ns = loadOpts.ns or {}
        state.ns = ns
        for _, file in ipairs(toc.files) do
            if not only or only[file] then
                self:LoadFile(dir and (dir .. "/" .. file) or file, state.addonName, ns)
            end
        end
        return ns
    end

    -- Dispara un evento a todos los marcos que lo tienen registrado (en el orden de creación).
    function env:Fire(event, ...)
        local snapshot = { unpack(state.widgets) } -- un manejador puede crear marcos nuevos
        for _, w in ipairs(snapshot) do
            local reg = w._events[event]
            local ok = reg == true
            if type(reg) == "table" then -- RegisterUnitEvent: solo las unidades registradas
                for _, unit in ipairs(reg) do
                    ok = ok or unit == (...)
                end
            end
            local handler = ok and w._scripts.OnEvent
            if handler then
                handler(w, event, ...)
            end
        end
    end

    -- Secuencia de entrada al mundo. Antes del ADDON_LOADED propio llega el de otro addon, para
    -- comprobar que el manejador filtra por nombre.
    function env:Login()
        self:Fire("ADDON_LOADED", "OtroAddon", false)
        self:Fire("ADDON_LOADED", state.addonName, false)
        self:Fire("PLAYER_LOGIN")
        self:Fire("PLAYER_ENTERING_WORLD", true, false)
    end

    -- Orden de la documentación: el evento llega ANTES de que la restricción esté activa (o
    -- después de quitarla) e IsAddOnRestrictionActive da false durante el despacho.
    -- Si pasa por Activating (1) está por comprobar en el cliente (informe 21, §8).
    function env:SetRestriction(kind, newState)
        state.restriction[kind] = newState
        state.dispatchingRestriction = true
        self:Fire("ADDON_RESTRICTION_STATE_CHANGED", kind, newState)
        state.dispatchingRestriction = false
    end

    function env:SetCombat(inCombat)
        state.combat = inCombat
        self:Fire(inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end

    function env:SetHealth(unit, current, maximum)
        local previous = state.health[unit]
        state.health[unit] = { current, maximum }
        self:Fire("UNIT_HEALTH", unit)
        if not previous or previous[2] ~= maximum then
            self:Fire("UNIT_MAXHEALTH", unit)
        end
    end

    -- Avanza el reloj simulado y dispara, en orden de vencimiento (y de creación si empatan), los
    -- temporizadores de C_Timer que venzan en ese intervalo, incluidos los que se creen durante el
    -- avance. Devuelve cuántas llamadas hizo. Los errores de un callback llegan al test.
    local function earlier(a, b)
        return b == nil or a.due < b.due or (a.due == b.due and a.seq < b.seq)
    end

    function env:Advance(seconds)
        local target = state.time + (seconds or 0)
        local fired = 0
        while true do
            local index, timer
            for i, t in ipairs(state.timers) do
                if t.due <= target and earlier(t, timer) then
                    index, timer = i, t
                end
            end
            if not timer then
                break
            end
            table.remove(state.timers, index)
            state.time = math.max(state.time, timer.due)
            local handle = timer.handle
            if not (handle and handle._cancelled) then
                fired = fired + 1
                if fired > 10000 then
                    error("C_Timer falso: más de 10000 llamadas en un Advance (¿un ticker de 0 s?)", 2)
                end
                if handle then
                    timer.callback(handle)
                else
                    timer.callback()
                end
                local remaining = timer.remaining and timer.remaining - 1
                if timer.interval and not handle._cancelled and (remaining == nil or remaining > 0) then
                    state.timerSeq = state.timerSeq + 1
                    timer.due, timer.seq, timer.remaining = timer.due + timer.interval, state.timerSeq, remaining
                    state.timers[#state.timers + 1] = timer
                end
            end
        end
        state.time = target
        return fired
    end

    -- Temporizadores pendientes (sin contar los cancelados).
    function env:PendingTimers()
        local n = 0
        for _, t in ipairs(state.timers) do
            if not (t.handle and t.handle._cancelled) then
                n = n + 1
            end
        end
        return n
    end

    -- Ejecuta código Lua en el entorno como si fuera un fichero del addon (recibe addonName y ns).
    -- Útil para probar un fragmento sin añadirlo al TOC.
    function env:LoadString(source, chunkName, addonName, ns)
        local chunk, err = loadstring(source, "@" .. (chunkName or "fragmento.lua"))
        if not chunk then
            error(err, 2)
        end
        setfenv(chunk, self)
        return chunk(addonName or state.addonName, ns or state.ns or {})
    end

    -- Ejecuta un comando de chat ("/rutamisiones reset confirm") con el manejador registrado.
    function env:RunSlash(text)
        local cmd, rest = text:match("^(/%S+)%s*(.-)$")
        for key, fn in pairs(rawget(self, "SlashCmdList")) do
            local i = 1
            while rawget(self, "SLASH_" .. key .. i) do
                if rawget(self, "SLASH_" .. key .. i):lower() == cmd:lower() then
                    return fn(rest, nil)
                end
                i = i + 1
            end
        end
        error("comando no registrado: " .. tostring(cmd), 2)
    end

    function env:Widgets(kind, parent)
        local list = {}
        for _, w in ipairs(state.widgets) do
            if w._kind == kind and (parent == nil or w._parent == parent) then
                list[#list + 1] = w
            end
        end
        return list
    end

    -- Globales que el addon sondea a propósito y pueden ser nil (además de las del perfil).
    function env:ExpectNil(...)
        for i = 1, select("#", ...) do
            state.expectedNil[(select(i, ...))] = true
        end
    end

    function env:Printed()
        return table.concat(state.printed, "\n")
    end

    function env:ClearPrinted()
        state.printed = {}
    end

    -- Globales leídas por el addon que este cliente simulado no define (debe quedar vacía).
    function env:Missing()
        local list = {}
        for k in pairs(state.missing) do
            list[#list + 1] = k
        end
        table.sort(list)
        return list
    end

    -- Globales creadas por asignación (no incluye los marcos con nombre de CreateFrame).
    function env:CreatedGlobals()
        local list = {}
        for k in pairs(state.created) do
            list[#list + 1] = k
        end
        table.sort(list)
        return list
    end

    function env:LoadedFiles()
        return { unpack(state.loaded) }
    end

    -- Ficheros que el TOC carga en este cliente (tras filtros y variables).
    function env:TocFiles()
        return { unpack(state.files or {}) }
    end

    -- Metadato del TOC tal como lo vería el addon (nil si no existe).
    function env:TocMeta(field)
        return state.meta[field:lower()]
    end

    function env:AddonName()
        return state.addonName
    end

    -- Categorías, ajustes, controles y aperturas del panel registrados en Settings.
    function env:SettingsRegistry()
        return settingsRegistry
    end

    -- La metatabla va al final para que nada de lo anterior cuente como global creada.
    setmetatable(env, {
        __index = function(_, k)
            local v = not absent[k] and std[k] or nil
            if v == nil and not state.expectedNil[k] and not absent[k] then
                state.missing[k] = true
            end
            return v
        end,
        -- Toda global nueva que escribe el addon (o el test) queda anotada: env:CreatedGlobals().
        __newindex = function(t, k, v)
            state.created[k] = true
            rawset(t, k, v)
        end,
    })
    return env
end

-- Atajo: cliente nuevo, addon cargado desde su TOC y secuencia de login completa.
-- Falla si el cliente del perfil no cargaría el addon (usa M.new + env:LoadToc para probarlo).
function M.boot(tocPath, opts)
    local env = M.new(opts)
    local ns, reason = env:LoadToc(tocPath)
    if not ns then
        error("el addon no carga en este cliente: " .. tostring(reason), 2)
    end
    env:Login()
    return env, ns
end

return M
