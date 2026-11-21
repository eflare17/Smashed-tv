@echo off
rem Double-click to play Voxel Arena (voxel-arena-unity\), the voxel shooter with Smashed's grunts.
rem W A S D move, mouse aims, left mouse rifle, right mouse rocket, Tab flips between over the shoulder and from above, F11 or Alt+Enter full screen or a window.
rem Runs the built exe in voxel-arena-unity\Builds\VoxelArena3 (make it with ArenaBuilder.BuildWindows).
cd /d "%~dp0voxel-arena-unity\Builds\VoxelArena3"
if not exist "VoxelArena.exe" (
	echo VoxelArena.exe was not found in "%CD%".
	echo Build it first: Unity, voxel-arena-unity, -executeMethod ArenaBuilder.BuildWindows
	pause
	exit /b 1
)
start "" "VoxelArena.exe"
