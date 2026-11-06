# Publicar RutaMisiones en CurseForge — kit

Preparado el 05-11-2026. Paquete: `mods\wow\dist\RutaMisiones-0.1.0.zip` (generado con
`python -I mods\herramientas\empaquetar-wow.py mods\wow\RutaMisiones --version 0.1.0`; pasa
`comprobar-paquete.py --juego wow`: solo `.toc`, `.lua`, `LICENSE` y `CHANGELOG.md`, sin ejecutables).

**Estado honesto:** pasa las seis comprobaciones fuera del juego (143 tests, 05-11-2026). **Sin ver en el
cliente**: ruta, flecha, aceptar y entregar solo, misiones aprendidas ([PLAN.md](../PLAN.md), pendiente 1).
Depende de Questie (trae QuestieDB): no copia datos de Questie, los consulta en el juego con su API pública. Solo
carga en Forever. Por eso se sube como **Beta**; pasarlo a Release cuando se vea en el juego.

## Campos del formulario

| Campo | Valor |
|---|---|
| Juego | World of Warcraft |
| Nombre del proyecto | `Fastest Quest Route` (la carpeta sigue siendo `RutaMisiones`) |
| Resumen | `Tells you in which order to pick up, do and turn in your quests to level faster, using Questie's database. For WoW: Forever.` |
| Categoría principal | Quests & Leveling (secundaria: Map & Minimap) |
| Licencia | MIT (está en `LICENSE`) |
| Donaciones | Ko-fi, usuario `thevoltor` (General › Donation Method) y botón bajo la introducción. Nunca dentro del addon |
| Relaciones | Questie como **Required Dependency**; TomTom como Optional Dependency |
| Versión de juego | **Forever 1.60.1** (Interface 16001). No marcar retail ni Classic |
| Tipo de fichero | Beta (ver arriba) |
| Avatar | `docs/avatar-curseforge.png` (lo dibuja `mods/herramientas/avatares_curseforge.py rutamisiones`) |
| Capturas | **Faltan**: ventana con la ruta, sección «Evitar», flecha en el mapa. Solo en el juego |

## Descripción (pegar en el editor de CurseForge)

```markdown
**Fastest Quest Route** tells you, at every moment, which quest to pick up, which objective to do and where to
turn in, in the order that gives you the most experience per hour, with the map arrow pointing at the next step.

Made for **World of Warcraft: Forever**. **Requires Questie** (it reads Questie's quest database in game).

<p align="center"><a href="https://ko-fi.com/thevoltor"><img src="https://storage.ko-fi.com/cdn/kofi6.png?v=6" alt="Buy Me a Coffee at ko-fi.com" width="145" height="36"></a><br><em>Free and always will be. If it helps you, you can buy me a coffee.</em></p>

## Features

- **Route for your current map**: looks at your quest log, level, completed quests and position, and plans the
  pick-ups, objectives and turn-ins with the most XP per hour, grouping NPCs and nearby objectives so you do not
  walk back and forth between camps.
- **Quest chains**: if turning in a quest opens another one in the same place, the route counts it ("[chain]")
  and values a weak quest that unlocks a good one.
- **Quests to avoid**: a section under the route lists quests in your log worth abandoning or leaving for later,
  and nearby ones not worth the detour, with their XP per hour compared with your route.
- **Auto accept and turn in** (optional): the quests worth doing are accepted and turned in when you talk to the
  NPC. Reward choices, payments, PvP and item-started quests are left to you. Hold **Shift** to do it by hand.
- **Learns the new Forever quests** that Questie's database does not have yet: when one of your characters does
  them, it remembers where they start, end and are turned in, and suggests them to your other characters.
- **Next zone**: when your zone runs out of steps, it suggests the zones with the most quest XP for your level and
  faction. `/ruta zonas` lists the best three.
- **Click a step** to put the Blizzard waypoint arrow there and open the map (out of combat). TomTom arrow too, if
  installed.
- Recalculates by itself when you accept, progress or turn in quests, level up or change zone; never in combat.

It never moves your character: Blizzard blocks movement from addons and the EULA treats that as a bot.

## Commands

`/ruta` shows or hides the window. `/ruta zonas`, `/ruta recalcular`, `/ruta ignorar [ID]`, `/ruta restaurar`,
`/ruta config`, `/ruta debug`. Also in the addon compartment next to the minimap.

## Limits

It is a heuristic, not an exact optimum: straight-line distances inside the map (no mountains, roads or flights),
estimated time per objective, and only the map you are in is planned. New Forever quests without XP data use the
median for their level.

## Bugs

Please report with the output of `/ruta debug` and, if there is an error, the BugSack export.

---

**Español.** Te dice en qué orden recoger, hacer y entregar las misiones del mapa para subir más rápido, con
flecha al siguiente paso, misiones a evitar, aceptar y entregar solo, misiones nuevas aprendidas entre personajes
y siguiente zona recomendada. Necesita Questie. Solo para WoW: Forever. Comando: `/ruta`.
```

## Changelog del fichero 0.1.0

```markdown
First public release (beta), for World of Warcraft: Forever. Requires Questie.

- Fastest quest route for your current map: pick-ups, objectives and turn-ins, with quest chains.
- Waypoint arrow and map on click; TomTom arrow if installed.
- "Avoid" list with the XP per hour of each quest compared with your route.
- Optional auto accept and turn in (Shift to do it by hand).
- Learns new Forever quests and suggests them to your other characters.
- Next zone suggestion (`/ruta zonas`).
```

## Subida

**Subido el 05-11-2026 hacia las 15:45 (por Claude, con la sesión de Nico en Chrome, por orden suya):** proyecto
«Fastest Quest Route», n.º **1785197** (`https://authors.curseforge.com/#/projects/1785197`), estado «New» hasta que
lo apruebe un moderador (moderación de 08:00 a 15:00, así que no antes del 06-11). Fichero «Fastest Quest Route
0.1.0», tipo **Beta** (pasado a **Release** a las 16:05 del mismo día, por orden de Nico: «Ponlo release»; changelog sin «(beta)»), versión Forever 1.60.1, publicación automática al aprobarse, changelog del kit, Questie
(ID 334372) como Required Dependency. Licencia MIT, distribución a terceros permitida, comentarios activados,
categorías Quests & Leveling + Map & Minimap, Ko-fi `thevoltor`. TomTom no se añadió como relación opcional.
Falta: capturas (solo en el juego) y verlo en el cliente.

El formulario de fichero de CurseForge no tiene `<input type=file>` en el DOM: lo crea al pulsar «Choose File».
Para subir por automatización se intercepta `HTMLInputElement.prototype.click`, se pulsa el botón y se le asigna
el zip con `DataTransfer` (el zip tiene que estar en una carpeta que la sesión pueda leer).

**0.1.1, nombre en inglés (05-11-2026, por orden de Nico: «Nombres en inglés siempre»):** el `## Title` del TOC pasa a «Fastest Quest Route» y el zip a `mods\wow\dist\FastestQuestRoute-0.1.1.zip`. Es el zip publicado anterior con solo el título y la versión cambiados (los cambios sin publicar del repo no entran); la carpeta interna sigue siendo `RutaMisiones`, así que las SavedVariables y la junction de `Interface\AddOns` no cambian. Subido como Release con las mismas versiones de juego y Questie como Required Dependency; pasa por moderación. Desde ahora `empaquetar-wow.py` nombra el zip por el `## Title`.

**0.2.0 (06-11-2026, por Claude con la sesión de Nico en Chrome, por orden suya: «Sí, súbelas»):** fichero «Fastest Quest Route 0.2.0», `mods\wow\dist\FastestQuestRoute-0.2.0.zip`, tipo **Release**, versiones Forever 1.60.1, publicación automática al aprobarse. Changelog en inglés que nombra lo nuevo: planificador calibrado con guías de subida (cadenas, entregas al pasar, objetivos solapados, campamentos); Questie sigue como Required Dependency. Pasa las comprobaciones fuera del juego (06-11-2026); **sin probar en el cliente**.
