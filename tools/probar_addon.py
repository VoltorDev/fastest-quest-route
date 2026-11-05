#!/usr/bin/env python3
"""Ejecuta los tests de un addon de WoW (tests/**/*_spec.lua) FUERA del juego, sin busted.

Usa el Lua 5.1.5 (PUC) que trae lupa y, con --luajit, su LuaJIT 2.1; cada fichero de spec corre
en un estado Lua nuevo (como el aislamiento por fichero de busted) con un shim minimo de la API
de busted/luassert (mini_busted.lua, junto a este script). El directorio de trabajo es la
carpeta del addon y package.path incluye tests/support, igual que el .busted de la plantilla.

Uso:
  python probar_addon.py CARPETA_ADDON [--luajit | --ambos] [--filtro TEXTO] [--traza]

  --luajit   ejecuta con LuaJIT 2.1 en vez de Lua 5.1 (el cliente de WoW usa Lua 5.1)
  --ambos    ejecuta con los dos runtimes
  --filtro   solo los tests cuyo nombre completo contiene TEXTO
  --traza    muestra la traza completa de cada fallo

lupa vive en el site-packages de usuario: ejecutalo con `python` normal. Con `python -I` (modo
aislado) el script anade explicitamente ese site-packages para encontrar lupa y nada mas.
Salida 0 si todos los tests pasan; 1 si alguno falla o no hay tests; 2 si falta lupa o la carpeta.
"""
import argparse
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
SHIM = os.path.join(AQUI, "mini_busted.lua")
RUNTIMES = {"lua51": ("lupa.lua51", "Lua 5.1 (PUC)"), "luajit": ("lupa.luajit21", "LuaJIT 2.1")}


def importar_runtime(modulo):
    """Importa lupa.lua51 o lupa.luajit21. Con -I, anade el site-packages de usuario."""
    import importlib
    try:
        return importlib.import_module(modulo)
    except ImportError:
        import site
        usuario = site.getusersitepackages()
        if usuario not in sys.path and os.path.isdir(usuario):
            sys.path.append(usuario)
            return importlib.import_module(modulo)
        raise


def buscar_specs(carpeta):
    specs = []
    raiz = os.path.join(carpeta, "tests")
    for directorio, subdirs, ficheros in os.walk(raiz):
        subdirs[:] = sorted(d for d in subdirs if d != "support")
        for fichero in sorted(ficheros):
            if fichero.endswith("_spec.lua"):
                specs.append(os.path.relpath(os.path.join(directorio, fichero), carpeta).replace("\\", "/"))
    return specs


def texto(valor):
    if valor is None:
        return ""
    if isinstance(valor, bytes):
        return valor.decode("utf-8", errors="replace")
    return str(valor)


def ejecutar_spec(lupa_mod, spec, filtro):
    """Ejecuta un fichero de spec en un LuaRuntime nuevo. Devuelve una lista de dicts."""
    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    g = lua.globals()
    g.PROBAR_SHIM = SHIM.replace("\\", "/").encode("utf-8")
    g.PROBAR_SPEC = spec.encode("utf-8")
    g.PROBAR_FILTRO = filtro.encode("utf-8") if filtro else None
    resultados = lua.execute(b"""
        package.path = "tests/support/?.lua;./?.lua;" .. package.path
        local shim = dofile(PROBAR_SHIM)
        shim.install(_G)
        return shim.runFile(PROBAR_SPEC, PROBAR_FILTRO)
    """)
    salida = []
    for i in range(1, len(resultados) + 1):
        r = resultados[i]
        salida.append({clave: texto(r[clave.encode()]) for clave in ("status", "name", "message", "trace")})
    return salida


def version_lua(lupa_mod):
    lua = lupa_mod.LuaRuntime(encoding=None)
    import lupa
    return "%s, lupa %s" % (texto(lua.eval(b"(jit and jit.version) or _VERSION")), lupa.__version__)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("carpeta", help="carpeta del addon (la que contiene el .toc y tests/)")
    grupo = p.add_mutually_exclusive_group()
    grupo.add_argument("--luajit", action="store_true", help="usar LuaJIT 2.1 en vez de Lua 5.1")
    grupo.add_argument("--ambos", action="store_true", help="usar Lua 5.1 y LuaJIT 2.1")
    p.add_argument("--filtro", help="solo tests cuyo nombre completo contiene este texto")
    p.add_argument("--traza", action="store_true", help="mostrar la traza completa de cada fallo")
    a = p.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    carpeta = os.path.abspath(a.carpeta)
    if not os.path.isdir(carpeta):
        print("No existe la carpeta %s" % carpeta)
        return 2
    specs = buscar_specs(carpeta)
    if not specs:
        print("No hay tests: %s no contiene tests/*_spec.lua" % carpeta)
        return 1
    elegidos = ["lua51", "luajit"] if a.ambos else (["luajit"] if a.luajit else ["lua51"])

    os.chdir(carpeta)  # los specs usan rutas relativas a la carpeta del addon, como con busted
    fallos_totales = 0
    for clave in elegidos:
        modulo, nombre = RUNTIMES[clave]
        try:
            lupa_mod = importar_runtime(modulo)
        except ImportError as error:
            print("No puedo importar %s (%s). Instala lupa para este Python: python -m pip install --user lupa"
                  % (modulo, error))
            return 2
        inicio = time.perf_counter()
        cuenta = {"ok": 0, "fallo": 0, "error": 0, "pending": 0}
        print("== %s (%s)" % (nombre, version_lua(lupa_mod)))
        for spec in specs:
            try:
                resultados = ejecutar_spec(lupa_mod, spec, a.filtro)
            except Exception as error:  # error de lupa o del shim: cuenta como fallo del fichero
                resultados = [{"status": "error", "name": "(runner)", "message": str(error), "trace": ""}]
            parcial = {"ok": 0, "fallo": 0, "error": 0, "pending": 0}
            for r in resultados:
                parcial[r["status"]] = parcial.get(r["status"], 0) + 1
            resumen = "%d ok" % parcial["ok"]
            if parcial["fallo"] or parcial["error"]:
                resumen += ", %d FALLO" % (parcial["fallo"] + parcial["error"])
            if parcial["pending"]:
                resumen += ", %d pendiente" % parcial["pending"]
            print("  %-34s %s" % (spec, resumen))
            for r in resultados:
                if r["status"] in ("fallo", "error"):
                    print("    FALLO  %s" % r["name"])
                    for linea in r["message"].splitlines() or [""]:
                        print("           %s" % linea)
                    if a.traza and r["trace"]:
                        for linea in r["trace"].strip().splitlines():
                            print("             %s" % linea)
                elif r["status"] == "pending":
                    print("    PENDIENTE  %s" % r["name"])
            for estado, n in parcial.items():
                cuenta[estado] = cuenta.get(estado, 0) + n
        malos = cuenta["fallo"] + cuenta["error"]
        fallos_totales += malos
        print("  Total %s: %d tests, %d ok, %d fallos, %d pendientes (%.2f s)"
              % (nombre, cuenta["ok"] + malos + cuenta["pending"], cuenta["ok"], malos, cuenta["pending"],
                 time.perf_counter() - inicio))
    if fallos_totales:
        print("\nFALLA: %d test(s) en rojo." % fallos_totales)
        return 1
    print("\nOK: todos los tests pasan (fuera del juego; no sustituye la prueba en el cliente).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
