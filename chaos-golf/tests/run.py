#!/usr/bin/env python3
"""Bundle the pure shared modules with Roblox stubs and run tests/tests.luau.

Usage: python3 tests/run.py /path/to/luau
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SHARED = HERE.parent / "src" / "shared"
MODULES = ["Config", "Skins", "Cosmetics", "Crates", "DailyRewards", "Maps", "Abilities", "Ranks", "Minigames", "ShopCatalog"]

harness = (HERE / "harness.luau").read_text()
harness = harness.replace(
    '\t\tlocal f = io and io.open and io.open(ROOT .. name .. ".luau")\n\t\terror("no io")',
    '\t\tlocal fn = __mods[name]\n\t\tassert(fn, "missing module " .. name)\n\t\tcache[name] = fn()\n\t\treturn cache[name]',
).replace("return nil\n", "")
parts = ["__mods = {}", harness]
for name in MODULES:
    src = (SHARED / f"{name}.luau").read_text().replace("--!strict", "")
    src = re.sub(r"^export type", "type", src, flags=re.M)
    parts.append(f'__mods["{name}"] = function()\n{src}\nend')
parts.append((HERE / "tests.luau").read_text())
bundle = HERE / ".bundle.luau"
bundle.write_text("\n".join(parts))
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
result = subprocess.run([luau, str(bundle)], capture_output=True, text=True)
bundle.unlink()
print(result.stdout + result.stderr)
sys.exit(0 if "ALL TESTS PASSED" in result.stdout else 1)
