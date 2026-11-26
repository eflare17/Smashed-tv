@echo off
rem Double-click to play Smash, the arcade mini-game, on its own.
rem Finds Godot 4.4 on this PC (or offers to download it once); see godot\arcade\smash\play_smash.ps1.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "godot\arcade\smash\play_smash.ps1"
if errorlevel 1 pause
