#!/bin/bash
# Installs Godot 4.4.1 (headless-capable Linux build) and the web export template, for a fresh cloud session.
# Usage: bash godot/tools/setup_godot.sh  -> prints the Godot binary path (also $HOME/godot/godot).
set -e
D="$HOME/godot"; T="$HOME/.local/share/godot/export_templates/4.4.1.stable"
mkdir -p "$D" "$T"
R=https://github.com/godotengine/godot/releases/download/4.4.1-stable
if [ ! -x "$D/godot" ]; then
  curl -sSL -m 600 -o "$D/g.zip" "$R/Godot_v4.4.1-stable_linux.x86_64.zip"
  unzip -o -q "$D/g.zip" -d "$D" && rm "$D/g.zip" && mv "$D/Godot_v4.4.1-stable_linux.x86_64" "$D/godot"
fi
if [ ! -f "$T/web_nothreads_release.zip" ]; then
  # the full template pack is big: keep only the web one this project exports with
  curl -sSL -m 1800 -o "$D/t.tpz" "$R/Godot_v4.4.1-stable_export_templates.tpz"
  unzip -o -q -j "$D/t.tpz" templates/web_nothreads_release.zip templates/web_nothreads_debug.zip templates/version.txt -d "$T"
  rm "$D/t.tpz"
fi
"$D/godot" --version --headless | tail -1
echo "$D/godot"
