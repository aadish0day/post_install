@echo off
setlocal
:: One-click launcher for Chocolatey Package Manager Installer TUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0choco_install.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
