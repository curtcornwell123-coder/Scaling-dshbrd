#!/bin/bash
# Export a code-built model to Rojo model JSON, then build .rbxm and .rbxmx.
# Usage: tools/export/export.sh <luau> <globalTypes.d.luau> <Workspace/Path> <Name> <outdir>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
LUAU="$1"; DEFS="$2"; PATH_IN="$3"; NAME="$4"; OUT="$5"
TMP="$(mktemp -d)"
mkdir -p "$OUT"
BOOT="$ROOT/tests/boot"
(cd "$BOOT" && [ -f api.luau ] || python3 gen_api.py "$DEFS" > /dev/null)
(echo "Sim.exportPath = \"$PATH_IN\""; echo ";(function()"; cat "$BOOT/setup.luau"; echo "end)();"; cat "$BOOT/export_model.luau") > "$TMP/scenario.luau"
(cd "$BOOT" && python3 gen.py "$TMP/scenario.luau" "$TMP/boot.luau")
"$LUAU" "$TMP/boot.luau" | grep "^@[NQ]|" > "$TMP/records.txt"
python3 "$HERE/model_to_rojo.py" "$TMP/records.txt" "$NAME" "$TMP/$NAME.model.json"
ROJO="${ROJO:-rojo}"
echo "{\"name\": \"$NAME\", \"tree\": {\"\$path\": \"$NAME.model.json\"}}" > "$TMP/export.project.json"
"$ROJO" build "$TMP/export.project.json" -o "$TMP/raw.rbxmx"
# Link Beam attachments (Rojo 7.4 leaves Rojo_Target_* as attributes), then build the binary model from it.
python3 "$HERE/fix_refs.py" "$TMP/raw.rbxmx" "$OUT/$NAME.rbxmx"
echo "{\"name\": \"$NAME\", \"tree\": {\"\$path\": \"$NAME.rbxmx\"}}" > "$OUT/export.project.json"
"$ROJO" build "$OUT/export.project.json" -o "$OUT/$NAME.rbxm"
rm "$OUT/export.project.json"
echo "instances: $(grep -c '^@N' "$TMP/records.txt")"
rm -rf "$TMP"
