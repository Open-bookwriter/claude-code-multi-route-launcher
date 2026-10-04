@echo off
setlocal
set "ROOT=%~dp0"
where wt.exe >nul 2>nul
if %errorlevel%==0 (
  start "" wt.exe -w new new-tab --title "Claude Multi-Route Launcher" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Launcher.ps1"
) else (
  start "Claude Multi-Route Launcher" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%Launcher.ps1"
)
endlocal
