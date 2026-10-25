#!/bin/bash
# Builds the browser version of the dino game into dino-play/ (repo top folder), served by GitHub Pages at
# https://eflare17.github.io/Smashed-tv/dino-play/. Like smash-play/, it reuses the main game's web engine
# (godot-play/index.js + index.wasm, Godot 4.4.1) and only ships its own small .pck, exported from a throwaway copy
# of the game (the scripts, the scene and the imported art: no tests, tools or raw sheets).
# Usage: bash dino/build_web.sh [path to Godot 4.4.1]
#   (default: the 4.4.1 console exe in %LOCALAPPDATA%\SmashedTV\godot441, else godot on the PATH)
set -e
GODOT=${1:-"$LOCALAPPDATA/SmashedTV/godot441/Godot_v4.4.1-stable_win64_console.exe"}
[ -x "$GODOT" ] || GODOT=$(command -v godot)
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
OUT="$REPO/dino-play"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/art" "$OUT"
cp -r "$HERE/scripts" "$W/"
cp "$HERE/main.tscn" "$W/"
cp "$HERE"/art/*.png "$W/art/"
rm -f "$W/art/_preview.png"
find "$W" -name "*.uid" -delete
# the same project, marked for 4.4 (the engine the page runs on)
sed 's/config\/features=PackedStringArray("4.6", "GL Compatibility")/config\/features=PackedStringArray("4.4", "GL Compatibility")/' \
	"$HERE/project.godot" > "$W/project.godot"
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
"$GODOT" --headless --path "$W" --export-pack Web "$W/dino.pck" >"$W/export.log" 2>&1 || true
[ -s "$W/dino.pck" ] || { cat "$W/export.log"; echo "export failed"; exit 1; }
# the pack's name carries its hash so browsers never use a stale cached copy
NAME="dino-$(sha256sum "$W/dino.pck" | cut -c1-8).pck"
SIZE=$(stat -c %s "$W/dino.pck")
rm -f "$OUT"/dino-*.pck
cp "$W/dino.pck" "$OUT/$NAME"
# the page: smash-play's, pointed at this pack (first build copies it and its icons)
if [ ! -f "$OUT/index.html" ]; then
	cp "$REPO/smash-play/index.html" "$OUT/index.html"
	cp "$REPO"/smash-play/index.*.png "$REPO/smash-play/index.png" "$OUT/" 2>/dev/null || true
	sed -i 's/<title>Smash<\/title>/<title>Dino<\/title>/' "$OUT/index.html"
fi
sed -i -E "s/\"mainPack\":\"(smash|dino)-[0-9a-f]+\.pck\"/\"mainPack\":\"$NAME\"/; s/\"(smash|dino)-[0-9a-f]+\.pck\":[0-9]+/\"$NAME\":$SIZE/" "$OUT/index.html"
echo "dino-play/$NAME ($SIZE bytes)"
