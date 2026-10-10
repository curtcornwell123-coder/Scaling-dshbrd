#!/bin/bash
# Dump the built world for tools/render_world.py.
# Usage: tests/boot/dump.sh <luau binary> <globalTypes.d.luau> <out.txt> [all|lobby|courses]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LUAU="$1"; DEFS="$2"; OUT="$3"; WHICH="${4:-all}"
TMP="$(mktemp -d)"
cd "$HERE"
[ -f api.luau ] || python3 gen_api.py "$DEFS" > /dev/null
(echo "Sim.dumpWhich = \"$WHICH\""; echo ";(function()"; cat setup.luau; echo "end)();"; cat dump_world.luau) > "$TMP/scenario.luau"
python3 gen.py "$TMP/scenario.luau" "$TMP/boot.luau"
"$LUAU" "$TMP/boot.luau" | grep "^@" > "$OUT"
rm -rf "$TMP"
echo "wrote $(grep -c '^@P' "$OUT") parts to $OUT"
