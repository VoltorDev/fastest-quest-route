local addonName, ns = ...
local L = ns.L

-- Volcado para soporte: todo lo necesario para reproducir un problema en otro cliente.
function ns:PrintDiagnostics()
    local client = self.Client
    self:Print(L.DEBUG_HEADER)
    print(("  %s %s | %s"):format(addonName, self.version, GetLocale()))
    print("  " .. client.Describe())
    print(
        ("  GameMode=%s ForeverExperiencePreset=%s"):format(
            tostring(client.GetGameModeName()),
            tostring(client.GetExperiencePresetName())
        )
    )
    print("  HasSecretRestrictions=" .. tostring(client.HasSecretRestrictions()))
    if Enum.AddOnRestrictionType then
        local active = {}
        for name, value in pairs(Enum.AddOnRestrictionType) do
            if self.IsRestrictionActive(value) then
                active[#active + 1] = name
            end
        end
        print("  Restricciones activas: " .. (#active > 0 and table.concat(active, ", ") or "ninguna"))
    end
    local lib = rawget(_G, "LibQuestieDB")
    print(
        ("  QuestieDB: %s (contrato %s, modo %s)"):format(
            lib and "sí" or "no",
            tostring(lib and lib.contractVersion),
            tostring(lib and lib.readMode)
        )
    )
    local route = self.Route
    print(
        ("  Ruta: estado=%s mapa=%s pasos=%d fuera=%d ignoradas=%d"):format(
            tostring(route.status),
            tostring(route.uiMap),
            route.plan and #route.plan.steps or 0,
            #(route.offMap or {}),
            (function()
                local n = 0
                for _ in pairs(self.charDB.ignored) do
                    n = n + 1
                end
                return n
            end)()
        )
    )
    if route.plan then
        print(L.SKIPPED_HEADER:format(#route.plan.skipped))
        for i, entry in ipairs(route.plan.skipped) do
            if i > 15 then
                break
            end
            local reason = L["REASON_" .. entry.reason:upper()] or entry.reason
            print(("    %d %s — %s"):format(entry.quest.id, tostring(entry.quest.name), reason))
        end
    end
    if self.Learned then
        print("  " .. L.DEBUG_LEARNED:format(self.Learned:Count()))
    end
    print(
        ("  autoAccept=%s autoTurnIn=%s velocidad=%.1f"):format(
            tostring(self.db.autoAccept),
            tostring(self.db.autoTurnIn),
            route.Speed and route.Speed() or self.db.speed
        )
    )
    print(("  InCombatLockdown=%s"):format(tostring(InCombatLockdown())))
    for _, warning in ipairs(client.GetWarnings()) do
        print("  AVISO: " .. warning)
    end
end

local ALIASES = {
    [""] = "show",
    mostrar = "show",
    show = "show",
    recalcular = "refresh",
    refresh = "refresh",
    ignorar = "ignore",
    ignore = "ignore",
    restaurar = "unignore",
    unignore = "unignore",
    config = "config",
    opciones = "config",
    debug = "debug",
    reset = "reset",
    zonas = "zones",
    zones = "zones",
}

SLASH_RUTAMISIONES1 = "/ruta"
SLASH_RUTAMISIONES2 = "/rutamisiones"
SlashCmdList.RUTAMISIONES = function(message)
    local command, argument = message:match("^(%S*)%s*(.-)%s*$")
    command = ALIASES[command:lower()]
    if command == "show" then
        ns:ToggleFrame()
    elseif command == "refresh" then
        ns.Route:RequestUpdate()
    elseif command == "ignore" then
        local questID = tonumber(argument)
        local step = ns.Route:CurrentStep()
        if not questID and step then
            questID = step.questID
        end
        if questID then
            ns.Route:Ignore(questID)
            ns:Print(L.IGNORED:format(questID))
        end
    elseif command == "unignore" then
        ns.Route:ClearIgnored()
        ns:Print(L.UNIGNORED)
    elseif command == "config" then
        ns:OpenSettings()
    elseif command == "debug" then
        ns:PrintDiagnostics()
    elseif command == "zones" then
        local zones = ns.Route.zones
        if not zones then
            ns:Print(L.ZONES_PENDING)
        elseif #zones == 0 then
            ns:Print(L.ZONES_NONE)
        else
            ns:Print(L.ZONES_HEADER)
            for i, zone in ipairs(zones) do
                print(L.ZONES_LINE:format(i, ns.Route.ZoneName(zone.map), zone.count, AbbreviateNumbers(zone.xp)))
            end
        end
    elseif command == "reset" then
        if argument == "confirm" or argument == "confirmar" then
            ns:ResetDB()
            ns:ApplySettings()
            ns:Print(L.RESET_DONE)
        else
            ns:Print(L.RESET_CONFIRM)
        end
    else
        ns:Print(L.SLASH_HELP)
    end
end
