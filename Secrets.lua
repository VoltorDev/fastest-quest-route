local _, ns = ...

-- Valores secretos (sistema de Midnight, activo en Forever). Un secreto se puede guardar,
-- pasar a funciones, concatenar o formatear y entregar a widgets que lo admiten
-- (StatusBar:SetValue, FontString:SetText/SetFormattedText...). NO se puede usar en
-- aritmética, comparaciones, #, como clave de tabla ni en un test booleano si es booleano.

-- En clientes sin el sistema (Classic Era antiguo), nada es secreto.
local issecretvalue = issecretvalue or function()
    return false
end

ns.IsSecret = issecretvalue

-- Devuelve el valor si se puede usar en cálculos; si es secreto, devuelve `fallback`.
function ns.Readable(value, fallback)
    if issecretvalue(value) then
        return fallback
    end
    return value
end

-- ¿Está activa ahora una restricción de addons? `restriction` es un valor de
-- Enum.AddOnRestrictionType (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat).
function ns.IsRestrictionActive(restriction)
    if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) or restriction == nil then
        return false
    end
    return C_RestrictedActions.IsAddOnRestrictionActive(restriction)
end

-- Si el build aplica secretos lo dice ns.Client.HasSecretRestrictions() (Detect.lua).
