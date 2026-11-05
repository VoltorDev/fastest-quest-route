"""Simula la ruta de RutaMisiones con la QuestieDB REAL fuera del juego.

Carga QuestieDB (tools/questiedb_real.py), después Data.lua, Builder.lua y Planner.lua del addon,
y «juega» la ruta: recoge, completa objetivos y entrega siguiendo el primer paso del plan,
replanificando tras cada paso como hace el addon. Sirve para juzgar si el orden tiene sentido.

Uso: python -I -B tools/simular_ruta.py [--mapa 1411] [--x 43.3 --y 68.5] [--nivel 1]
         [--raza 2] [--clase 9] [--pasos 40] [--hasta-nivel 10]
"""
import argparse
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import questiedb_real  # noqa: E402

ADDON = os.path.dirname(AQUI)

# Tamaños de mapa en yardas (C_Map.GetMapWorldSize en el juego). Aproximados para simular.
TAMANOS = {1411: (5287.5, 3525.0), 1412: (5137.5, 3425.0), 1420: (4518.75, 3012.5), 1413: (10133.3, 6756.2)}
# XP para pasar de nivel (Vanilla).
XP_NIVEL = [0, 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900,
            14400, 15700, 17200, 18800, 20400, 22100]

SIM = r"""
local ns, mapa, pos, player, w, h = ...
local data = ns.Data.New(LibQuestieDB)
local candidates = data:IndexStep(mapa)
local previous
local function plan(log, here)
  pos = here or pos
  local quests, offMap = ns.Builder.Build(data, {uiMap = mapa, position = pos, player = player, log = log,
      candidates = candidates})
  local result = ns.Planner.Plan(quests, {start = pos, w = w, h = h, previous = previous})
  previous = {}
  for i = 2, #result.steps do previous[#previous + 1] = result.steps[i].key end
  return result, #quests, offMap
end
return data, candidates, plan
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mapa", type=int, default=1411)
    ap.add_argument("--x", type=float, default=43.3)
    ap.add_argument("--y", type=float, default=68.5)
    ap.add_argument("--nivel", type=int, default=1)
    ap.add_argument("--raza", type=int, default=2)
    ap.add_argument("--clase", type=int, default=9)
    ap.add_argument("--pasos", type=int, default=60)
    ap.add_argument("--hasta-nivel", type=int, default=99)
    args = ap.parse_args()

    lua = questiedb_real.cargar()
    ns = lua.table()
    loader = lua.eval(b"function(code, name, ns) local f, err = loadstring(code, name); "
                      b"if not f then error(err) end; return f('RutaMisiones', ns) end")
    for f in ("Data.lua", "Builder.lua", "Planner.lua"):
        with open(os.path.join(ADDON, f), encoding="utf-8") as fh:
            loader(fh.read().encode(), ("@" + f).encode(), ns)

    E = lua.globals().LibQuestieDB.Enum
    player = lua.table()
    player.level = args.nivel
    player.raceMask = E.raceMaskById[args.raza]
    player.classMask = 2 ** (args.clase - 1)
    player.completed = lua.table()
    player.inLog = lua.table()
    player.ignored = lua.table()
    pos = lua.table()
    pos.x, pos.y = args.x, args.y
    w, h = TAMANOS.get(args.mapa, (5000.0, 3400.0))
    data, candidates, plan = lua.execute(SIM.encode(), ns, args.mapa, pos, player, w, h)
    print("Misiones con dador en el mapa %d: %d" % (args.mapa, len(candidates)))

    Q = lua.globals().LibQuestieDB.Quest
    log = lua.table()  # questID -> {title, complete, objectives}
    xp_total, xp_nivel, t = 0, 0, 0.0
    evitar_antes = None
    avoid_list = lua.eval(b"function(ns, plan) return ns.Planner.AvoidList(plan, 5) end")
    for paso in range(1, args.pasos + 1):
        resultado, n_quests, _ = plan(log, pos)
        steps = resultado.steps
        if len(steps) == 0:
            print("Sin pasos: la ruta se ha agotado en este mapa.")
            break
        evitar = [("%s%s %.0f XP/h" % ("[diario] " if e.inLog else "", (e.name or b"?").decode("utf-8", "replace"), e.xpPerHour))
                  for e in avoid_list(ns, resultado).values()]
        if evitar != evitar_antes:
            print("     Evitar: " + ("; ".join(evitar) if evitar else "(nada)"))
            evitar_antes = evitar
        s = steps[1]
        qid = s.questID
        nombre = (s.name or b"?").decode("utf-8", "replace")
        dt = s.arrive
        # Trabajo del paso: lo que el planificador presupuestó (tiempo hasta el siguiente paso).
        t += s.arrive + s.work
        pos = lua.table()
        pos.x, pos.y = s.x, s.y
        if s.kind == b"pickup":
            entrada = lua.table()
            entrada.title = s.name
            entrada.complete = False
            entrada.objectives = lua.table()
            log[qid] = entrada
            player.inLog[qid] = True
            grupos = data.ObjectiveGroups(data, qid, args.mapa)
            for g in grupos.values():
                o = lua.table()
                o.type = g.kind
                o.finished = False
                o.numRequired = g.count
                o.numFulfilled = 0
                entrada.objectives[len(entrada.objectives) + 1] = o
            if len(grupos) == 0:
                entrada.complete = True
            accion = "Recoger"
        elif s.kind == b"objective":
            entrada = log[qid]
            for o in entrada.objectives.values():
                if not o.finished and (o.type == s.label or s.label == b"poi"):
                    o.finished = True
                    o.numFulfilled = o.numRequired
                    break
            if s.label in (b"monster", b"item"):
                n = 8
                for o in entrada.objectives.values():
                    if o.type == s.label and o.numRequired:
                        n = o.numRequired
                        break
                kx = (player.level * 5 + 45) * n
                xp_total += kx
                xp_nivel += kx
                while player.level < len(XP_NIVEL) - 1 and xp_nivel >= XP_NIVEL[player.level]:
                    xp_nivel -= XP_NIVEL[player.level]
                    player.level += 1
                    print("   ** Sube a nivel %d (min %.0f)" % (player.level, t / 60))
            if all(o.finished for o in entrada.objectives.values()):
                entrada.complete = True
            accion = "Objetivo"
        else:
            log[qid] = None
            player.inLog[qid] = None
            player.completed[qid] = True
            xp = data.EstimateXP(data, qid, player.level)
            xp = xp[0] if isinstance(xp, tuple) else xp
            xp_total += xp
            xp_nivel += xp
            while player.level < len(XP_NIVEL) - 1 and xp_nivel >= XP_NIVEL[player.level]:
                xp_nivel -= XP_NIVEL[player.level]
                player.level += 1
                print("   ** Sube a nivel %d (min %.0f)" % (player.level, t / 60))
            accion = "Entregar (+%d XP)" % xp
        sys.stdout.reconfigure(encoding='utf-8')
        print("%3d. %-18s %-42s (%.1f, %.1f)  viaje %.0fs  [ruta: %d pasos, %.0f XP/h, %d candidatas]" % (
            paso, accion, nombre[:42] + (" [cadena]" if s.chained else ""), s.x, s.y, dt, len(steps), resultado.xpPerHour, n_quests))
        if player.level >= args.hasta_nivel:
            break
    print("Tiempo simulado: %.0f min, XP: %d, nivel %d" % (t / 60, xp_total, player.level))


if __name__ == "__main__":
    main()
