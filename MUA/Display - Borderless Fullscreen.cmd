@echo off
rem One-click: switch Marvel Ultimate Alliance to BORDERLESS FULLSCREEN at desktop resolution.
rem Recommended mode on MUA (fills the monitor, Alt-Tab friendly, no centering/cursor caveats).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MUA_Display_Mode.ps1" -Mode borderless
echo.
pause
