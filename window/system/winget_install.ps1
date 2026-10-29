<#
.SYNOPSIS
    Automated WinGet (Windows Package Manager) Installer for Windows 10 & 11.
.DESCRIPTION
    PowerShell installer for Microsoft WinGet (DesktopAppInstaller):
    - Detects OS version and verifies compatibility (Windows 10 1809+ / Build 17763+).
    - Detects system architecture (x64, ARM64, x86).
    - Checks for existing WinGet installation and version.
    - Downloads required dependencies:
        * Microsoft.VCLibs (UWP Desktop)
        * Microsoft.UI.Xaml 2.8+
        * Latest Microsoft.DesktopAppInstaller msixbundle & License from GitHub.
    - Installs AppX package with full dependency resolution.
    - Supports per-user installation and optional system-wide provisioning (-ProvisionAllUsers).
    - Configures WindowsApps PATH and refreshes environment variables.
    - Initializes and updates official WinGet sources.
.PARAMETER Force
    Forces reinstallation or upgrade even if WinGet is already detected.
.PARAMETER ProvisionAllUsers
    Provisions WinGet for all users on the machine (requires Administrator privileges).
.PARAMETER NoSourceUpdate
    Skips the post-install 'winget source update' command.
#>

[CmdletBinding()]
param (
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

Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "     WinGet (Windows Package Manager) Installer for Win 10/11   " -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# Helper: Check Administrator Privileges
# ------------------------------------------------------------------------------
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-IsAdmin
if ($isAdmin) {
    Write-Host "[+] Running with Administrator privileges." -ForegroundColor Green
} else {
    Write-Host "[*] Running with standard user privileges." -ForegroundColor Gray
}

# ------------------------------------------------------------------------------
# Step 1: OS Compatibility & Architecture Detection
# ------------------------------------------------------------------------------
Write-Host "`n[*] Detecting system architecture and OS build..." -ForegroundColor Yellow

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

Write-Host "[+] Windows Build: $osBuild" -ForegroundColor Green
Write-Host "[+] Architecture:  $arch" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 2: Check Existing WinGet Installation
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

    return $null
}

$existingWinGet = Get-WinGetExecutable
if ($existingWinGet -and -not $Force) {
    try {
        $currentVersion = & $existingWinGet --version 2>$null
        if ($currentVersion) {
            Write-Host "`n[+] WinGet is already installed: version $currentVersion" -ForegroundColor Green
            Write-Host "    Executable path: $existingWinGet" -ForegroundColor Gray
            Write-Host "[*] If you wish to reinstall or force-update, run with the -Force switch:" -ForegroundColor Cyan
            Write-Host "    .\winget_install.ps1 -Force`n" -ForegroundColor White
            exit 0
        }
    } catch {}
}

if ($Force -and $existingWinGet) {
    Write-Host "[!] -Force specified: proceeding with reinstallation/upgrade..." -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# Step 3: High-Speed / Resilient Downloader
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
# Step 4: Resolve Download URLs
# ------------------------------------------------------------------------------
$tempDir = Join-Path $env:TEMP ("winget_install_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Host "`n[*] Resolving latest WinGet package and dependencies..." -ForegroundColor Yellow

    # Dependency 1: Microsoft.VCLibs.140.00.UWPDesktop
    $vclibsUrl = "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx"
    $vclibsFile = Join-Path $tempDir "Microsoft.VCLibs.$arch.appx"

    # Dependency 2: Microsoft.UI.Xaml 2.8+
    $xamlVersion = "2.8.6"
    $xamlUrl = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v$xamlVersion/Microsoft.UI.Xaml.2.8.$arch.appx"
    $xamlFile = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.$arch.appx"

    # WinGet msixbundle and License XML from GitHub
    $wingetBundleUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $wingetLicenseUrl = $null
    $wingetBundleFile = Join-Path $tempDir "Microsoft.DesktopAppInstaller.msixbundle"
    $wingetLicenseFile = Join-Path $tempDir "DesktopAppInstaller_License.xml"

    # Query GitHub API to discover exact release assets and license XML
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
        Write-Host "    [!] GitHub API rate-limit/offline, using direct official release endpoints." -ForegroundColor Gray
    }

    # ------------------------------------------------------------------------------
    # Step 5: Download Packages
    # ------------------------------------------------------------------------------
    Write-Host "`n[*] Downloading dependencies..." -ForegroundColor Yellow
    Download-FileWithProgress -Url $vclibsUrl -OutputFile $vclibsFile -Description "VCLibs ($arch)"
    Download-FileWithProgress -Url $xamlUrl -OutputFile $xamlFile -Description "Microsoft.UI.Xaml 2.8 ($arch)"

    Write-Host "`n[*] Downloading WinGet (DesktopAppInstaller)..." -ForegroundColor Yellow
    Download-FileWithProgress -Url $wingetBundleUrl -OutputFile $wingetBundleFile -Description "DesktopAppInstaller bundle"

    if ($wingetLicenseUrl) {
        try {
            Download-FileWithProgress -Url $wingetLicenseUrl -OutputFile $wingetLicenseFile -Description "License XML"
        } catch {
            $wingetLicenseFile = $null
        }
    } else {
        $wingetLicenseFile = $null
    }

    # ------------------------------------------------------------------------------
    # Step 6: Install WinGet & Dependencies
    # ------------------------------------------------------------------------------
    Write-Host "`n[*] Installing packages..." -ForegroundColor Yellow

    # Install VCLibs and UI.Xaml dependencies
    Write-Host "    -> Registering VCLibs..." -ForegroundColor Gray
    Add-AppxPackage -Path $vclibsFile -ErrorAction SilentlyContinue

    Write-Host "    -> Registering Microsoft.UI.Xaml..." -ForegroundColor Gray
    Add-AppxPackage -Path $xamlFile -ErrorAction SilentlyContinue

    # Install WinGet
    $installedSuccessfully = $false

    # Option A: System-wide provisioning if Admin and requested
    if ($isAdmin -and $ProvisionAllUsers) {
        Write-Host "    -> Provisioning WinGet system-wide for all users..." -ForegroundColor Cyan
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

    # Option B: Per-user installation (standard)
    if (-not $installedSuccessfully) {
        Write-Host "    -> Installing Microsoft.DesktopAppInstaller msixbundle..." -ForegroundColor Cyan
        $dependencies = @($vclibsFile, $xamlFile)
        Add-AppxPackage -Path $wingetBundleFile -DependencyPath $dependencies -ErrorAction Stop
        $installedSuccessfully = $true
    }

    # ------------------------------------------------------------------------------
    # Step 7: Configure Environment & PATH
    # ------------------------------------------------------------------------------
    Write-Host "`n[*] Refreshing environment PATH..." -ForegroundColor Yellow
    $windowsAppsDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"

    # Add to current process PATH
    if ($env:PATH -notlike "*$windowsAppsDir*") {
        $env:PATH = "$windowsAppsDir;$env:PATH"
    }

    # Ensure it's persistently stored in User PATH
    try {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$windowsAppsDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$windowsAppsDir;$userPath", "User")
        }
    } catch {}

    # ------------------------------------------------------------------------------
    # Step 8: Verification & Source Initialization
    # ------------------------------------------------------------------------------
    Write-Host "`n[*] Verifying WinGet installation..." -ForegroundColor Yellow

    # Pause briefly for Windows app execution alias registration
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
        Write-Host "     WinGet successfully installed! Version: $wingetVer        " -ForegroundColor Green
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host "Location: $wingetCmd" -ForegroundColor Gray

        if (-not $NoSourceUpdate) {
            Write-Host "`n[*] Initializing official WinGet sources (winget & msstore)..." -ForegroundColor Yellow
            try {
                & $wingetCmd source update --accept-source-agreements 2>$null | Out-Null
                Write-Host "[+] Sources updated successfully." -ForegroundColor Green
            } catch {
                Write-Host "[-] Note: Sources will automatically update on first package search/install." -ForegroundColor Gray
            }
        }

        Write-Host "`nYou can now use winget in any PowerShell or Command Prompt terminal:" -ForegroundColor Cyan
        Write-Host "  winget search <package>" -ForegroundColor White
        Write-Host "  winget install <package>" -ForegroundColor White
        Write-Host "  winget upgrade --all`n" -ForegroundColor White
    } else {
        Write-Host "`n[!] WinGet package was registered, but the CLI alias is still initializing." -ForegroundColor Yellow
        Write-Host "    Please open a NEW PowerShell or Command Prompt window and run:" -ForegroundColor Cyan
        Write-Host "    winget --version`n" -ForegroundColor White
    }

} catch {
    Write-Host "`n[-] Error during WinGet installation: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Cleanup temporary files
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
