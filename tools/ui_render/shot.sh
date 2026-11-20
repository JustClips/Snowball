#!/bin/bash
# Renders one or more scenarios on phone and PC: tools/ui_render/shot.sh hud keeprolling ...
# PNGs go to ${UI_OUT:-/tmp/claude-0/ui}/<scenario>_<device>.png
cd "$(dirname "$0")/../.." || exit 1
OUT=${UI_OUT:-/tmp/claude-0/ui}
mkdir -p "$OUT"
for s in "$@"; do
  for d in PC Phone; do
    lune run tools/ui_render/run.luau "$s" "$d" "$OUT/${s}_${d}.json" > "$OUT/${s}_${d}.log" 2>&1
    node tools/ui_render/render.mjs "$OUT/${s}_${d}.json" "$OUT/${s}_${d}.png" "$d" > /dev/null
    grep "^\[" "$OUT/${s}_${d}.log" | grep -v "PetWorldController\|TrackFx\|Obstacles" | head -5
  done
done
