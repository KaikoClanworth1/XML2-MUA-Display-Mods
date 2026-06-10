@echo off
rem One-click: restore Marvel Ultimate Alliance to stock EXCLUSIVE (true) FULLSCREEN at desktop resolution.
rem Lowest latency, but minimizes when you Alt-Tab (stock behavior).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MUA_Display_Mode.ps1" -Mode fullscreen
echo.
pause
