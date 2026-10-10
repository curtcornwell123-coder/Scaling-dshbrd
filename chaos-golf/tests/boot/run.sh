#!/bin/bash
# Headless boot test of the whole game against a Roblox API mock.
# Usage: tests/boot/run.sh <luau binary> <globalTypes.d.luau> [forward|reverse|deferred]
# Signal mode = order in which handlers for the same signal fire (Roblox doesn't guarantee one).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LUAU="$1"; DEFS="$2"; MODE="${3:-forward}"
TMP="$(mktemp -d)"
cd "$HERE"
[ -f api.luau ] || python3 gen_api.py "$DEFS" > /dev/null
(echo "Sim.signalMode = \"$MODE\""; echo ";(function()"; cat setup.luau; echo "end)();"; echo "(function()"; cat scenario.luau; echo "end)();"; cat phase2.luau phase3.luau final.luau) > "$TMP/scenario.luau"
python3 gen.py "$TMP/scenario.luau" "$TMP/boot.luau"
"$LUAU" "$TMP/boot.luau" | grep -E "FLOW|ERRORS" 
rm -rf "$TMP"
