local addonName, ns = ...

-- Detector de cliente (Forever / retail / Classic). Carga en cualquier cliente sin errores.
-- Forever es la familia Mainline con game type "camelot", que Blizzard anunció que renombrará
-- a "forever". Por eso se aceptan los dos nombres y basta una de tres señales independientes.
-- Trampas que evita: en Forever WOW_PROJECT_ID NO es WOW_PROJECT_MAINLINE, su Interface (16001)
-- cae en la zona numérica de Classic y LE_EXPANSION_LEVEL_CURRENT vale 0, como en Classic Era.
local Client = {}
ns.Client = Client

-- WOW_PROJECT_CAMELOT solo existe en Forever (nil en el resto): se respalda con su valor, 18.
local PROJECT_FOREVER = WOW_PROJECT_FOREVER or WOW_PROJECT_CAMELOT or 18
local PROJECT_MAINLINE = WOW_PROJECT_MAINLINE or 1
local PROJECT_CLASSIC = WOW_PROJECT_CLASSIC or 2
local FOREVER_GAME_TOKENS = { camelot = true, forever = true }

-- Metadato del TOC; descarta el texto literal "[Game]" si el cliente no expande la variable.
local function Metadata(field)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getter then
        return nil
    end
    local ok, value = pcall(getter, addonName, field)
    if ok and type(value) == "string" and value ~= "" and not value:find("[", 1, true) then
        return value
    end
    return nil
end

local buildVersion, buildNumber, _, interfaceVersion = GetBuildInfo()
Client.buildVersion = buildVersion
Client.buildNumber = tonumber(buildNumber)
Client.interface = tonumber(interfaceVersion) or 0
Client.gameToken = Metadata("X-Game") -- "Camelot" hoy; "Forever" si se renombra; "Standard" en retail
Client.familyToken = Metadata("X-Family") -- "Mainline" o "Classic"
Client.tocFlavor = Metadata("X-Flavor") -- qué TOC eligió el cliente (campo propio de cada .toc)

Client.signals = {
    project = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == PROJECT_FOREVER,
    game = Client.gameToken ~= nil and FOREVER_GAME_TOKENS[Client.gameToken:lower()] == true,
    interface = Client.interface >= 16000 and Client.interface < 20000, -- banda que no usa ningún otro cliente
}
Client.isForever = Client.signals.project or Client.signals.game or Client.signals.interface
Client.isRetail = not Client.isForever and WOW_PROJECT_ID == PROJECT_MAINLINE
Client.isClassicEra = not Client.isForever and WOW_PROJECT_ID == PROJECT_CLASSIC

if Client.familyToken then
    Client.isMainlineFamily = Client.familyToken:lower() == "mainline"
else
    Client.isMainlineFamily = Client.isForever or Client.isRetail
end

if Client.isForever then
    Client.flavor = "Forever"
elseif Client.isRetail then
    Client.flavor = "Retail"
elseif Client.isClassicEra then
    Client.flavor = "ClassicEra"
else
    Client.flavor = Client.isMainlineFamily and "Mainline" or "Classic"
end

-- Eje 1, API: FrameXML y namespaces de retail 12.x (retail y Forever). Decide qué funciones llamar;
-- mejor aún, comprueba la función concreta (if C_Spell and C_Spell.GetSpellInfo then ...).
Client.hasModernAPI = Client.isMainlineFamily

-- Eje 2, restricciones de Midnight (secretos, combat log cerrado...): capacidad real del build.
function Client.HasSecretRestrictions()
    return C_Secrets ~= nil and C_Secrets.HasSecretRestrictions ~= nil and C_Secrets.HasSecretRestrictions() == true
end

-- Eje 3, contenido (0 = Vanilla). Decide qué datos de juego cargar (zonas, mazmorras, clases).
Client.contentExpansion = LE_EXPANSION_LEVEL_CURRENT
if type(Client.contentExpansion) == "number" then
    Client.hasVanillaContent = Client.contentExpansion == (LE_EXPANSION_CLASSIC or 0)
else
    Client.hasVanillaContent = Client.isForever or Client.isClassicEra
end

local function EnumName(enumTable, value)
    if enumTable == nil or value == nil then
        return nil
    end
    for name, enumValue in pairs(enumTable) do
        if enumValue == value then
            return name
        end
    end
    return tostring(value)
end

-- En Forever se espera "Standard" (inferencia): el modo de juego no distingue Forever de retail.
function Client.GetGameModeName()
    if C_GameRules and C_GameRules.GetActiveGameMode and Enum then
        return EnumName(Enum.GameMode, C_GameRules.GetActiveGameMode())
    end
    return nil
end

-- Preajuste del primer arranque ("Classic"/"Modern", en la interfaz "Classic"/"Enhanced"); puede ser nil.
-- Solo fija ajustes iniciales: para saber cómo juega el usuario, lee el ajuste concreto.
function Client.GetExperiencePresetName()
    if C_GameRules and C_GameRules.GetForeverExperiencePreset and Enum then
        return EnumName(Enum.ForeverExperiencePreset, C_GameRules.GetForeverExperiencePreset())
    end
    return nil
end

-- Señales que no cuadran: primer aviso de un renombrado o de un cambio de build.
function Client.GetWarnings()
    local warnings = {}
    if Client.isForever and not Client.signals.project then
        warnings[#warnings + 1] = ("WOW_PROJECT_ID=%s no es el esperado (18)"):format(tostring(WOW_PROJECT_ID))
    end
    if Client.isForever and not Client.signals.interface then
        warnings[#warnings + 1] = ("Interface %d fuera de la banda 16000-19999"):format(Client.interface)
    end
    if Client.isForever and Client.gameToken and Client.gameToken:lower() ~= "camelot" then
        warnings[#warnings + 1] = "[Game] ya no es Camelot: " .. Client.gameToken
    end
    if Client.isForever and Client.tocFlavor and Client.tocFlavor ~= "Forever" then
        warnings[#warnings + 1] = "el cliente cargó el TOC de " .. Client.tocFlavor .. ", no el de Forever"
    end
    return warnings
end

function Client.Describe()
    local pattern =
        "%s | %s.%s Interface %d | WOW_PROJECT_ID=%s | X-Game=%s X-Family=%s X-Flavor=%s | señales %s/%s/%s"
    return pattern:format(
        Client.flavor,
        tostring(Client.buildVersion),
        tostring(Client.buildNumber),
        Client.interface,
        tostring(WOW_PROJECT_ID),
        tostring(Client.gameToken),
        tostring(Client.familyToken),
        tostring(Client.tocFlavor),
        tostring(Client.signals.project),
        tostring(Client.signals.game),
        tostring(Client.signals.interface)
    )
end

-- Atajos usados por el resto del addon.
ns.flavor = Client.flavor
ns.interfaceVersion = Client.interface
ns.isForever = Client.isForever
ns.isRetail = Client.isRetail
ns.isClassicEra = Client.isClassicEra
ns.hasModernAPI = Client.hasModernAPI
ns.hasVanillaContent = Client.hasVanillaContent
