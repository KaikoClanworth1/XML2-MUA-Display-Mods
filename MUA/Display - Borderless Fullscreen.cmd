@echo off
rem One-click: switch Marvel Ultimate Alliance to BORDERLESS FULLSCREEN at desktop resolution.
rem Recommended mode (fills the monitor, Alt-Tab friendly). Then launch Game.exe.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MUA_Display_Mode.ps1" -Mode borderless
echo.
pause
