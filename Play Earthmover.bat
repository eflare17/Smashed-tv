@echo off
rem Double-click to try the earthmover test on the PC (earthmover-godot\). W A S D drive, Q and E lower and raise the blade,
rem right mouse drag looks, the wheel zooms. Uses Godot 4.4.1, or the GODOT variable.
cd /d "%~dp0earthmover-godot"
set "G=%GODOT%"
if "%G%"=="" set "G=%USERPROFILE%\Godot_4.4.1\Godot_v4.4.1-stable_win64.exe"
if not exist "%G%" (
	echo Godot 4.4.1 was not found at "%G%".
	echo Set the GODOT environment variable to your Godot exe.
	pause
	exit /b 1
)
start "" "%G%" --path .
