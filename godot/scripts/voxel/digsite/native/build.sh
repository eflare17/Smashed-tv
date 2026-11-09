#!/bin/sh
# Builds the Dig Site's GDExtension (DigSiteGrid: the voxel ground, its dirt, its meshes) for Linux and Windows x86_64:
#   GODOT_CPP=/path/to/godot-cpp (branch 4.4, built: scons target=template_release for linux and windows use_mingw=yes)
#   sh scripts/voxel/digsite/native/build.sh
# Needs g++, x86_64-w64-mingw32-g++. The same way as addons/mine_sim. Owned by the voxel session.
set -e
cd "$(dirname "$0")"
G="$GODOT_CPP"
INC="-I$G/include -I$G/gen/include -I$G/gdextension -Isrc"
# (built beside them, then moved over them: a game running with the old one keeps it)
SRC="src/dig_site_grid.cpp src/dig_site_dirt.cpp src/dig_site_net.cpp src/dig_site_cave.cpp src/dig_site_mesh.cpp src/dig_site_blade.cpp src/dig_site_show.cpp src/register_types.cpp"
g++ -std=c++17 -O2 -fPIC -shared $INC $SRC \
	"$G/bin/libgodot-cpp.linux.template_release.x86_64.a" -o bin/.new.so
x86_64-w64-mingw32-g++ -std=c++17 -O2 -shared $INC $SRC \
	"$G/bin/libgodot-cpp.windows.template_release.x86_64.a" -static-libgcc -static-libstdc++ -static \
	-o bin/.new.dll
strip bin/.new.so
x86_64-w64-mingw32-strip bin/.new.dll
mv -f bin/.new.so bin/libdig_site_sim.linux.x86_64.so
mv -f bin/.new.dll bin/dig_site_sim.windows.x86_64.dll
