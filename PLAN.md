# Plan — RutaMisiones

Único plan vivo del addon. Actualizado el 05-11-2026.

## Objetivo

Que Nico sepa en cada momento qué misión recoger, hacer o entregar para subir lo más rápido posible, sin pagar un
addon de guías. Pedido el 05-11-2026; el mismo día pidió que tuviera en cuenta las misiones que hacen ir y venir.

## Estado

| Pieza | Implementado | Verificado |
|---|---|---|
| Datos: API pública de QuestieDB (contrato 4), 5232 misiones, 872 nuevas de Forever (584 con dador localizado), nombres en español | Sí | Cargada la base real fuera del juego (`tools/questiedb_real.py`, emula `C_EncodingUtil`) |
| Disponibilidad (nivel, raza con máscaras > 2^32, clase, previas, exclusivas, temporada) + `IsDoable` de Questie si está | Sí | Tests con base falsa; simulación con la real |
| Planificador: inserción más barata con precedencias, cadenas, descarte por XP/h, tope de 90 min, mejora local (pasos y misiones enteras) y estabilidad | Sí | 12 tests; simulación real: Durotar 1→12 en ~2 h 48 min y Mulgore 1→10 en ~2 h 03 min (tiempos estimados, no medidos) |
| Sección «Evitar» (05-11-2026, pedida por Nico): `Planner.AvoidList` + poda final (las del diario se insertaban contra una ruta vacía y nunca se descartaban) | Sí | 3 tests nuevos; simulación real sin cambio de tiempo (Durotar 1→12 igual); en los Baldíos a nivel 16 sale «Jorn Visioceleste» (~1000 XP/h frente a ~18 000 de la ruta). **Sin ver en el cliente** |
| Clic que lleva allí (05-11-2026, pedido de Nico: «que me lleve hasta ahí automáticamente»). Mover al personaje no es posible ni admisible (funciones de movimiento protegidas; EULA 1.C.ii.2, bots). En su lugar: flecha de Blizzard + `OpenWorldMap` (fuera de combate) + TomTom con la misma llamada que usa Questie en Forever | Sí | 4 tests nuevos (mapa, combate, «Evitar», TomTom puesto/quitado y apagado). **Sin ver en el cliente**; TomTom no está instalado en este PC |
| Diario, posición, flecha (`C_Map.SetUserWaypoint` + `C_SuperTrack`), ventana, `/ruta`, opciones | Sí | 7 tests del flujo en el cliente simulado. **Sin ver en el cliente** |
| Comprobaciones fuera del juego | — | Las seis pasan (05-11-2026): luacheck, StyLua, LuaLS, `api_forever` (avisos de `UnitRace`/`UnitClass` revisados: del jugador y filtrados con `issecretvalue`), 121 tests, sin XML |

## Pendiente

1. **Primera prueba en el cliente.** Reiniciar el cliente la primera vez (addon nuevo). Con Fear Ofme:
   - `/ruta debug`: «QuestieDB: sí (contrato 4, modo baked)» y estado `ready`.
   - Que el primer paso y la flecha coincidan con algo razonable en el Valle de los Retos.
   - Que aceptar, completar y entregar avance la ruta sola en ~1 s.
   - Que no haya tirones al entrar en una zona nueva (indexa 300 misiones por fotograma).
   - Que la sección «Evitar» no recomiende abandonar algo que sí merece la pena (pasa el ratón para ver la
     comparación de XP/h); si se equivoca, anotar la misión para afinar los tiempos estimados.
   - Comprobar en Mulgore que los puntos de Questie caen en su sitio: QuestieDB ofrece `EraToForever` para
     Mulgore, Redridge, Stormwind y la Plaga del Este, pero Questie no lo aplica; si los puntos salen
     desplazados, aplicarlo en `Data:PointsOnMap` para esas cuatro zonas.
2. Velocidad con montura: hoy 7 yd/s fijas (`RutaMisionesDB.speed`). Leerla de `GetUnitSpeed` o subirla al tener
   montura.
3. Aprender misiones nuevas que QuestieDB no tiene: guardar dónde se aceptó cada una (posición del jugador en
   `QUEST_ACCEPTED`) para proponerlas a otros personajes.
4. Planificar entre zonas (siguiente zona recomendada por nivel, vuelos, piedra de hogar). La guía de ExpCarry
   (consultada el 05-11-2026) da los tramos por zona de la Horda; fiabilidad baja (web de boosting), útil solo como
   pista contrastada con QuestieDB.
5. Publicar en CurseForge si funciona en el cliente (depende de Questie: decirlo en la descripción).
