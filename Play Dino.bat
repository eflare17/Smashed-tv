@echo off
rem Double-click to play the dino game (dino\, step 1). Uses Godot 4.6.2 from Downloads, or the GODOT variable.
cd /d "%~dp0dino"
set "G=%GODOT%"
if "%G%"=="" set "G=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
if not exist "%G%" (
	echo Godot 4.6.2 was not found at "%G%".
	echo Set the GODOT environment variable to your Godot exe.
	pause
	exit /b 1
)
start "" "%G%" --path .
