#!/usr/bin/env bash
# St Kilda in the voxel game: copy the St Kilda map's code (Luna Park and the town around it) from the St Kilda
# project (C:\Users\Admin\Documents\stkilda-godot, only ever read) into scripts/voxel/stkilda/map/, every class
# renamed with "Sk" in front so nothing clashes with the voxel game's own (its GameData, its DayNight), and cut its
# map down to Luna Park and the 50 m round it (tools/stkilda_cut.gd -> data/stkilda/). Run it again to bring later
# St Kilda changes across: the copied files are overwritten, so don't edit them here.
#
# It copies what's committed there (git HEAD), not what's half done in its working copy.
#
#   bash tools/stkilda_sync.sh [path to stkilda-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-C:/Users/Admin/Documents/stkilda-godot}"
GODOT="${GODOT:-C:/Users/Admin/Godot_4.4.1/Godot_v4.4.1-stable_win64_console.exe}"
OUT=scripts/voxel/stkilda/map
mkdir -p "$OUT" data/stkilda

FILES=(town/town_builder town/town_roads town/town_trees town/facades town/landmarks
       town/luna_park town/luna_rides town/luna_extras town/scenic_railway world/models
       town/coaster_wood town/contact_shade town/ground_look town/worn_look town/crowd town/ragdoll
       town/day_night town/park_flags town/ride_lights)
NAMES=(TownBuilder TownRoads TownTrees Facades Landmarks LunaPark LunaRides LunaExtras ScenicRailway Models
       CoasterWood ContactShade GroundLook WornLook Crowd Ragdoll DayNight ParkFlags RideLights GameData
       Car Walker)

# a file as committed in the St Kilda project
src() {
	git -C "$SRC" show "HEAD:scripts/$1"
}

rename() {
	local s=""
	for n in "${NAMES[@]}"; do
		local to="Sk$n"
		[ "$n" = GameData ] && to=SkData
		s+="s/\\b$n\\b/$to/g;"
	done
	sed -E "$s"'s#res://data/(town|luna)\.json#res://data/stkilda/\1.json#g'
}

for f in "${FILES[@]}"; do
	out="$OUT/sk_$(basename "$f").gd"
	{
		echo "# (Copied from stkilda-godot scripts/$f.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)"
		src "$f.gd" | rename
	} > "$out"
done
# the St Kilda project's GameData: only its colours and physics layers are used (as SkData)
{
	echo "# (Copied from stkilda-godot scripts/game_data.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)"
	echo "class_name SkData"
	src game_data.gd | sed -E 's/^extends Node$/extends RefCounted/' | rename
} > "$OUT/sk_data.gd"
# The crowd knocks people over when the St Kilda game's car (Car) or you on foot (Walker) bump into them. Neither is
# here (the voxel game has its own player, and no car), so stand-ins: VoxelStKilda's walker never moves, so nobody's
# knocked over.
cat > "$OUT/sk_car.gd" <<'EOF'
# (Made by tools/stkilda_sync.sh: a stand-in for the St Kilda game's Car, which SkCrowd names. No car here.)
class_name SkCar
extends Node3D

var speed := 0.0
var velocity := Vector3.ZERO
EOF
cat > "$OUT/sk_walker.gd" <<'EOF'
# (Made by tools/stkilda_sync.sh: a stand-in for the St Kilda game's Walker, which SkCrowd names. It never moves, so
# the crowd never gets knocked over.)
class_name SkWalker
extends CharacterBody3D

func shove() -> void:
	pass
EOF

# (its map too, as committed)
TMP="$(mktemp -d)"
command -v cygpath >/dev/null && TMP="$(cygpath -m "$TMP")"     # (Godot wants a Windows path)
mkdir -p "$TMP/data"
git -C "$SRC" show HEAD:data/town.json > "$TMP/data/town.json"
git -C "$SRC" show HEAD:data/luna.json > "$TMP/data/luna.json"
"$GODOT" --headless --path . -s tools/stkilda_cut.gd -- --src="$TMP" 2>&1 | grep -v "^Godot Engine" || true
rm -rf "$TMP"
echo "St Kilda synced from $SRC ($(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?'))"
