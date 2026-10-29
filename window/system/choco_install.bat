@echo off
setlocal
:: One-click launcher for Chocolatey Package Manager Installer TUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0choco_install.ps1" %*
endlocal
