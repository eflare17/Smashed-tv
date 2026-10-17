#!/bin/bash
# Builds the web export of the game with the fighting installed, in a scratch copy of godot/ (main.gd gets the
# one install line the integration note asks for), serves it and takes a screenshot.
# Usage: bash godot/test/combat/web_test.sh <out.png> [wait_ms] [query]   (query e.g. "state&fight=run")
set -e
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
W="${WORK:-/tmp/claude-0/fightweb}"
G="${GODOT:-$HOME/godot/godot}"
PORT="${PORT:-8765}"
mkdir -p "$W"
mkdir -p "$W/godot" && (cd "$SRC" && tar cf - --exclude=./.godot --exclude=./build .) | (cd "$W/godot" && tar xf -)
if ! grep -q "FightInstall.install" "$W/godot/scripts/main.gd"; then
  sed -i 's/^\tprint("Smashed TV (Godot) ", hud.build_text, ": ready")/\tFightInstall.install(self)\n&/' "$W/godot/scripts/main.gd"
fi
cd "$W/godot"
"$G" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p build/web
"$G" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -iE "error|warn" | grep -v "^$" | head -20 || true
if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  (python3 -m http.server "$PORT" --directory "$W/godot" >/dev/null 2>&1 &)
  sleep 1
fi
OUT="${1:-/tmp/claude-0/shot.png}"
NO_PROXY=127.0.0.1 node "$SRC/tools/gd_shot.mjs" "http://127.0.0.1:$PORT/build/web/index.html?${3:-state}" "$OUT" "${2:-15000}"
