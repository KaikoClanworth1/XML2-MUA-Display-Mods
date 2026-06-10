@echo off
rem One-click: switch Marvel Ultimate Alliance to WINDOWED (1280x720, centered by dgVoodoo).
rem Then launch Game.exe. Edit the line below to change size, e.g. add  -Width 1600 -Height 900
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MUA_Display_Mode.ps1" -Mode windowed
echo.
pause
