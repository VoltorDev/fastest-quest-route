"""Carga la QuestieDB real (modo baked, TOC de Forever) en Lua 5.1 (lupa) fuera del juego.

Uso: python -I -B tools/questiedb_real.py [RUTA_QUESTIEDB] -- "codigo lua"
Devuelve un runtime lupa con LibQuestieDB cargada (función cargar()).
"""
import os
import base64
import re
import struct
import zlib
import sys

import site

_usuario = site.getusersitepackages()
if _usuario not in sys.path and os.path.isdir(_usuario):
    sys.path.append(_usuario)
import lupa.lua51 as lupa  # noqa: E402

DEFAULT = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestieDB"

STUBS = r"""
bit = bit or {}
local function tobits(n) return n end
if not bit.band then
  function bit.band(a, b) local r, p = 0, 1; while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end; a = math.floor(a/2); b = math.floor(b/2); p = p*2 end; return r end
  function bit.bor(a, b) local r, p = 0, 1; while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + p end; a = math.floor(a/2); b = math.floor(b/2); p = p*2 end; return r end
  function bit.lshift(a, n) return a * 2^n end
  function bit.rshift(a, n) return math.floor(a / 2^n) end
  function bit.bxor(a, b) local r, p = 0, 1; while a > 0 or b > 0 do if (a % 2) ~= (b % 2) then r = r + p end; a = math.floor(a/2); b = math.floor(b/2); p = p*2 end; return r end
  function bit.bnot(a) return -1 - a end
end
strsplit = function(sep, s, n)
  local out = {}
  local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
  for piece in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out+1] = piece end
  return unpack(out)
end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
GetLocale = function() return LOCALE_FORZADO or "esES" end
GetBuildInfo = function() return "1.60.1", "70790", "Nov 4 2026", 16001 end
print_ = print
C_Timer = { After = function(_, f) end, NewTicker = function() return { Cancel = function() end } end }
UnitFactionGroup = function() return FACCION_FORZADA or "Horde", FACCION_FORZADA or "Horde" end
UnitLevel = function() return 1 end
UnitClassBase = function() return "WARLOCK", 9 end
UnitRace = function() return "Orc", "Orc", 2 end
GetRealmName = function() return "Forever" end
UnitName = function() return "Fear", "Ofme" end
GetTime = os.clock
debugprofilestop = function() return os.clock() * 1000 end
hooksecurefunc = function() end
issecretvalue = function() return false end
UnitRace = function() return "Orc", "Orc", 2 end
UnitClass = function() return "Warlock", "WARLOCK", 9 end
CreateFrame = function() local f = {}; setmetatable(f, { __index = function() return function() end end }); return f end
"""


def _cbor(lua, data):
    """Decodificador CBOR mínimo con la semántica de C_EncodingUtil.DeserializeCBOR."""
    pos = 0

    def arg(info):
        nonlocal pos
        if info < 24:
            return info
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        v = int.from_bytes(data[pos:pos + size], "big")
        pos += size
        return v

    def item():
        nonlocal pos
        ib = data[pos]
        pos += 1
        major, info = ib >> 5, ib & 31
        if major == 0:
            return arg(info)
        if major == 1:
            return -1 - arg(info)
        if major in (2, 3):
            n = arg(info)
            v = bytes(data[pos:pos + n])
            pos += n
            return v
        if major == 4:
            n = arg(info)
            t = lua.table()
            for i in range(n):
                v = item()
                if v is not None:
                    t[i + 1] = v
            return t
        if major == 5:
            n = arg(info)
            t = lua.table()
            for _ in range(n):
                k = item()
                v = item()
                if k is not None and v is not None:
                    t[k] = v
            return t
        if major == 6:
            arg(info)
            return item()
        if info == 20:
            return False
        if info == 21:
            return True
        if info in (22, 23):
            return None
        if info == 25:
            h = struct.unpack(">e", data[pos:pos + 2])[0]
            pos += 2
            return h
        if info == 26:
            f = struct.unpack(">f", data[pos:pos + 4])[0]
            pos += 4
            return f
        if info == 27:
            d = struct.unpack(">d", data[pos:pos + 8])[0]
            pos += 8
            return d
        raise ValueError("CBOR no soportado: %d/%d" % (major, info))

    return item()


def _encoding(lua):
    def decode_b64(s):
        return base64.b64decode(s + b"=" * (-len(s) % 4))

    def decompress(s, method=0):
        method = int(method or 0)
        if method == 1:
            return zlib.decompress(s)
        if method == 2:
            return zlib.decompress(s, 16 + zlib.MAX_WBITS)
        return zlib.decompress(s, -zlib.MAX_WBITS)

    t = lua.table()
    t[b"DecodeBase64"] = decode_b64
    t[b"DecompressString"] = decompress
    t[b"DeserializeCBOR"] = lambda s: _cbor(lua, s)
    return t


def cargar(ruta=DEFAULT, locale="esES"):
    toc = os.path.join(ruta, "QuestieDB_Forever.toc")
    meta = {}
    archivos = []
    with open(toc, encoding="utf-8") as fh:
        for linea in fh:
            linea = linea.rstrip("\r\n")
            if linea.startswith("## "):
                m = re.match(r"## ([^:]+):\s?(.*)$", linea)
                if m:
                    meta[m.group(1).strip()] = m.group(2)
            elif linea and not linea.startswith("#"):
                archivos.append(linea.strip())
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    g = lua.globals()
    lua.execute(STUBS.encode())
    g.C_EncodingUtil = _encoding(lua)
    g.LOCALE_FORZADO = locale.encode()
    meta_lua = lua.table_from({k.encode(): v.encode() for k, v in meta.items()})
    getter = lua.eval(b"function(meta) return function(addon, key) return meta[key] end end")(meta_lua)
    g.C_AddOns = lua.table_from({b"GetAddOnMetadata": getter})
    g.GetAddOnMetadata = getter
    ns = lua.table()
    loader = lua.eval(b"function(code, name, ns) local f, err = loadstring(code, name); if not f then error(err) end; return f('QuestieDB', ns) end")
    for rel in archivos:
        path = os.path.join(ruta, rel.replace("\\", os.sep))
        if not path.endswith(".lua"):
            continue
        with open(path, encoding="utf-8") as fh:
            codigo = fh.read()
        if codigo.startswith("\ufeff"):
            codigo = codigo[1:]
        loader(codigo.encode(), ("@" + rel).encode(), ns)
    return lua


if __name__ == "__main__":
    args = sys.argv[1:]
    ruta = DEFAULT
    if args and args[0] != "--":
        ruta = args.pop(0)
    if args and args[0] == "--":
        args.pop(0)
    lua = cargar(ruta)
    for codigo in args:
        print(lua.execute(codigo.encode()))
