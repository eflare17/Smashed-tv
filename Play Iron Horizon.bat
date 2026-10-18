@echo off
rem Double-click to play Iron Horizon: starts the little game server and opens the game.
cd /d "%~dp0"
powershell -NoProfile -Command "try { (New-Object Net.Sockets.TcpClient).Connect('localhost', 8765); exit 0 } catch { exit 1 }"
if errorlevel 1 (
  start "Iron Horizon server - close this to stop" /min powershell -NoProfile -ExecutionPolicy Bypass -File ".claude\serve.ps1"
  timeout /t 2 /nobreak >nul
)
start "" "http://localhost:8765/iron-horizon/index.html"
