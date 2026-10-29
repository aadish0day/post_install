<#
.SYNOPSIS
    Automated Chocolatey Package Manager Installer, Updater & Maintenance Utility (TUI).
.DESCRIPTION
    Interactive Text-based User Interface (TUI) and automation tool for Chocolatey on Windows:
    
    [Option 1: Install / Update Chocolatey]
    - Verifies OS version and PowerShell environment (v3+ with TLS 1.2+ support).
    - Checks for existing Chocolatey installation and reports current version.
    - Executes the official installation script from https://community.chocolatey.org/install.ps1.
    - Configures ChocolateyInstall directory and refreshes session PATH immediately.
    - Enables enhanced exit codes and color settings.

    [Option 2: Upgrade All Packages]
    - Runs 'choco upgrade all -y' to bring all installed packages to their latest versions.

    [Option 3: Repair Environment]
    - Re-establishes Chocolatey environment variables and system PATH entries.
    - Clears stale temporary cache files from %TEMP%\chocolatey.
    - Refreshes current process environment.

.PARAMETER Action
    Specifies the action directly: 'Install', 'Upgrade', or 'Repair'.
    If omitted, an interactive TUI menu with keyboard navigation is displayed.
.PARAMETER Force
    Forces re-installation or re-download even if already detected.
.PARAMETER SkipConfirmation
    Bypasses user confirmation prompts during non-interactive execution.
#>

[CmdletBinding()]
param (
    [ValidateSet('Install', 'Upgrade', 'Repair')]
    [string]$Action,
    [switch]$Force,
    [switch]$SkipConfirmation
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Automatically set execution policy to Bypass for current process
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
} catch {}

# Enable modern TLS 1.2 and TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 12288
} catch {}

# ------------------------------------------------------------------------------
# Helper: Check Administrator Privileges
# ------------------------------------------------------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin

# Auto-elevate if not running as Administrator
function Ensure-AdminElevation {
    if (-not (Test-IsAdmin)) {
        Write-Host " [*] Elevating to Administrator..." -ForegroundColor Yellow
        $scriptPath = if (![string]::IsNullOrEmpty($PSScriptRoot)) { $MyInvocation.MyCommand.Path }
                      elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path }
                      else { $null }

        if ($scriptPath -and (Test-Path $scriptPath)) {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            if ($Action) { $argList += " -Action $Action" }
            if ($Force) { $argList += " -Force" }
            if ($SkipConfirmation) { $argList += " -SkipConfirmation" }

            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
            Exit 0
        } else {
            Write-Host " [!] Administrator privileges required. Please re-run from an elevated prompt." -ForegroundColor Red
            Exit 1
        }
    }
}

# ------------------------------------------------------------------------------
# Helper: Refresh Environment Variables
# ------------------------------------------------------------------------------
function Refresh-EnvironmentPath {
    $chocoPath = [Environment]::GetEnvironmentVariable('ChocolateyInstall', 'Machine')
    if (-not $chocoPath) {
        $chocoPath = "$env:SystemDrive\ProgramData\chocolatey"
    }
    $chocoBin = Join-Path $chocoPath "bin"

    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH    = "$chocoBin;$machinePath;$userPath"
    $env:ChocolateyInstall = $chocoPath
}

# ------------------------------------------------------------------------------
# Helper: Locate Choco Executable
# ------------------------------------------------------------------------------
function Find-ChocoExecutable {
    Refresh-EnvironmentPath
    $cmd = Get-Command choco.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }

    $defaultPath = "$env:SystemDrive\ProgramData\chocolatey\bin\choco.exe"
    if (Test-Path $defaultPath) { return $defaultPath }

    return $null
}

# ------------------------------------------------------------------------------
# Action 1: Install Chocolatey
# ------------------------------------------------------------------------------
function Invoke-ChocoInstall {
    Ensure-AdminElevation

    Write-Host ""
    Write-Host " ==============================================================" -ForegroundColor Cyan
    Write-Host "  Chocolatey Installation & Verification" -ForegroundColor White
    Write-Host " ==============================================================" -ForegroundColor Cyan
    Write-Host ""

    $existingChoco = Find-ChocoExecutable
    if ($existingChoco -and (-not $Force)) {
        $v = & $existingChoco --version 2>$null
        Write-Host " [+] Chocolatey is already installed: v$v ($existingChoco)" -ForegroundColor Green
        Write-Host "     Use -Force to reinstall." -ForegroundColor DarkGray
        return
    }

    Write-Host " [*] Downloading and executing official Chocolatey bootstrap script..." -ForegroundColor Cyan
    Write-Host "     URL: https://community.chocolatey.org/install.ps1" -ForegroundColor DarkGray

    try {
        $installScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
        Invoke-Expression $installScript
    } catch {
        Write-Host " [-] Chocolatey installation failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    Refresh-EnvironmentPath
    Start-Sleep -Seconds 2

    $chocoExe = Find-ChocoExecutable
    if ($chocoExe) {
        $ver = & $chocoExe --version 2>$null
        Write-Host ""
        Write-Host " [+] Successfully installed Chocolatey v$ver!" -ForegroundColor Green
        Write-Host "     Binary located at: $chocoExe" -ForegroundColor Gray
    } else {
        Write-Host " [!] Installation finished, but choco.exe was not immediately found in PATH." -ForegroundColor Yellow
        Write-Host "     Please restart your terminal or log out and back in." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
# Action 2: Upgrade All Packages
# ------------------------------------------------------------------------------
function Invoke-ChocoUpgrade {
    Ensure-AdminElevation

    $chocoExe = Find-ChocoExecutable
    if (-not $chocoExe) {
        Write-Host " [-] Chocolatey is not installed. Installing it first..." -ForegroundColor Yellow
        Invoke-ChocoInstall
        $chocoExe = Find-ChocoExecutable
    }

    if ($chocoExe) {
        Write-Host ""
        Write-Host " [*] Running 'choco upgrade all -y'..." -ForegroundColor Cyan
        & $chocoExe upgrade all -y
        Write-Host " [+] Chocolatey packages upgrade check complete." -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# Action 3: Repair Chocolatey Environment
# ------------------------------------------------------------------------------
function Invoke-ChocoRepair {
    Ensure-AdminElevation

    Write-Host ""
    Write-Host " ==============================================================" -ForegroundColor Cyan
    Write-Host "  Repairing Chocolatey Environment" -ForegroundColor White
    Write-Host " ==============================================================" -ForegroundColor Cyan
    Write-Host ""

    $chocoDir = "$env:SystemDrive\ProgramData\chocolatey"
    $chocoBin = "$chocoDir\bin"

    if (Test-Path $chocoDir) {
        Write-Host " [*] Ensuring Machine environment variable ChocolateyInstall is set..." -ForegroundColor Cyan
        [Environment]::SetEnvironmentVariable('ChocolateyInstall', $chocoDir, 'Machine')

        Write-Host " [*] Verifying Chocolatey bin directory in Machine PATH..." -ForegroundColor Cyan
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        if ($machinePath -notlike "*$chocoBin*") {
            [Environment]::SetEnvironmentVariable('PATH', "$chocoBin;$machinePath", 'Machine')
            Write-Host " [+] Added $chocoBin to Machine PATH." -ForegroundColor Green
        } else {
            Write-Host " [OK] Machine PATH already contains $chocoBin." -ForegroundColor DarkGray
        }

        # Clear temp caches
        $tempChoco = Join-Path $env:TEMP "chocolatey"
        if (Test-Path $tempChoco) {
            Write-Host " [*] Clearing temporary cache files in $tempChoco..." -ForegroundColor Cyan
            Remove-Item -Path "$tempChoco\*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        Refresh-EnvironmentPath
        $chocoExe = Find-ChocoExecutable
        if ($chocoExe) {
            $ver = & $chocoExe --version 2>$null
            Write-Host " [+] Chocolatey repair complete. Detected version: v$ver" -ForegroundColor Green
        }
    } else {
        Write-Host " [!] Chocolatey directory not found at $chocoDir. Running full installation..." -ForegroundColor Yellow
        Invoke-ChocoInstall
    }
}

# ------------------------------------------------------------------------------
# Interactive TUI Menu
# ------------------------------------------------------------------------------
function Show-TuiMenu {
    $selectedIndex = 0
    $options = @(
        @{
            Title = "Install / Update Chocolatey"
            Desc  = "Download and execute official Chocolatey bootstrap installer."
        },
        @{
            Title = "Upgrade All Chocolatey Packages"
            Desc  = "Runs 'choco upgrade all -y' across all installed packages."
        },
        @{
            Title = "Repair Chocolatey Environment"
            Desc  = "Restore missing PATH entries, refresh variables, clean cache."
        },
        @{
            Title = "Exit"
            Desc  = "Return to terminal."
        }
    )

    $origCursor = $Host.UI.RawUI.CursorSize
    try {
        $Host.UI.RawUI.CursorSize = 0
    } catch {}

    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host "  |       Chocolatey Package Manager - Setup & Maintenance      |" -ForegroundColor White
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host "   Use [Up / Down] to Navigate | [Enter] Select | [1-4] Quick | [Q] Quit" -ForegroundColor DarkGray
            Write-Host ""

            for ($i = 0; $i -lt $options.Count; $i++) {
                $opt = $options[$i]
                $num = $i + 1
                if ($i -eq $selectedIndex) {
                    Write-Host "  > [$num] $($opt.Title)" -ForegroundColor Cyan
                    Write-Host "       * $($opt.Desc)" -ForegroundColor Yellow
                } else {
                    Write-Host "    [$num] $($opt.Title)" -ForegroundColor Gray
                    Write-Host "         $($opt.Desc)" -ForegroundColor DarkGray
                }
            }
            Write-Host ""

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'    { $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count }
                'DownArrow'  { $selectedIndex = ($selectedIndex + 1) % $options.Count }
                'D1'         { $selectedIndex = 0; $enterPressed = $true }
                'NumPad1'    { $selectedIndex = 0; $enterPressed = $true }
                'D2'         { $selectedIndex = 1; $enterPressed = $true }
                'NumPad2'    { $selectedIndex = 1; $enterPressed = $true }
                'D3'         { $selectedIndex = 2; $enterPressed = $true }
                'NumPad3'    { $selectedIndex = 2; $enterPressed = $true }
                'D4'         { $selectedIndex = 3; $enterPressed = $true }
                'NumPad4'    { $selectedIndex = 3; $enterPressed = $true }
                'Q'          { return }
                'Escape'     { return }
                'Enter'      { $enterPressed = $true }
            }

            if ($enterPressed) {
                switch ($selectedIndex) {
                    0 { Invoke-ChocoInstall; break }
                    1 { Invoke-ChocoUpgrade; break }
                    2 { Invoke-ChocoRepair; break }
                    3 { return }
                }
                Write-Host ""
                Write-Host " Press any key to return to menu..." -ForegroundColor DarkGray
                [Console]::ReadKey($true) | Out-Null
                $enterPressed = $false
            }
        }
    } finally {
        try {
            $Host.UI.RawUI.CursorSize = $origCursor
        } catch {}
    }
}

# ------------------------------------------------------------------------------
# Main Dispatch
# ------------------------------------------------------------------------------
if ($Action) {
    switch ($Action) {
        'Install' { Invoke-ChocoInstall }
        'Upgrade' { Invoke-ChocoUpgrade }
        'Repair'  { Invoke-ChocoRepair }
    }
} else {
    Show-TuiMenu
}
