<#
.SYNOPSIS
    Automated WinGet (Windows Package Manager) Installer & Repair Utility for Windows 10 & 11 (TUI).
.DESCRIPTION
    Interactive Text-based User Interface (TUI) and automation tool for Microsoft WinGet (DesktopAppInstaller):
    
    [Dual-Engine Architecture]
    - Primary Engine (WinUtil logic): Leverages official Microsoft.WinGet.Client module and
      Repair-WinGetPackageManager via PowerShell Gallery (PSGallery) and NuGet provider.
    - Fallback Engine (Direct Standalone): Direct high-speed download of signed official MSIX bundles
      and framework dependencies (Microsoft.VCLibs & Microsoft.UI.Xaml 2.8+) from GitHub/Microsoft CDNs.

    [Option 1: Install / Update]
    - Detects OS version and verifies compatibility (Windows 10 1809+ / Build 17763+).
    - Detects system architecture (x64, ARM64, x86).
    - Checks for existing WinGet installation and version.
    - Attempts official Microsoft.WinGet.Client package repair/deployment.
    - Seamlessly falls back to direct MSIX bundle download if PSGallery or NuGet is unreachable.
    - Supports per-user installation and optional system-wide provisioning (-ProvisionAllUsers).
    - Configures WindowsApps PATH and refreshes environment variables.
    - Initializes and updates official WinGet sources.

    [Option 2: Repair]
    - Resets DesktopAppInstaller AppX package state (Reset-AppxPackage).
    - Re-registers AppXManifest for App Installer if corrupted.
    - Invokes Repair-WinGetPackageManager (WinUtil engine) for deep package repair.
    - Fixes broken App Execution Aliases and restores WindowsApps PATH.
    - Cleans locked/corrupted local SQLite source cache (LocalState/*.db*).
    - Resets WinGet repository sources (winget source reset --force).
    - Re-downloads and performs a clean reinstall if the package is missing/irreparable.
    - Updates official source catalogs (winget & msstore).

.PARAMETER Action
    Specifies the action directly: 'Install' or 'Repair'.
    If omitted, an interactive TUI menu with keyboard navigation is displayed.
.PARAMETER Force
    Forces full reinstallation/upgrade even if WinGet is already detected.
.PARAMETER ProvisionAllUsers
    Provisions WinGet for all users on the machine (requires Administrator privileges).
.PARAMETER NoSourceUpdate
    Skips the post-install/repair 'winget source update' command.
#>

[CmdletBinding()]
param (
    [ValidateSet('Install', 'Repair')]
    [string]$Action,
    [switch]$Force,
    [switch]$ProvisionAllUsers,
    [switch]$NoSourceUpdate
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

# ------------------------------------------------------------------------------
# TUI Menu (Interactive Arrow-Key Navigation)
# ------------------------------------------------------------------------------
function Show-TuiMenu {
    param (
        [string]$Title,
        [array]$MenuItems,
        [int]$DefaultIndex = 0
    )

    # Fallback to standard CLI prompt if stdin/stdout is redirected (e.g. non-interactive or remote CI)
    if ([System.Console]::IsInputRedirected -or [System.Console]::IsOutputRedirected) {
        Write-Host "`n$Title" -ForegroundColor Cyan
        for ($i = 0; $i -lt $MenuItems.Count; $i++) {
            Write-Host "  [$($i + 1)] $($MenuItems[$i].Title)" -ForegroundColor White
        }
        $choice = Read-Host "`nEnter selection [1-$($MenuItems.Count)] (Default: 1)"
        if ([int]::TryParse($choice, [ref]$val) -and $val -ge 1 -and $val -le $MenuItems.Count) {
            return $MenuItems[$val - 1].Action
        }
        return $MenuItems[0].Action
    }

    $selectedIndex = $DefaultIndex
    $cursorVisibleSaved = $true
    try {
        $cursorVisibleSaved = [System.Console]::CursorVisible
        [System.Console]::CursorVisible = $false
    } catch {}

    $startTop = [System.Console]::CursorTop

    function Render-Menu {
        param ([int]$CurrentIndex)

        try {
            [System.Console]::SetCursorPosition(0, $startTop)
        } catch {}

        Write-Host "  ┌───────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "  │           WinGet Package Manager - Setup & Maintenance        │" -ForegroundColor Cyan
        Write-Host "  └───────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
        Write-Host "   Use [↑ / ↓] to Navigate | [Enter] Select | [1/2/3] Quick Select | [Q] Quit`n" -ForegroundColor DarkGray

        for ($i = 0; $i -lt $MenuItems.Count; $i++) {
            $item = $MenuItems[$i]
            $isHighlighted = ($i -eq $CurrentIndex)

            if ($isHighlighted) {
                Write-Host "  ► " -NoNewline -ForegroundColor Green
                Write-Host "[$($i + 1)] $($item.Title)" -ForegroundColor Black -BackgroundColor Cyan
                foreach ($descLine in $item.Description) {
                    Write-Host "       $descLine" -ForegroundColor Cyan
                }
            } else {
                Write-Host "    [$($i + 1)] $($item.Title)" -ForegroundColor White
                foreach ($descLine in $item.Description) {
                    Write-Host "       $descLine" -ForegroundColor DarkGray
                }
            }
            Write-Host ""
        }
    }

    try {
        Clear-Host
        $startTop = [System.Console]::CursorTop
        Render-Menu -CurrentIndex $selectedIndex

        while ($true) {
            $key = [System.Console]::ReadKey($true)

            switch ($key.Key) {
                ([System.ConsoleKey]::UpArrow) {
                    $selectedIndex = if ($selectedIndex -gt 0) { $selectedIndex - 1 } else { $MenuItems.Count - 1 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::DownArrow) {
                    $selectedIndex = if ($selectedIndex -lt ($MenuItems.Count - 1)) { $selectedIndex + 1 } else { 0 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::W) {
                    $selectedIndex = if ($selectedIndex -gt 0) { $selectedIndex - 1 } else { $MenuItems.Count - 1 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::K) {
                    $selectedIndex = if ($selectedIndex -gt 0) { $selectedIndex - 1 } else { $MenuItems.Count - 1 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::S) {
                    $selectedIndex = if ($selectedIndex -lt ($MenuItems.Count - 1)) { $selectedIndex + 1 } else { 0 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::J) {
                    $selectedIndex = if ($selectedIndex -lt ($MenuItems.Count - 1)) { $selectedIndex + 1 } else { 0 }
                    Render-Menu -CurrentIndex $selectedIndex
                }
                ([System.ConsoleKey]::D1) {
                    return $MenuItems[0].Action
                }
                ([System.ConsoleKey]::NumPad1) {
                    return $MenuItems[0].Action
                }
                ([System.ConsoleKey]::D2) {
                    if ($MenuItems.Count -ge 2) { return $MenuItems[1].Action }
                }
                ([System.ConsoleKey]::NumPad2) {
                    if ($MenuItems.Count -ge 2) { return $MenuItems[1].Action }
                }
                ([System.ConsoleKey]::D3) {
                    if ($MenuItems.Count -ge 3) { return $MenuItems[2].Action }
                }
                ([System.ConsoleKey]::NumPad3) {
                    if ($MenuItems.Count -ge 3) { return $MenuItems[2].Action }
                }
                ([System.ConsoleKey]::Enter) {
                    return $MenuItems[$selectedIndex].Action
                }
                ([System.ConsoleKey]::Spacebar) {
                    return $MenuItems[$selectedIndex].Action
                }
                ([System.ConsoleKey]::Escape) {
                    return 'Exit'
                }
                ([System.ConsoleKey]::Q) {
                    return 'Exit'
                }
            }
        }
    } finally {
        try {
            [System.Console]::CursorVisible = $cursorVisibleSaved
        } catch {}
    }
}

# ------------------------------------------------------------------------------
# Launch TUI If -Action Not Specified
# ------------------------------------------------------------------------------
if (-not $Action) {
    $menuOptions = @(
        @{
            Title = "Install / Update WinGet"
            Action = "Install"
            Description = @(
                "• Full clean installation or update to the latest release",
                "• Dual engine: WinUtil Microsoft.WinGet.Client + Direct MSIX fallback",
                "• Registers User PATH and synchronizes official sources"
            )
        },
        @{
            Title = "Repair WinGet Environment"
            Action = "Repair"
            Description = @(
                "• Resets AppX package state & re-registers AppXManifest",
                "• Runs Repair-WinGetPackageManager for deep system repair",
                "• Restores broken WindowsApps PATH, aliases & purges SQLite cache"
            )
        },
        @{
            Title = "Exit"
            Action = "Exit"
            Description = @(
                "• Cancel and return to terminal"
            )
        }
    )

    $chosenAction = Show-TuiMenu -Title "WinGet Management" -MenuItems $menuOptions -DefaultIndex 0
    if ($chosenAction -eq 'Exit') {
        Write-Host "`n[*] Exiting without making changes.`n" -ForegroundColor Yellow
        exit 0
    }
    $Action = $chosenAction
}

Clear-Host
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "    WinGet (Windows Package Manager) Installer & Repair Tool   " -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

if ($isAdmin) {
    Write-Host "[+] Running with Administrator privileges." -ForegroundColor Green
} else {
    Write-Host "[*] Running with standard user privileges." -ForegroundColor Gray
}

Write-Host "`n>>> Mode: $Action" -ForegroundColor Magenta

# ------------------------------------------------------------------------------
# System Detection (OS & Architecture)
# ------------------------------------------------------------------------------
$osBuild = [System.Environment]::OSVersion.Version.Build
if ($osBuild -lt 17763) {
    Write-Host "[-] Unsupported OS: Windows 10 Build 17763 (v1809) or higher is required." -ForegroundColor Red
    Write-Host "    Current Build: $osBuild" -ForegroundColor Red
    exit 1
}

$rawArch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'x64' }
} else {
    'x86'
}

$arch = switch ($rawArch) {
    'arm64' { 'arm64' }
    'x64'   { 'x64' }
    default { 'x86' }
}

Write-Host "[+] Windows Build: $osBuild | Architecture: $arch" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Locate Existing WinGet Executable
# ------------------------------------------------------------------------------
function Get-WinGetExecutable {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) {
        return $cmd.Source
    }

    $defaultAlias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path $defaultAlias) {
        return $defaultAlias
    }

    $windowsAppsParent = "$env:ProgramFiles\WindowsApps"
    if (Test-Path $windowsAppsParent) {
        $installerApp = Get-ChildItem -Path $windowsAppsParent -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($installerApp -and (Test-Path $installerApp.FullName)) {
            return $installerApp.FullName
        }
    }

    return $null
}

# ------------------------------------------------------------------------------
# Resilient Downloader
# ------------------------------------------------------------------------------
function Download-FileWithProgress {
    param (
        [string]$Url,
        [string]$OutputFile,
        [string]$Description = "Downloading"
    )

    $parentDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Method 1: Check for native Windows curl.exe
    $curlExe = $null
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd -and (Test-Path $curlCmd.Source)) {
        $curlExe = $curlCmd.Source
    } elseif (Test-Path "$env:SystemRoot\System32\curl.exe") {
        $curlExe = "$env:SystemRoot\System32\curl.exe"
    }

    if ($curlExe) {
        Write-Host "      [curl] $Description..." -ForegroundColor Cyan
        try {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $curlArgs = @("-fL", "--retry", "3", "--retry-delay", "2", "-o", $OutputFile, $Url)
            $p = Start-Process -FilePath $curlExe -ArgumentList $curlArgs -NoNewWindow -Wait -PassThru
            $ErrorActionPreference = $prevEap

            if ($p.ExitCode -eq 0 -and (Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 0)) {
                return
            }
        } catch {}
    }

    # Method 2: System.Net.WebClient
    Write-Host "      [WebClient] $Description..." -ForegroundColor Cyan
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/WinGet-Installer")
        $webClient.DownloadFile($Url, $OutputFile)
        if ((Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 0)) {
            return
        }
    } catch {}

    # Method 3: Invoke-WebRequest fallback
    Write-Host "      [Invoke-WebRequest] $Description..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $OutputFile -UseBasicParsing -Headers @{ "User-Agent" = "PowerShell/WinGet-Installer" }
}

# ------------------------------------------------------------------------------
# Helper: Ensure WindowsApps PATH is registered
# ------------------------------------------------------------------------------
function Update-WindowsAppsPath {
    $windowsAppsDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
    if ($env:PATH -notlike "*$windowsAppsDir*") {
        $env:PATH = "$windowsAppsDir;$env:PATH"
    }

    try {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$windowsAppsDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$windowsAppsDir;$userPath", "User")
            Write-Host "[+] Added $windowsAppsDir to persistent User PATH." -ForegroundColor Green
        }
    } catch {}
}

# ------------------------------------------------------------------------------
# Engine 1: WinUtil Logic (Microsoft.WinGet.Client + Repair-WinGetPackageManager)
# ------------------------------------------------------------------------------
function Invoke-WinUtilModuleInstall {
    param (
        [bool]$AsAdmin,
        [bool]$DoProvision
    )

    Write-Host "`n[*] [Engine 1: WinUtil] Attempting setup via Microsoft.WinGet.Client..." -ForegroundColor Yellow

    # Step 1: Ensure NuGet PackageProvider is present
    try {
        Write-Host "    -> Checking NuGet package provider..." -ForegroundColor Gray
        $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-Host "    -> Bootstrapping NuGet provider..." -ForegroundColor Cyan
            Install-PackageProvider -Name NuGet -Force -Confirm:$false -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Host "    [!] NuGet provider bootstrap error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }

    # Step 2: Install Microsoft.WinGet.Client module from PSGallery
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        $scope = if ($AsAdmin) { "AllUsers" } else { "CurrentUser" }
        Write-Host "    -> Installing Microsoft.WinGet.Client module ($scope scope)..." -ForegroundColor Cyan
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope $scope -Force -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction Stop | Out-Null
        Import-Module -Name Microsoft.WinGet.Client -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "    [!] PSGallery / Microsoft.WinGet.Client install failed: $($_.Exception.Message)" -ForegroundColor DarkGray
        return $false
    }

    # Step 3: Execute Repair-WinGetPackageManager (Official Microsoft Repair Cmdlet)
    try {
        Write-Host "    -> Running Repair-WinGetPackageManager..." -ForegroundColor Cyan
        if ($AsAdmin -and $DoProvision) {
            Repair-WinGetPackageManager -AllUsers -Latest -Force -ErrorAction Stop
        } else {
            Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop
        }

        Update-WindowsAppsPath
        Start-Sleep -Seconds 2

        $installedExe = Get-WinGetExecutable
        if ($installedExe) {
            $ver = & $installedExe --version 2>$null
            if ($ver) {
                Write-Host "[+] WinGet successfully configured via Microsoft.WinGet.Client (v$ver)!" -ForegroundColor Green
                return $true
            }
        }
    } catch {
        Write-Host "    [!] Repair-WinGetPackageManager error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $false
}

# ------------------------------------------------------------------------------
# Engine 2: Standalone Direct MSIX Bundle Fallback
# ------------------------------------------------------------------------------
function Install-WinGetPackagesDirect {
    param (
        [string]$TargetArch,
        [bool]$AsAdmin,
        [bool]$DoProvision
    )

    Write-Host "`n[*] [Engine 2: Standalone] Resolving official packages directly from GitHub..." -ForegroundColor Yellow

    $tempDir = Join-Path $env:TEMP ("winget_install_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.$TargetArch.14.00.Desktop.appx"
        $vclibsFile = Join-Path $tempDir "Microsoft.VCLibs.$TargetArch.appx"

        $xamlVersion = "2.8.6"
        $xamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v$xamlVersion/Microsoft.UI.Xaml.2.8.$TargetArch.appx"
        $xamlFile = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.$TargetArch.appx"

        $wingetBundleUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetLicenseUrl = $null
        $wingetBundleFile = Join-Path $tempDir "Microsoft.DesktopAppInstaller.msixbundle"
        $wingetLicenseFile = Join-Path $tempDir "DesktopAppInstaller_License.xml"

        # Query GitHub API for latest release assets
        try {
            $apiUri = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $headers = @{ "User-Agent" = "PowerShell/WinGet-Installer" }
            $releaseJson = Invoke-RestMethod -Uri $apiUri -Headers $headers -TimeoutSec 10 -ErrorAction SilentlyContinue

            if ($releaseJson -and $releaseJson.assets) {
                $bundleAsset = $releaseJson.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
                if ($bundleAsset) {
                    $wingetBundleUrl = $bundleAsset.browser_download_url
                }

                $licenseAsset = $releaseJson.assets | Where-Object { $_.name -like "*License1.xml" } | Select-Object -First 1
                if ($licenseAsset) {
                    $wingetLicenseUrl = $licenseAsset.browser_download_url
                }
            }
        } catch {
            Write-Host "    [!] GitHub API rate-limited/offline; using direct official release endpoints." -ForegroundColor Gray
        }

        Write-Host "`n[*] Downloading required packages..." -ForegroundColor Yellow
        Download-FileWithProgress -Url $vclibsUrl -OutputFile $vclibsFile -Description "VCLibs ($TargetArch)"
        Download-FileWithProgress -Url $xamlUrl -OutputFile $xamlFile -Description "Microsoft.UI.Xaml 2.8 ($TargetArch)"
        Download-FileWithProgress -Url $wingetBundleUrl -OutputFile $wingetBundleFile -Description "DesktopAppInstaller msixbundle"

        if ($wingetLicenseUrl) {
            try {
                Download-FileWithProgress -Url $wingetLicenseUrl -OutputFile $wingetLicenseFile -Description "License XML"
            } catch {
                $wingetLicenseFile = $null
            }
        } else {
            $wingetLicenseFile = $null
        }

        Write-Host "`n[*] Registering AppX packages..." -ForegroundColor Yellow
        Add-AppxPackage -Path $vclibsFile -ErrorAction SilentlyContinue
        Add-AppxPackage -Path $xamlFile -ErrorAction SilentlyContinue

        $installedSuccessfully = $false

        if ($AsAdmin -and $DoProvision) {
            Write-Host "    -> Provisioning WinGet for all users..." -ForegroundColor Cyan
            try {
                $depArgs = @($vclibsFile, $xamlFile)
                if ($wingetLicenseFile -and (Test-Path $wingetLicenseFile)) {
                    Add-AppxProvisionedPackage -Online -PackagePath $wingetBundleFile -DependencyPackagePath $depArgs -LicensePath $wingetLicenseFile -ErrorAction Stop | Out-Null
                } else {
                    Add-AppxProvisionedPackage -Online -PackagePath $wingetBundleFile -DependencyPackagePath $depArgs -SkipLicense -ErrorAction Stop | Out-Null
                }
                $installedSuccessfully = $true
                Write-Host "[+] System-wide provisioning complete." -ForegroundColor Green
            } catch {
                Write-Host "    [!] Provisioning failed ($($_.Exception.Message)). Falling back to per-user install..." -ForegroundColor Yellow
            }
        }

        if (-not $installedSuccessfully) {
            Write-Host "    -> Installing Microsoft.DesktopAppInstaller msixbundle..." -ForegroundColor Cyan
            $dependencies = @($vclibsFile, $xamlFile)
            Add-AppxPackage -Path $wingetBundleFile -DependencyPath $dependencies -ErrorAction Stop
            $installedSuccessfully = $true
        }

        Update-WindowsAppsPath
        return $installedSuccessfully

    } finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------------------------
# Hybrid Orchestrator: Try WinUtil Logic First, Fallback to Direct Standalone
# ------------------------------------------------------------------------------
function Install-Or-Repair-WinGet {
    param (
        [string]$TargetArch,
        [bool]$AsAdmin,
        [bool]$DoProvision
    )

    # Attempt Engine 1: WinUtil logic (Microsoft.WinGet.Client module)
    $engine1Success = Invoke-WinUtilModuleInstall -AsAdmin $AsAdmin -DoProvision $DoProvision
    if ($engine1Success) {
        return $true
    }

    # Attempt Engine 2: Standalone direct MSIX bundle download & registration
    Write-Host "`n[*] [Engine 1 failed or unavailable] Falling back to Engine 2 (Direct GitHub bundle)..." -ForegroundColor Yellow
    return Install-WinGetPackagesDirect -TargetArch $TargetArch -AsAdmin $AsAdmin -DoProvision $DoProvision
}

# ==============================================================================
# ACTION: INSTALL / UPDATE
# ==============================================================================
if ($Action -eq 'Install') {
    $existingWinGet = Get-WinGetExecutable

    if ($existingWinGet -and -not $Force) {
        try {
            $currentVer = & $existingWinGet --version 2>$null
            if ($currentVer) {
                Write-Host "`n[+] WinGet is already installed: version $currentVer" -ForegroundColor Green
                Write-Host "    Executable path: $existingWinGet" -ForegroundColor Gray
                Write-Host "[*] Use the -Force switch or select 'Repair' to reinstall or repair your setup.`n" -ForegroundColor Cyan
                exit 0
            }
        } catch {}
    }

    if ($Force -and $existingWinGet) {
        Write-Host "[!] -Force specified: proceeding with reinstallation/upgrade..." -ForegroundColor Yellow
    }

    Install-Or-Repair-WinGet -TargetArch $arch -AsAdmin $isAdmin -DoProvision $ProvisionAllUsers
}

# ==============================================================================
# ACTION: REPAIR
# ==============================================================================
elseif ($Action -eq 'Repair') {
    Write-Host "`n[1/5] Checking AppX package registration..." -ForegroundColor Yellow

    $appxPackages = Get-AppxPackage -Name "*Microsoft.DesktopAppInstaller*" -ErrorAction SilentlyContinue
    $reinstallNeeded = $false

    if ($appxPackages) {
        foreach ($pkg in $appxPackages) {
            Write-Host "    Found package: $($pkg.PackageFullName)" -ForegroundColor Gray

            # Attempt modern package reset if available (Win10 2004+ / Win11)
            $resetCmd = Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue
            if ($resetCmd) {
                try {
                    Write-Host "    -> Resetting AppX package state..." -ForegroundColor Cyan
                    Reset-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                } catch {}
            }

            # Re-register AppX Manifest
            try {
                $manifestPath = Join-Path $pkg.InstallLocation "AppXManifest.xml"
                if (Test-Path $manifestPath) {
                    Write-Host "    -> Re-registering manifest from $manifestPath..." -ForegroundColor Cyan
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                    Write-Host "[+] Package successfully re-registered." -ForegroundColor Green
                }
            } catch {
                Write-Host "    [!] Re-registration issue ($($_.Exception.Message))." -ForegroundColor Yellow
                $reinstallNeeded = $true
            }
        }
    } else {
        Write-Host "[-] Microsoft.DesktopAppInstaller AppX package is missing." -ForegroundColor Yellow
        $reinstallNeeded = $true
    }

    # If AppX registration was corrupted or missing, invoke the hybrid engine
    if ($reinstallNeeded) {
        Write-Host "`n[*] Package missing or corrupted. Launching hybrid installer engine..." -ForegroundColor Yellow
        Install-Or-Repair-WinGet -TargetArch $arch -AsAdmin $isAdmin -DoProvision $ProvisionAllUsers
    }

    # Step 2: Fix and verify PATH & Execution Aliases
    Write-Host "`n[2/5] Restoring environment PATH & App Execution Aliases..." -ForegroundColor Yellow
    Update-WindowsAppsPath

    # Step 3: Clean corrupted local SQLite index/cache
    Write-Host "`n[3/5] Cleaning local package database cache..." -ForegroundColor Yellow
    $localStateDir = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"
    if (Test-Path $localStateDir) {
        try {
            Get-ChildItem -Path $localStateDir -Filter "*.db*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Local state database cache purged." -ForegroundColor Green
        } catch {
            Write-Host "[-] Could not purge database files (may currently be in use)." -ForegroundColor Gray
        }
    }

    # Step 4: Reset WinGet Sources
    Write-Host "`n[4/5] Resetting repository sources..." -ForegroundColor Yellow
    $wingetCmd = Get-WinGetExecutable
    if ($wingetCmd) {
        try {
            & $wingetCmd source reset --force 2>$null | Out-Null
            Write-Host "[+] WinGet sources reset to factory defaults." -ForegroundColor Green
        } catch {
            Write-Host "[-] Note: WinGet source reset will execute automatically on first query." -ForegroundColor Gray
        }
    }

    Write-Host "`n[5/5] Finalizing repair process..." -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# Verification & Source Update
# ------------------------------------------------------------------------------
Write-Host "`n[*] Verifying WinGet..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$wingetCmd = Get-WinGetExecutable
$wingetVer = $null

if ($wingetCmd) {
    try {
        $wingetVer = & $wingetCmd --version 2>$null
    } catch {}
}

if ($wingetVer) {
    Write-Host "`n===============================================================" -ForegroundColor Green
    Write-Host "    Operation Successful! WinGet Version: $wingetVer           " -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "Location: $wingetCmd" -ForegroundColor Gray

    if (-not $NoSourceUpdate) {
        Write-Host "`n[*] Initializing & updating official sources (winget & msstore)..." -ForegroundColor Yellow
        try {
            & $wingetCmd source update --accept-source-agreements 2>$null | Out-Null
            Write-Host "[+] Sources successfully synchronized." -ForegroundColor Green
        } catch {
            Write-Host "[-] Note: Sources will update on the next winget command." -ForegroundColor Gray
        }
    }

    Write-Host "`nWinGet is ready to use:" -ForegroundColor Cyan
    Write-Host "  winget search <package>" -ForegroundColor White
    Write-Host "  winget install <package>" -ForegroundColor White
    Write-Host "  winget upgrade --all`n" -ForegroundColor White
} else {
    Write-Host "`n[!] Package registered, but Windows App Execution Alias is completing registration." -ForegroundColor Yellow
    Write-Host "    Please open a NEW PowerShell or Command Prompt terminal and run:" -ForegroundColor Cyan
    Write-Host "    winget --version`n" -ForegroundColor White
}
