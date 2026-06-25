@echo off
setlocal
cd /d "%~dp0"

where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\serve-dist.ps1"
) else (
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\serve-dist.ps1"
)

