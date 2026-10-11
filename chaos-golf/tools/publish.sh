#!/bin/bash
# Build Ultimate Golf and publish it to an existing place through Open Cloud (place publishing API).
# Usage: tools/publish.sh UNIVERSE_ID PLACE_ID [Saved|Published]
# Auth: the x-api-key header is added by the environment's network proxy (needs universe-places:write).
set -euo pipefail
cd "$(dirname "$0")/.."
UNIVERSE="$1"; PLACE="$2"; TYPE="${3:-Published}"
ROJO="${ROJO:-/tmp/claude-0/tools/rojo}"
mkdir -p build
"$ROJO" build default.project.json -o build/UltimateGolf.rbxlx
curl -sS -m 300 -X POST \
  "https://apis.roblox.com/universes/v1/$UNIVERSE/places/$PLACE/versions?versionType=$TYPE" \
  -H "Content-Type: application/xml" --data-binary @build/UltimateGolf.rbxlx -w "\n[HTTP %{http_code}]\n"
