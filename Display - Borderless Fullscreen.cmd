@echo off
rem One-click: switch X-Men Legends II to BORDERLESS FULLSCREEN at your desktop resolution.
rem Alt-Tab friendly, no exclusive mode. Add -Width/-Height to override (must be a real mode for the menu).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0XML2_Display_Mode.ps1" -Mode borderless
echo.
pause
