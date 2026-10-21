#!/bin/sh
# Builds the voxel_retro GDExtension (Linux and Windows x86_64) and the libretro cores it plays, from source:
#   GODOT_CPP=/path/to/godot-cpp (branch 4.4, built: scons target=template_release for linux and windows use_mingw=yes)
#   GPGX=/path/to/Genesis-Plus-GX SNES9X=/path/to/snes9x (libretro's; built with their libretro makefiles)
#   sh src/build.sh
# Needs g++, x86_64-w64-mingw32-g++. Owned by the voxel session.
set -e
cd "$(dirname "$0")/.."
G="$GODOT_CPP"
INC="-I$G/include -I$G/gen/include -I$G/gdextension -Isrc"
g++ -std=c++17 -O2 -fPIC -shared $INC src/retro_core.cpp src/register_types.cpp \
	"$G/bin/libgodot-cpp.linux.template_release.x86_64.a" -ldl -o bin/libvoxel_retro.linux.x86_64.so
x86_64-w64-mingw32-g++ -std=c++17 -O2 -shared $INC src/retro_core.cpp src/register_types.cpp \
	"$G/bin/libgodot-cpp.windows.template_release.x86_64.a" -static-libgcc -static-libstdc++ -static \
	-o bin/voxel_retro.windows.x86_64.dll
strip bin/libvoxel_retro.linux.x86_64.so
x86_64-w64-mingw32-strip bin/voxel_retro.windows.x86_64.dll
mkdir -p bin/cores
if [ -n "$GPGX" ]; then
	cp "$GPGX/genesis_plus_gx_libretro.so" bin/cores/ && strip bin/cores/genesis_plus_gx_libretro.so
	cp "$GPGX/genesis_plus_gx_libretro.dll" bin/cores/ && x86_64-w64-mingw32-strip bin/cores/genesis_plus_gx_libretro.dll
fi
if [ -n "$SNES9X" ]; then
	cp "$SNES9X/libretro/snes9x_libretro.so" bin/cores/ && strip bin/cores/snes9x_libretro.so
	cp "$SNES9X/libretro/snes9x_libretro.dll" bin/cores/ && x86_64-w64-mingw32-strip bin/cores/snes9x_libretro.dll
fi
