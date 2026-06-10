@echo off
rem One-click: switch X-Men Legends II to WINDOWED mode (1280x720 by default).
rem Edit the line below to change size, e.g. add  -Width 1600 -Height 900
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0XML2_Display_Mode.ps1" -Mode windowed
echo.
pause
