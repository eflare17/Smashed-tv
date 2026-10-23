#!/bin/sh
# Builds the mine_sim GDExtension (the mine's pixel world: MineSim) for Linux and Windows x86_64:
#   GODOT_CPP=/path/to/godot-cpp (branch 4.4, built: scons target=template_release for linux and windows use_mingw=yes)
#   sh src/build.sh
# Needs g++, x86_64-w64-mingw32-g++. Owned by the voxel session.
set -e
cd "$(dirname "$0")/.."
G="$GODOT_CPP"
INC="-I$G/include -I$G/gen/include -I$G/gdextension -Isrc"
g++ -std=c++17 -O2 -fPIC -shared $INC src/mine_sim.cpp src/register_types.cpp \
	"$G/bin/libgodot-cpp.linux.template_release.x86_64.a" -o bin/libmine_sim.linux.x86_64.so
x86_64-w64-mingw32-g++ -std=c++17 -O2 -shared $INC src/mine_sim.cpp src/register_types.cpp \
	"$G/bin/libgodot-cpp.windows.template_release.x86_64.a" -static-libgcc -static-libstdc++ -static \
	-o bin/mine_sim.windows.x86_64.dll
strip bin/libmine_sim.linux.x86_64.so
x86_64-w64-mingw32-strip bin/mine_sim.windows.x86_64.dll
