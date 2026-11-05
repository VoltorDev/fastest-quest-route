local _, ns = ...

-- Identidad del personaje (references/forever.md §9.3-9.4). Forever usa "Nombre Apellido", sin reino
-- y único por región; retail y Classic, "Nombre-Reino". Se decide por capacidad
-- (RegionalUniqueNamesEnabled), no por versión. Usa estas funciones desde PLAYER_LOGIN: antes, el
-- nombre puede llegar como "Unknown" (pasaba hasta la build 70170).
--   GetPlayerFullName()  nombre para mostrar y comunicarse ("Nombre Apellido" / "Nombre-Reino")
--   GetCharacterKey()    clave de SavedVariables, mismo texto que el charKey de AceDB-3.0 MINOR 39
--   GetRuleset()         "Hardcore", "RP", "PvP" o "PvE" (nil si el cliente no tiene reglas de juego)
--   NormalizeSender(s)   remitente de CHAT_MSG_ADDON/WHISPER en la forma de GetPlayerFullName()
--   IsMe(s)              ¿ese remitente soy yo?
--   GetCharEntry(db)     entrada db.chars[clave], con migración por GUID (renombrado o clave antigua)
local Identity = {}
ns.Identity = Identity

local SEP = Constants and Constants.CharacterNameSeparatorConsts
local SURNAME_SEP = SEP and SEP.CHARACTERNAME_SURNAME_SEPARATOR or " "
local REALM_SEP = SEP and SEP.CHARACTERNAME_REALMNAME_SEPARATOR or "-"
local REALM_SUFFIX = "^(.-)" .. REALM_SEP:gsub("%p", "%%%0") -- "Nombre Apellido-Reino" -> "Nombre Apellido"
local GetUnmodifiedName = UnitNameUnmodified or UnitName
local issecret = issecretvalue or function()
    return false
end

-- Un nombre solo sirve si no es secreto y es una cadena no vacía.
local function Usable(value)
    return value ~= nil and not issecret(value) and type(value) == "string" and value ~= ""
end

function Identity.UsesRegionalNames()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

-- Nombre para mostrar y comunicarse. nil si el nombre aún no se puede leer.
function Identity.GetPlayerFullName()
    local name, second = GetUnmodifiedName("player")
    if not Usable(name) then
        return nil
    end
    if Identity.UsesRegionalNames() then -- el 2.º retorno es el apellido, no el reino
        if Usable(second) and not name:find(SURNAME_SEP, 1, true) then
            return name .. SURNAME_SEP .. second
        end
        return name
    end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return Usable(realm) and (name .. REALM_SEP .. realm) or name
end

-- Ruleset en el orden de AceDB 39. Enum.GameRule solo está en el volcado del cliente: se lee por nombre.
local RULESETS = { { "HardcoreRuleset", "Hardcore" }, { "RPRuleset", "RP" }, { "PvPRuleset", "PvP" } }

function Identity.GetRuleset()
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule) then
        return nil
    end
    for _, entry in ipairs(RULESETS) do
        local rule = Enum.GameRule[entry[1]]
        if rule and C_GameRules.IsGameRuleActive(rule) then
            return entry[2]
        end
    end
    return "PvE"
end

-- Clave de SavedVariables: mismo texto que el charKey de AceDB-3.0 MINOR 39 (" " y " - " literales).
function Identity.GetCharacterKey()
    local name, second = GetUnmodifiedName("player")
    if not Usable(name) then
        return nil
    end
    if Identity.UsesRegionalNames() then
        if Usable(second) and not name:find(" ", 1, true) then
            return name .. " " .. second
        end
        return name
    end
    local realm = GetRealmName and GetRealmName()
    return Usable(realm) and (name .. " - " .. realm) or nil
end

-- Remitente de CHAT_MSG_ADDON/WHISPER en la forma de GetPlayerFullName(); nil si es secreto.
-- No convierte "Nombre-Apellido": en Forever el guion es separador de enlace o de reino.
-- Para responder usa el remitente LITERAL; guarda el normalizado para listas y claves.
function Identity.NormalizeSender(sender)
    if not Usable(sender) then
        return nil
    end
    if Identity.UsesRegionalNames() then
        local base = sender:match(REALM_SUFFIX)
        if base and base:find(SURNAME_SEP, 1, true) then
            return base
        end
        return sender
    end
    if sender:find(REALM_SEP, 1, true) then
        return sender
    end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return Usable(realm) and (sender .. REALM_SEP .. realm) or sender
end

function Identity.IsMe(sender)
    local who = Identity.NormalizeSender(sender)
    return who ~= nil and who == Identity.GetPlayerFullName()
end

-- Entrada por personaje dentro de la SV de cuenta (db.chars), con clave "Nombre Apellido" y el
-- ruleset y el GUID como atributos. Llámala en PLAYER_LOGIN o después; nil si el nombre no se lee.
-- Si el GUID coincide con una entrada de otra clave (renombrado, o clave de la beta o de AceDB 36-38),
-- la mueve a la clave actual. Que el GUID se conserve al renombrar es inferencia (forever.md §9.4).
function Identity.GetCharEntry(db)
    local key = Identity.GetCharacterKey()
    if not key then
        return nil
    end
    db.chars = db.chars or {}
    local chars = db.chars
    local guid = UnitGUID("player")
    if guid ~= nil and issecret(guid) then
        guid = nil
    end
    if guid and not chars[key] then
        local oldKey
        for k, entry in pairs(chars) do
            if type(entry) == "table" and entry.guid == guid then
                oldKey = k
                break
            end
        end
        if oldKey then
            chars[key], chars[oldKey] = chars[oldKey], nil
        end
    end
    local entry = chars[key] or {}
    chars[key] = entry
    entry.guid = guid or entry.guid
    entry.ruleset = Identity.GetRuleset()
    entry.lastLogin = time()
    return entry
end
