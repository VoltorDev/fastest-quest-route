"""Genera FlightData.lua: tiempos de vuelo medidos entre maestros de vuelo de Forever, por facción.

Uso: python -I -B tools/extraer_vuelos.py FICHERO_ORIGEN [--lua FlightData.lua]

FICHERO_ORIGEN es un .lua de datos de vuelo de Forever con la forma
    addon.FPDB = { Alliance = { [nodo] = { [destino] = segundos, ..., name = "..." } }, Horde = {...} }
Los nodos son los nodeID de C_TaxiMap. Se completa la simetría (A→B vale lo mismo que B→A si solo
consta un sentido) y se descartan los nombres: el addon los lee del cliente.
"""
import argparse
import os
import sys

import site

sys.path.insert(0, site.getusersitepackages())
import lupa.lua51 as lupa  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(AQUI)


def leer(ruta):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    with open(ruta, encoding="utf-8") as fh:
        codigo = fh.read().lstrip("﻿")
    addon = lua.table()
    addon.game = b"FOREVER"
    f = lua.eval(b"function(code) local f, err = loadstring(code, '@vuelos'); if not f then error(err) end; return f end")(
        codigo.encode())
    f(None, addon)
    fpdb = addon.FPDB
    if fpdb is None:
        sys.exit("el fichero no define FPDB")
    out = {}
    for faccion, clave in ((b"Alliance", "A"), (b"Horde", "H")):
        tabla = fpdb[faccion]
        tiempos = {}
        if tabla is not None:
            for nodo, destinos in tabla.items():
                for destino, segundos in destinos.items():
                    if isinstance(destino, int) and isinstance(segundos, (int, float)) and segundos > 0:
                        tiempos.setdefault(int(nodo), {})[destino] = int(round(segundos))
        # Simetría: si solo consta un sentido, el otro vale lo mismo.
        for a, destinos in list(tiempos.items()):
            for b, s in destinos.items():
                tiempos.setdefault(b, {}).setdefault(a, s)
        out[clave] = tiempos
    return out


def to_lua(datos):
    lineas = [
        "-- Tiempos de vuelo entre maestros de vuelo de Forever, en segundos, por facción:",
        "-- [nodo] = { [destino] = segundos }. Los nodos son los nodeID de C_TaxiMap.",
        "-- Generado por tools/extraer_vuelos.py: no editar a mano.",
        "local _, ns = ...",
        "ns.FlightTimes = {",
    ]
    for clave in ("A", "H"):
        lineas.append("    %s = {" % clave)
        for nodo in sorted(datos[clave]):
            pares = ", ".join("[%d] = %d" % (d, s) for d, s in sorted(datos[clave][nodo].items()))
            lineas.append("        [%d] = { %s }," % (nodo, pares))
        lineas.append("    },")
    lineas.append("}")
    return "\n".join(lineas) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("origen")
    ap.add_argument("--lua", default=os.path.join(ADDON, "FlightData.lua"))
    args = ap.parse_args()
    datos = leer(args.origen)
    with open(args.lua, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(to_lua(datos))
    for clave in ("A", "H"):
        aristas = sum(len(d) for d in datos[clave].values())
        print("%s: %d nodos, %d tramos" % (clave, len(datos[clave]), aristas))


if __name__ == "__main__":
    main()
