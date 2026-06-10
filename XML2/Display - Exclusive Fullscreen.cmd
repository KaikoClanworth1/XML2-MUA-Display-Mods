@echo off
rem One-click: switch X-Men Legends II to EXCLUSIVE (true) FULLSCREEN at your desktop resolution.
rem Lowest latency / best for G-Sync/FreeSync. Resolution must be one your GPU enumerates.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0XML2_Display_Mode.ps1" -Mode fullscreen
echo.
pause
