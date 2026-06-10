@echo off
rem One-click: switch Marvel Ultimate Alliance to WINDOWED mode (1280x720 titled window).
rem Note: MUA has no dgVoodoo, so the window spawns at the top-left (not centered).
rem Edit the line below to change size, e.g. add  -Width 1600 -Height 900
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MUA_Display_Mode.ps1" -Mode windowed
echo.
pause
