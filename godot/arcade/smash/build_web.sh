#!/bin/bash
# Rebuilds the browser version of Smash in smash-play/ (repo top folder), served by GitHub Pages at
# https://eflare17.github.io/Smashed-tv/smash-play/. Like wheres-shane/, it reuses the main game's engine
# (godot-play/index.js + index.wasm, Godot 4.4.1) and only ships its own small .pck, exported from a throwaway
# project holding just this folder's game scripts (so none of the main game's autoloads come along).
# Usage: bash godot/arcade/smash/build_web.sh [path to Godot 4.4.1]   (default: godot on the PATH, else ~/godot/godot)
set -e
GODOT=${1:-$(command -v godot || echo "$HOME/godot/godot")}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
OUT="$REPO/smash-play"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/arcade/smash"
for f in smash.gd smash.tscn smash_gibs.gd smash_horde.gd smash_hud.gd smash_input.gd smash_shots.gd smash_vox.gd; do
	cp "$HERE/$f" "$W/arcade/smash/"
done
cat > "$W/project.godot" <<'P'
config_version=5

[application]

config/name="Smash"
run/main_scene="res://arcade/smash/smash.tscn"
config/features=PackedStringArray("4.4", "GL Compatibility")

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
P
cat > "$W/export_presets.cfg" <<'P'
[preset.0]

name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
export_path="out/index.html"

[preset.0.options]

variant/extensions_support=false
variant/thread_support=false
P
"$GODOT" --headless --path "$W" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$W" --export-pack Web "$W/smash.pck" >/dev/null 2>&1
[ -s "$W/smash.pck" ] || { echo "export failed"; exit 1; }
# the pack's name carries its hash so browsers never use a stale cached copy
NAME="smash-$(sha256sum "$W/smash.pck" | cut -c1-8).pck"
SIZE=$(stat -c %s "$W/smash.pck")
rm -f "$OUT"/smash-*.pck
cp "$W/smash.pck" "$OUT/$NAME"
sed -i -E "s/\"mainPack\":\"smash-[0-9a-f]+\.pck\"/\"mainPack\":\"$NAME\"/; s/\"smash-[0-9a-f]+\.pck\":[0-9]+/\"$NAME\":$SIZE/" "$OUT/index.html"
echo "smash-play/$NAME ($SIZE bytes)"
