"""Extrae de unas guías de subida de Forever los datos de misiones que le faltan a QuestieDB.

Uso:
    python -I -B tools/extraer_guias.py RUTA [--json SALIDA.json] [--lua GuideData.lua]
                                        [--solo-ids FICHERO]

RUTA es la carpeta del visor de guías (la que tiene Guides-Forever y Libs-Forever).

Por misión saca: título, facción, rango de niveles de la guía, condiciones de raza y clase,
punto de recogida, puntos de objetivos, punto de entrega y misiones previas probables (las que se
entregan en el mismo paso, justo antes de aceptarla: el patrón «entrega X, acepta Y» de las cadenas).
Las coordenadas van en porcentaje (0-100) sobre el UiMapID del cliente.
"""

import argparse
import collections
import json
import os
import re
import sys

ACTION_RE = re.compile(r"^\s*(accept|turnin)\s+([^#|]+?)##(\d+)")
GOTO_RE = re.compile(r"(?:^|\|)\s*goto\s+([^|]+?)\s+(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)")
QREF_RE = re.compile(r"\|q\s+(\d+)(?:/\d+)?")
ONLY_RE = re.compile(r"\|only(?:\s+if)?\s+([^|]+)")
TITLE_RE = re.compile(r'RegisterGuide\("([^"]+)"')
RANGE_RE = re.compile(r"\((\d+)-(\d+)\)\s*$")
MAP_RE = re.compile(r'\["((?:[^"\\]|\\.)+)"\]\s*=\s*\{\[0\]=(\d+)')

CLASSES = {
    "Warrior": 1, "Paladin": 2, "Hunter": 3, "Rogue": 4, "Priest": 5,
    "Shaman": 7, "Mage": 8, "Warlock": 9, "Druid": 11,
}
# Token de archivo de UnitRace (2.º retorno). Skyborne: sin verificar en el cliente.
RACES = {
    "Human": "Human", "Dwarf": "Dwarf", "Gnome": "Gnome", "NightElf": "NightElf",
    "Orc": "Orc", "Undead": "Scourge", "Scourge": "Scourge", "Tauren": "Tauren", "Troll": "Troll",
    "Skyborne": "Skyborne",
}
FACTION_RACES = {
    "A": ["Human", "Dwarf", "Gnome", "NightElf", "Skyborne"],
    "H": ["Orc", "Scourge", "Tauren", "Troll", "Skyborne"],
}
# Funciones de condición de las guías: las que dependen del estado se dan por ciertas (no restringen),
# salvo hardcore() (la ruta no es para Hardcore).
FUNC_FALSE = {"hardcore"}

GUIDE_FILES = [
    ("Leveling", "Alliance", "A"),
    ("Leveling", "Horde", "H"),
    ("Leveling", "Common", None),
    ("Dungeons", "DungeonAlliance", "A"),
    ("Dungeons", "DungeonHorde", "H"),
]


def load_maps(root):
    path = os.path.join(root, "Libs-Forever", "LibRover-1.0", "data.lua")
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    maps = {}
    for name, map_id in MAP_RE.findall(text):
        maps[name.replace("\\'", "'")] = int(map_id)
    maps.setdefault("Hilsbrad Foothills", maps.get("Hillsbrad Foothills"))  # errata de las guías
    return maps


def parse_goto(line, maps):
    m = GOTO_RE.search(line)
    if not m:
        return None, False
    zone = m.group(1).strip()
    zone = zone.split("/")[0].strip()
    map_id = maps.get(zone)
    if map_id is None:
        return None, True
    return {"m": map_id, "x": round(float(m.group(2)), 2), "y": round(float(m.group(3)), 2)}, True


def eval_condition(expr, race, cls):
    """Evalúa una condición |only de la guía para una combinación raza/clase."""
    expr = expr.strip()
    expr = re.sub(r"(\w+)\s*\([^)]*\)", lambda m: "False" if m.group(1) in FUNC_FALSE else "True", expr)
    tokens = re.findall(r"\(|\)|[A-Za-z_']+", expr)
    out = []
    prev_atom = False
    for tok in tokens:
        if tok in ("(", ")"):
            if tok == "(" and prev_atom:
                out.append("and")
            out.append(tok)
            prev_atom = tok == ")"
            continue
        low = tok.lower()
        if low in ("and", "or", "not"):
            out.append(low)
            prev_atom = False
            continue
        if tok in ("True", "False"):
            value = tok
        elif tok in CLASSES:
            value = str(cls == tok)
        elif tok in RACES:
            value = str(race == RACES[tok])
        else:
            value = "True"  # desconocido (walking, subzone…): no restringe
        if prev_atom:
            out.append("and")  # "Human Warlock" = Human and Warlock
        out.append(value)
        prev_atom = True
    if not out:
        return True
    try:
        return bool(eval(" ".join(out), {"__builtins__": {}}, {}))
    except Exception:
        return True


def restriction(alternatives, faction):
    """Razas y clases permitidas (None = todas). `alternatives` es una lista de listas de
    condiciones: una por cada paso donde se acepta la misión; basta con cumplir una."""
    if not alternatives or any(not c for c in alternatives):
        return None, None
    races = FACTION_RACES.get(faction) or sorted(set(FACTION_RACES["A"] + FACTION_RACES["H"]))
    ok = set()
    for race in races:
        for cls in CLASSES:
            if any(all(eval_condition(c, race, cls) for c in conds) for conds in alternatives):
                ok.add((race, cls))
    allowed_races = sorted({r for r, _ in ok})
    allowed_classes = sorted({CLASSES[c] for _, c in ok})
    return (
        None if len(allowed_races) == len(races) else allowed_races,
        None if len(allowed_classes) == len(CLASSES) else allowed_classes,
    )


def split_guides(text):
    """(título, cuerpo) de cada RegisterGuide."""
    parts = []
    for m in TITLE_RE.finditer(text):
        start = text.find("[[", m.end())
        end = text.find("]]", start)
        if start < 0 or end < 0:
            continue
        parts.append((m.group(1), text[start + 2:end]))
    return parts


def split_steps(body):
    steps, current = [], None
    for line in body.splitlines():
        if line.strip() == "step":
            current = []
            steps.append(current)
        elif current is not None:
            current.append(line)
    return steps


def merge_point(lst, point):
    if point and point not in lst:
        lst.append(point)


def extract(root):
    maps = load_maps(root)
    guides_dir = os.path.join(root, "Guides-Forever")
    quests = {}
    unknown_zones = set()
    members = {"A": {}, "H": {}}  # facción -> {questID: (lo, hi)} de las guías de subida y mazmorras
    zones = []  # (facción, lo, hi, Counter de mapas de recogida) de cada guía de subida con tramo

    def entry_for(qid, title, faction, lo, hi):
        e = quests.setdefault(qid, {"id": qid, "t": title, "f": set(), "lo": lo, "hi": hi,
                                    "cond": [], "p": None, "o": [], "e": None, "a": set()})
        if faction:
            e["f"].add(faction)
        if lo is not None and (e["lo"] is None or lo < e["lo"]):
            e["lo"] = lo
        if hi is not None and (e["hi"] is None or hi > e["hi"]):
            e["hi"] = hi
        return e

    for folder, tag, faction in GUIDE_FILES:
        base = os.path.join(guides_dir, folder)
        names = [n for n in sorted(os.listdir(base)) if tag in n and n.endswith("CLASSIC.lua")] \
            if os.path.isdir(base) else []
        if not names:
            continue
        path = os.path.join(base, names[0])
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        for title, body in split_guides(text):
            rng = RANGE_RE.search(title)
            lo, hi = (int(rng.group(1)), int(rng.group(2))) if rng else (None, None)
            pickup_maps = collections.Counter()
            # Las guías de inicio (desde nivel 1) son por raza: no sirven para elegir la siguiente zona.
            if folder == "Leveling" and lo is not None and lo > 1:
                zones.append((faction, lo, hi, pickup_maps))
            for step in split_steps(body):
                step_conditions = []
                step_goto = None
                turned_in = []
                pending = []  # (kind, line, qid, title, conditions, point)
                for line in step:
                    stripped = line.strip()
                    if stripped.startswith("|only"):
                        m = ONLY_RE.search(stripped)
                        if m:
                            step_conditions.append(m.group(1))
                        continue
                    point, had_goto = parse_goto(stripped, maps)
                    if had_goto and point is None:
                        unknown_zones.add(GOTO_RE.search(stripped).group(1))
                    if stripped.startswith("goto ") and point:
                        step_goto = point
                        for item in pending:
                            if item[5] is None:
                                item[5] = point
                        continue
                    inline = [m.group(1) for m in ONLY_RE.finditer(stripped)]
                    action = ACTION_RE.match(stripped)
                    if action:
                        pending.append([action.group(1), stripped, int(action.group(3)),
                                        action.group(2).strip(), inline, point or step_goto])
                        continue
                    q = QREF_RE.search(stripped)
                    if q and not stripped.startswith("|"):
                        pending.append(["obj", stripped, int(q.group(1)), None, inline, point or step_goto])
                for kind, _, qid, qtitle, inline, point in pending:
                    conditions = step_conditions + inline
                    if kind == "accept":
                        e = entry_for(qid, qtitle, faction, lo, hi)
                        if e["p"] is None and point:
                            e["p"] = point
                        if conditions not in e["cond"]:
                            e["cond"].append(conditions)
                        e["a"].update(p for p in turned_in if p != qid)
                        if point:
                            pickup_maps[point["m"]] += 1
                        if lo is not None:
                            for fac in ([faction] if faction else ["A", "H"]):
                                old = members[fac].get(qid)
                                members[fac][qid] = (min(lo, old[0]), max(hi, old[1])) if old else (lo, hi)
                    elif kind == "turnin":
                        e = entry_for(qid, qtitle, faction, lo, hi)
                        if e["e"] is None and point:
                            e["e"] = point
                        turned_in.append(qid)
                    else:
                        e = quests.get(qid)
                        if e is not None:
                            merge_point(e["o"], point)
    out = {}
    for qid, e in quests.items():
        faction = None
        if len(e["f"]) == 1:
            faction = next(iter(e["f"]))
        races, classes = restriction(e["cond"], faction)
        out[qid] = {
            "t": e["t"], "f": faction, "lo": e["lo"], "hi": e["hi"],
            "r": races, "c": classes, "p": e["p"], "o": e["o"][:6], "e": e["e"],
            "a": sorted(a for a in e["a"] if a in quests),
        }
    route = {"A": [], "H": []}
    for faction, lo, hi, counter in zones:
        total = sum(counter.values())
        if not total:
            continue
        top = [m for m, n in counter.most_common() if n >= max(3, total * 0.2)][:2] or [counter.most_common(1)[0][0]]
        for fac in ([faction] if faction else ["A", "H"]):
            for m in top:
                route[fac].append((m, lo, hi))
    return out, sorted(unknown_zones), {"members": members, "route": route}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_point(p):
    return "{%d,%s,%s}" % (p["m"], ("%g" % p["x"]), ("%g" % p["y"]))


def order_lua(extra):
    """Zonas por tramo de nivel, en el orden de las guías, por facción."""
    lines = []
    lines.append("-- Zonas por tramo de nivel, en el orden de las guías: { mapa, nivel mínimo, nivel máximo }.")
    lines.append("ns.GuideZones = {")
    for fac in ("A", "H"):
        lines.append("    %s = {" % fac)
        for m, lo, hi in extra["route"][fac]:
            lines.append("        { %d, %d, %d }," % (m, lo, hi))
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def to_lua(data):
    lines = [
        "-- Datos de misiones de guías de subida de Forever. Generado por tools/extraer_guias.py: no editar a mano.",
        "-- [id] = { t=título, f=facción, lo/hi=niveles de la guía, r=razas, c=clases,",
        "--          p=recogida {mapa,x,y}, o=objetivos {{mapa,x,y}}, e=entrega, a=previas }",
        "local _, ns = ...",
        "ns.GuideData = {",
    ]
    for qid in sorted(data):
        e = data[qid]
        parts = ["t=" + lua_str(e["t"])]
        if e["f"]:
            parts.append('f="%s"' % e["f"])
        if e["lo"] is not None:
            parts.append("lo=%d,hi=%d" % (e["lo"], e["hi"]))
        if e["r"]:
            parts.append("r={" + ",".join(lua_str(r) for r in e["r"]) + "}")
        if e["c"]:
            parts.append("c={" + ",".join(str(c) for c in e["c"]) + "}")
        if e["p"]:
            parts.append("p=" + lua_point(e["p"]))
        if e["o"]:
            parts.append("o={" + ",".join(lua_point(p) for p in e["o"]) + "}")
        if e["e"]:
            parts.append("e=" + lua_point(e["e"]))
        if e["a"]:
            parts.append("a={" + ",".join(str(a) for a in e["a"]) + "}")
        lines.append("    [%d]={%s}," % (qid, ",".join(parts)))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("guide")
    ap.add_argument("--json")
    ap.add_argument("--lua")
    ap.add_argument("--solo-ids", help="fichero con un ID por línea: solo se exportan esos")
    args = ap.parse_args()
    data, unknown, extra = extract(args.guide)
    if args.solo_ids:
        with open(args.solo_ids, encoding="utf-8") as f:
            keep = {int(x) for x in f.read().split() if x.strip().isdigit()}
        data = {k: v for k, v in data.items() if k in keep}
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({str(k): v for k, v in data.items()}, f, ensure_ascii=False, indent=0)
    if args.lua:
        with open(args.lua, "w", encoding="utf-8", newline="\n") as f:
            f.write(to_lua(data))
            f.write(order_lua(extra))
    with_p = sum(1 for v in data.values() if v["p"])
    with_e = sum(1 for v in data.values() if v["e"])
    print("misiones: %d (con recogida %d, con entrega %d)" % (len(data), with_p, with_e))
    print("en las guías: Alianza %d, Horda %d; zonas por tramo: Alianza %d, Horda %d" % (
        len(extra["members"]["A"]), len(extra["members"]["H"]), len(extra["route"]["A"]), len(extra["route"]["H"])))
    if unknown:
        print("zonas sin UiMapID: " + ", ".join(unknown), file=sys.stderr)


if __name__ == "__main__":
    main()
