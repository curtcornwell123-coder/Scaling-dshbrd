#!/bin/bash
# Usage: run_all.sh [--preview]   (renders every scene sequentially)
PY=${BLENDER_PY:-/tmp/claude-0/bpyenv/bin/python}
cd "$(dirname "$0")"
for pair in golf:hero golf:ranked golf:race golf:skins golf:daily brainrot:hero brainrot:mutations brainrot:night \
            merge:hero merge:steal merge:speed merge:tiers cyber:hero cyber:breach cyber:army; do
  g=${pair%%:*}; s=${pair##*:}
  echo "$(date +%T) start $g $s"; $PY scenes.py $g $s $1 2>&1 | grep -E "WROTE|Error|Traceback|line [0-9]+" | head -5
done
echo ALL_DONE
