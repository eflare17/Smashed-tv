#!/usr/bin/env bash
# St Kilda in the voxel game: copy the St Kilda map's code (Luna Park and the town around it) from the St Kilda
# project (C:\Users\Admin\Documents\stkilda-godot, only ever read) into scripts/voxel/stkilda/map/, every class
# renamed with "Sk" in front so nothing clashes with the voxel game's own (its GameData, say), and cut its map down
# to Luna Park and the 50 m round it (tools/stkilda_cut.gd -> data/stkilda/). Run it again to bring later St Kilda
# changes across: the copied files are overwritten, so don't edit them here.
#
#   bash tools/stkilda_sync.sh [path to stkilda-godot]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-C:/Users/Admin/Documents/stkilda-godot}"
GODOT="${GODOT:-C:/Users/Admin/Godot_4.4.1/Godot_v4.4.1-stable_win64_console.exe}"
OUT=scripts/voxel/stkilda/map
mkdir -p "$OUT" data/stkilda

FILES=(town/town_builder town/town_roads town/town_trees town/facades town/landmarks
       town/luna_park town/luna_rides town/luna_extras town/scenic_railway world/models)
NAMES=(TownBuilder TownRoads TownTrees Facades Landmarks LunaPark LunaRides LunaExtras ScenicRailway Models GameData)

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
		rename < "$SRC/scripts/$f.gd"
	} > "$out"
done
# the St Kilda project's GameData: only its colours and physics layers are used (as SkData)
{
	echo "# (Copied from stkilda-godot scripts/game_data.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)"
	echo "class_name SkData"
	sed -E 's/^extends Node$/extends RefCounted/' "$SRC/scripts/game_data.gd" | rename
} > "$OUT/sk_data.gd"

"$GODOT" --headless --path . -s tools/stkilda_cut.gd -- --src="$SRC" 2>&1 | grep -v "^Godot Engine" || true
echo "St Kilda synced from $SRC ($(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo '?'))"
