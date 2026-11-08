@echo off
rem -Preview shows the finish result with the optional graph; preferences stay unchanged.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Overlay.ps1" %*
if errorlevel 1 pause
