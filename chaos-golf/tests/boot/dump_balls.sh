#!/bin/bash
# Dump one printed ball per skin for tools/render_balls.py.
# Usage: tests/boot/dump_balls.sh <luau binary> <globalTypes.d.luau> <out.txt>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LUAU="$1"; DEFS="$2"; OUT="$3"
TMP="$(mktemp -d)"
cd "$HERE"
[ -f api.luau ] || python3 gen_api.py "$DEFS" > /dev/null
(echo ";(function()"; cat setup.luau; echo "end)();"; cat dump_balls.luau) > "$TMP/scenario.luau"
python3 gen.py "$TMP/scenario.luau" "$TMP/boot.luau"
"$LUAU" "$TMP/boot.luau" | grep "^@" > "$OUT"
rm -rf "$TMP"
echo "wrote $(grep -c '^@BALL' "$OUT") balls, $(grep -c '^@PLATE' "$OUT") plates to $OUT"
