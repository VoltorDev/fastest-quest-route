local _, ns = ...

local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then
    return
end

local L = ns.L

L.LOADED = "cargado. Escribe /ruta para ver la ruta y /ruta ayuda para los comandos."
L.SLASH_HELP = "Comandos: /ruta [mostrar | recalcular | ignorar [ID] | restaurar | config | debug | reset]"
L.ERR_COMBAT = "No disponible en combate; inténtalo al salir de él."
L.RESET_CONFIRM = "Escribe /ruta reset confirmar para volver a los valores por defecto."
L.RESET_DONE = "Opciones restauradas a los valores por defecto."
L.COMPARTMENT_TOOLTIP = "Clic: mostrar u ocultar la ruta. Clic derecho: opciones."
L.ERR_NO_QUESTIEDB = "QuestieDB no está cargada: instala Questie (trae QuestieDB) para tener ruta."

L.OPT_ENABLED = "Activar"
L.OPT_ENABLED_TT = "Muestra u oculta todo lo que dibuja este addon."
L.OPT_SCALE = "Escala"
L.OPT_SCALE_TT = "Tamaño de la ventana de la ruta."
L.OPT_WAYPOINT = "Flecha al siguiente paso"
L.OPT_WAYPOINT_TT = "Pone el marcador de mapa de Blizzard en el siguiente paso cada vez que cambia."
L.OPT_STEPS = "Pasos visibles"
L.OPT_STEPS_TT = "Cuántos pasos de la ruta lista la ventana."
L.OPT_ABOVE = "Niveles máximos por encima"
L.OPT_ABOVE_TT = "No propone misiones nuevas de más niveles por encima de ti (+3 ya es naranja)."
L.OPT_QUESTIE = "Usar las reglas de Questie"
L.OPT_QUESTIE_TT = "Si Questie está cargado, aplica también sus listas negras"
    .. " y sus comprobaciones de reputación y profesión."

L.BUTTON_REFRESH = "Recalcular"
L.STEP_PICKUP = "Recoger"
L.STEP_OBJECTIVE = "Hacer"
L.STEP_TURNIN = "Entregar"
L.OBJ_MONSTER = "matar"
L.OBJ_ITEM = "conseguir"
L.OBJ_OBJECT = "usar"
L.OBJ_EVENT = "ir"
L.OBJ_POI = "zona"
L.CHAIN_MARK = "[cadena]"
L.SUMMARY = "%d pasos · unos %s · %s PX/h"
L.OFFMAP = "%d misiones de tu diario están fuera de este mapa."
L.EMPTY = "Aquí no queda nada rentable: cambia de zona o sube de nivel."
L.STATUS_IDLE = "Esperando al primer cálculo…"
L.STATUS_NODB = "QuestieDB no está cargada."
L.STATUS_INDEXING = "Indexando las misiones de este mapa…"
L.STATUS_NOMAP = "Aquí no hay mapa (¿estancia?)."
L.TT_ARRIVE = "Llegas en unos %s."
L.TT_CLICK = "Clic: flecha aquí. Clic derecho: ignorar esta misión."
L.IGNORED = "Ignoro «%s». /ruta restaurar devuelve las ignoradas."
L.UNIGNORED = "Misiones ignoradas restauradas."
L.NEXT = "Siguiente: %s"
L.SKIPPED_HEADER = "No compensan aquí (%d):"
L.REASON_RATE = "poca XP para lo que cuesta"
L.REASON_TIME = "no cabe en la ruta"
L.REASON_CHAIN = "su misión previa no está en la ruta"

L.DEBUG_HEADER = "Diagnóstico (pégalo al informar de un problema):"
