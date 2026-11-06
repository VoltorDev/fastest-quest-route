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
| Aceptar y entregar solo (`AutoQuest.lua`, 05-11-2026; réplica gratis de Zygor, pedida por Nico: «ponte con todo»). Gossip y saludo antiguo, detalle (auto-accept del servidor confirmado, JcJ y objetos al jugador), progreso y recompensa (solo sin elección o con una, sin pago). Filtro: no grises ni repetibles salvo si la ruta las pide; nunca ignoradas ni de «Evitar». Mayús = manual; guarda de 5 s contra bucles | Sí | 8 tests con diálogo simulado. **Sin probar en el cliente**: que las globales del diálogo (solo en el volcado, sin documentar) respondan como en el código de Blizzard |
| Misiones aprendidas (`Learned.lua`, `Builder.BuildLearnedQuest`, pendiente 3): las que QuestieDB no tiene se guardan por cuenta (`RutaMisionesDB.learned`: recogida, punto donde se completaron, entrega, XP, nivel mínimo, facción, clases) y se proponen a otros personajes | Sí | 5 tests (flujo de dos personajes y filtros). **Sin probar en el cliente**: `C_QuestLog.GetLogIndexForQuestID` en `QUEST_ACCEPTED` y que el diario ya tenga el título en ese momento |
| Velocidad con montura (pendiente 2): `GetUnitSpeed` (runSpeed) si `IsMounted()`, filtrada con `issecretvalue`; recalcula en `PLAYER_MOUNT_DISPLAY_CHANGED` | Sí | 1 test. **Sin probar en el cliente** el valor real de runSpeed montado |
| Siguiente zona (pendiente 2, parte 1): `Data:IndexAllStep` (una pasada para todos los mapas, rellena el índice por mapa), `Data:RecommendZones` (XP disponible ±2 niveles, `IsAvailable`, dador amistoso por `friendlyToFaction`), línea en la ventana con ≤3 pasos y `/ruta zonas` | Sí | 2 tests; con la QuestieDB real (scratch, 05-11-2026): indexa 5232 misiones en 18 trozos de 300 (~0,1 s fuera del juego), recomendar ~3 ms; orco 12 → Baldíos, Bosque Argénteo, Tirisfal; humano 20 → Baldíos, Costa Oscura, Crestagrana. Aparece el mapa 2521 (zona nueva de Forever, misiones AH de nivel 1-4): sin nombre verificado |
| Recomendaciones raras (05-11-2026, aviso de Nico con captura: a nivel 7, primer paso «Asegurar las rutas», de nivel 11): (1) las del diario por encima del tope (`maxAbove`) y sin completar salen de la ruta con aviso en la ventana («demasiado altas»); (2) el trabajo de un objetivo sube un 25 % por nivel por encima del jugador; (3) las de objetos de botín valen lo mismo antes y después de aceptarlas (perdían la XP de muertes al entrar en el diario); (4) siguiente zona sin capitales y con las del mismo continente primero (`Route.ContinentOf`); (5) nombres del cliente (`C_QuestLog.GetTitleForQuestID`) para las misiones de Forever que QuestieDB solo trae en inglés | Sí | 6 tests nuevos. Con la QuestieDB real: orco 12 → Los Baldíos primero; humano 20 → Los Humedales, Loch Modan, Crestagrana (antes Los Baldíos el primero). Descartado: dadores de la otra facción (0 casos en la base). **Sin ver en el cliente** |
| Comprobaciones fuera del juego | — | Las seis pasan (05-11-2026, tras los arreglos de recomendaciones: 143 tests en Lua 5.1 y LuaJIT; antes, tras aceptar/entregar y aprendidas): luacheck, StyLua, LuaLS, `api_forever` (avisos de `UnitRace`/`UnitClass`/`GetUnitSpeed` revisados: del jugador y filtrados con `issecretvalue` antes de comparar), 137 tests en Lua 5.1 y LuaJIT, sin XML |

## Pendiente

1. **Primera prueba en el cliente.** Reiniciar el cliente (el TOC cambió con AutoQuest y Learned; `/reload` no carga
   ficheros nuevos). Con Fear Ofme:
   - A nivel 7 con «Asegurar las rutas» (11) y «Zalazane» (10) en el diario: que no salgan en la ruta, que la ventana
     diga «2 misiones de tu diario son demasiado altas» y que vuelvan al subir a 8 (Zalazane) y 9 (Asegurar).
   - Que las misiones nuevas salgan en español («Wayward Weapons») si el cliente ya las conoce.
   - Las misiones nuevas de Forever no traen XP en QuestieDB (usan la mediana del nivel): si el orden sigue raro,
     anotar misión, XP real cobrada y nivel.
   - `/ruta debug`: «QuestieDB: sí (contrato 4, modo baked)» y estado `ready`.
   - Que el primer paso y la flecha coincidan con algo razonable en el Valle de los Retos.
   - Que aceptar, completar y entregar avance la ruta sola en ~1 s.
   - Que no haya tirones al entrar en una zona nueva (indexa 300 misiones por fotograma).
   - Que la sección «Evitar» no recomiende abandonar algo que sí merece la pena (pasa el ratón para ver la
     comparación de XP/h); si se equivoca, anotar la misión para afinar los tiempos estimados.
   - Aceptar y entregar solo: hablar con Gornek y ver que acepta y entrega sin clics; con Mayús, que no; una
     misión con varias recompensas debe quedar abierta con el aviso en el chat.
   - Aprendidas: aceptar una misión nueva de Forever y ver `/ruta debug` → «Misiones aprendidas: 1»; con otro
     personaje en la misma zona, que aparezca como «Recoger».
   - Comprobar en Mulgore que los puntos de Questie caen en su sitio: QuestieDB ofrece `EraToForever` para
     Mulgore, Redridge, Stormwind y la Plaga del Este, pero Questie no lo aplica; si los puntos salen
     desplazados, aplicarlo en `Data:PointsOnMap` para esas cuatro zonas.
2. Planificar entre zonas: la siguiente zona ya se recomienda por XP; falta tener en cuenta el viaje (vuelos,
   piedra de hogar, continente) y no proponer capitales. La guía de ExpCarry
   (consultada el 05-11-2026) da los tramos por zona de la Horda; fiabilidad baja (web de boosting), útil solo como
   pista contrastada con QuestieDB.
3. Publicado en CurseForge: la 0.1.0 se subió el 05-11-2026 y pasó a Release ese mismo día por orden
   de Nico, sin probar en el cliente (proyecto 1785197, «Fastest Quest Route», Questie como dependencia; ver [docs/CURSEFORGE.md](docs/CURSEFORGE.md)).
   Faltan capturas.
