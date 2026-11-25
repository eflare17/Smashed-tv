#!/usr/bin/env bash
# The Android APK of the voxel arena, start to finish, the way downloads/SmashedVoxelArena.apk was built.
#
#   tools/build_android.sh [out.apk]        (default: downloads/SmashedVoxelArena.apk)
#
# Two steps, because one of them is not something Godot 4.4 can do:
#   1. a release export of the "Android Voxel Arena" preset, signed with the Godot editor's own debug keystore --
#      the same key every build so far, so a new APK installs straight over the old app;
#   2. tools/android_cutout.py, which puts android:windowLayoutInDisplayCutoutMode="shortEdges" on the activity in
#      the exported APK's manifest and signs it again with the same key. Without it the phone's window is laid out
#      to avoid the punch-hole camera and the game sits in a black band down one side (see that file's notes).
#
# rendering/textures/vram_compression/import_etc2_astc in project.godot must stay on: Godot refuses an Android
# export without it and says nothing about why.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/downloads/SmashedVoxelArena.apk}"
godot="${GODOT:-/root/godot/godot}"
sdk="${ANDROID_SDK_ROOT:-/root/android-sdk}"
tools="${ANDROID_BUILD_TOOLS:-$sdk/build-tools/34.0.0}"
keystore="${KEYSTORE:-$HOME/.local/share/godot/keystores/debug.keystore}"

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

raw="$root/godot/build/android/SmashedVoxelArena.apk"
mkdir -p "$(dirname "$raw")"
"$godot" --headless --path "$root/godot" --export-release "Android Voxel Arena" "$raw"

python3 "$root/tools/android_cutout.py" "$raw" "$out" \
	--keystore "$keystore" --alias androiddebugkey --pass android --build-tools "$tools"

echo
echo "$out"
ls -l "$out"
sha256sum "$out"
"$tools/apksigner" verify --verbose "$out"
"$tools/aapt2" dump xmltree --file AndroidManifest.xml "$out" | grep -i cutout
unzip -l "$out" | grep -E "lib/|addons/|digsite/native" || echo "(no addons, no native lib)"
