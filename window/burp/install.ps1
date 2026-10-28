<#
.SYNOPSIS
    Automated Burp Suite Professional Installer for Windows.
.DESCRIPTION
    Full-featured PowerShell port of arch/apps/burp/install.sh.
    - Deep Java 21+ detection (PATH, Registry, Program Files).
    - Auto-installs Java 21 via winget (with silent MSI fallback).
    - Dynamically queries PortSwigger release API for the latest Pro JAR.
    - Downloads key loader with failover mirrors.
    - Generates silent launchers (Burp.bat & Burp-Suite-Pro.vbs).
    - Creates Desktop & Start Menu shortcuts with the official .ico icon.
    - Registers CLI command in User PATH for terminal access.
    - Auto-starts key loader and Burp Suite Pro.
#>

[CmdletBinding()]
param (
    [string]$InstallPath = "$env:USERPROFILE\Documents\Crack\Burpsuite-Professional",
    [switch]$SkipLaunch,
    [switch]$ForceDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Ensure modern TLS 1.2 and TLS 1.3 are enabled for downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Host @"
===============================================================
       Burp Suite Professional Installer for Windows
===============================================================
"@ -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Directory Initialization
# ------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Get-Location
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallPath)
Write-Host "[1/8] Setting up installation target: $InstallDir" -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "      Created directory: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "      Target directory exists." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 2. Comprehensive Java 21+ Detection & Auto-Installation (winget + fallback)
# ------------------------------------------------------------------------------
Write-Host "`n[2/8] Checking Java runtime environment (Requires Java 21+)..." -ForegroundColor Cyan

function Refresh-EnvironmentPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-JavaVersion {
    param ([string]$ExecutablePath)
    try {
        if (-not (Test-Path $ExecutablePath)) { return $null }
        $out = & $ExecutablePath -version 2>&1 | Out-String
        if ($out -match 'version "(\d+)(\.[\d\._]+)?"') {
            $major = [int]$matches[1]
            return [PSCustomObject]@{
                Path    = $ExecutablePath
                Major   = $major
                Raw     = $out.Trim()
            }
        }
    } catch {}
    return $null
}

Refresh-EnvironmentPath

$validJava = $null

# 2A. Check Java in current PATH
$javaInPath = Get-Command java.exe -ErrorAction SilentlyContinue
if ($javaInPath) {
    $testResult = Test-JavaVersion -ExecutablePath $javaInPath.Source
    if ($testResult -and $testResult.Major -ge 21) {
        $validJava = $testResult
        Write-Host "      [✓] Compatible Java found in PATH: Java $($validJava.Major) ($($validJava.Path))" -ForegroundColor Green
    } elseif ($testResult) {
        Write-Host "      [!] Java in PATH is version $($testResult.Major) (Burp Suite Pro requires Java 21+)." -ForegroundColor Yellow
    }
}

# 2B. Check Registry and Program Files if not found in PATH
if (-not $validJava) {
    Write-Host "      Scanning registry and disk for existing JDK 21+ installations..." -ForegroundColor DarkCyan
    $searchPatterns = @(
        "$env:ProgramFiles\Java\jdk-2*\bin\java.exe",
        "$env:ProgramFiles\Eclipse Adoptium\jdk-2*\bin\java.exe",
        "$env:ProgramFiles\Microsoft\jdk-2*\bin\java.exe",
        "${env:ProgramFiles(x86)}\Java\jdk-2*\bin\java.exe",
        "$env:LOCALAPPDATA\Programs\Eclipse Adoptium\jdk-2*\bin\java.exe"
    )

    $candidates = Resolve-Path $searchPatterns -ErrorAction SilentlyContinue
    foreach ($cand in $candidates) {
        $testResult = Test-JavaVersion -ExecutablePath $cand.Path
        if ($testResult -and $testResult.Major -ge 21) {
            $validJava = $testResult
            $javaBin = Split-Path -Parent $validJava.Path
            $env:Path = "$javaBin;" + $env:Path
            Write-Host "      [✓] Found installed JDK $($validJava.Major) at: $($validJava.Path)" -ForegroundColor Green
            break
        }
    }
}

# 2C. If Java 21+ is missing, install via winget or direct MSI fallback
if (-not $validJava) {
    Write-Host "      [!] Java 21+ was not detected on this system." -ForegroundColor Yellow
    $installedViaWinget = $false

    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "      Attempting automated installation via winget..." -ForegroundColor Cyan
        $wingetPackages = @("Microsoft.OpenJDK.21", "EclipseAdoptium.Temurin.21.JDK", "Oracle.JDK.21")

        foreach ($pkg in $wingetPackages) {
            Write-Host "      Installing $pkg via winget..." -ForegroundColor Yellow
            try {
                $process = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $pkg -e --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
                if ($process.ExitCode -eq 0) {
                    Write-Host "      [✓] Successfully installed $pkg via winget!" -ForegroundColor Green
                    $installedViaWinget = $true
                    break
                }
            } catch {
                Write-Host "      Winget install of $pkg encountered an issue, trying next option..." -ForegroundColor DarkGray
            }
        }
    }

    # Direct MSI download fallback if winget is absent or fails
    if (-not $installedViaWinget) {
        Write-Host "      Winget unavailable or failed. Falling back to direct Adoptium OpenJDK 21 MSI installer..." -ForegroundColor Yellow
        $msiUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/OpenJDK21U-jdk_x64_windows_hotspot_21.0.6_7.msi"
        $msiFile = Join-Path $env:TEMP "temurin21_installer.msi"

        Write-Host "      Downloading JDK 21 installer from Adoptium..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiFile

        Write-Host "      Running silent MSI installer..." -ForegroundColor Cyan
        $installArgs = "/i `"$msiFile`" /quiet /qn /norestart ADDLOCAL=FeatureMain,FeatureJavaHome,FeatureJarFileRunWith,FeatureNavigator"
        $msiProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

        if (Test-Path $msiFile) { Remove-Item -Path $msiFile -Force -ErrorAction SilentlyContinue }

        if ($msiProcess.ExitCode -ne 0 -and $msiProcess.ExitCode -ne 3010) {
            Write-Warning "MSI installer exited with code $($msiProcess.ExitCode). Checking if Java is available..."
        }
    }

    # Refresh PATH and verify
    Refresh-EnvironmentPath
    $recheck = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($recheck) {
        $validJava = Test-JavaVersion -ExecutablePath $recheck.Source
    }

    if (-not $validJava) {
        # Check newly created program files directories
        $newPaths = Resolve-Path @(
            "$env:ProgramFiles\Eclipse Adoptium\jdk-21*\bin\java.exe",
            "$env:ProgramFiles\Microsoft\jdk-21*\bin\java.exe"
        ) -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($newPaths) {
            $validJava = Test-JavaVersion -ExecutablePath $newPaths.Path
            $javaBin = Split-Path -Parent $newPaths.Path
            $env:Path = "$javaBin;" + $env:Path
        }
    }

    if (-not $validJava) {
        Write-Error "ERROR: Could not verify Java 21+ installation. Please manually install JDK 21 from https://adoptium.net and rerun."
        exit 1
    } else {
        Write-Host "      [✓] Java 21+ verified successfully: $($validJava.Raw)" -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# 3. Dynamic Release Version Fetch from PortSwigger
# ------------------------------------------------------------------------------
Write-Host "`n[3/8] Fetching latest Burp Suite Professional version from PortSwigger..." -ForegroundColor Cyan
$BURP_VERSION = $null

try {
    $releases = Invoke-RestMethod -Uri "https://portswigger.net/burp/releases/data?pageSize=10" -Method Get -TimeoutSec 10
    if ($releases -and $releases.ResultSet -and $releases.ResultSet.Results) {
        foreach ($r in $releases.ResultSet.Results) {
            $hasJar = $r.builds | Where-Object { $_.BuildCategoryPlatform -eq "Jar" }
            if ($hasJar) {
                $BURP_VERSION = $r.version
                break
            }
        }
    }
} catch {
    Write-Warning "Could not query PortSwigger API: $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($BURP_VERSION)) {
    $BURP_VERSION = "2026.10.1"
    Write-Host "      Using fallback release version: $BURP_VERSION" -ForegroundColor Yellow
}

$JarName = "burpsuite_pro_v$BURP_VERSION.jar"
$DownloadUrl = "https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VERSION&type=Jar"
Write-Host "      Latest Pro Version: $BURP_VERSION" -ForegroundColor Green
Write-Host "      Target File:        $JarName" -ForegroundColor DarkGray

# ------------------------------------------------------------------------------
# 4. Download Key Loader
# ------------------------------------------------------------------------------
Write-Host "`n[4/8] Downloading key loader..." -ForegroundColor Cyan
$TargetLoader = Join-Path $InstallDir "loader.jar"
$loaderSources = @(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar",
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
)

$loaderDownloaded = $false
foreach ($url in $loaderSources) {
    try {
        Write-Host "      Fetching from $url ..." -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $TargetLoader
        if ((Test-Path $TargetLoader) -and ((Get-Item $TargetLoader).Length -gt 10240)) {
            Write-Host "      [✓] Loader verified ($((Get-Item $TargetLoader).Length) bytes)." -ForegroundColor Green
            $loaderDownloaded = $true
            break
        }
    } catch {
        Write-Warning "Download from $url failed."
    }
}

if (-not $loaderDownloaded) {
    Write-Error "ERROR: Failed to download a valid loader.jar. Check your internet connection."
    exit 1
}

# ------------------------------------------------------------------------------
# 5. Clean Old Versions & Download Burp Suite Pro JAR
# ------------------------------------------------------------------------------
Write-Host "`n[5/8] Managing Burp Suite Pro JAR releases..." -ForegroundColor Cyan

# Remove old versions to save disk space
Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $JarName } |
    ForEach-Object {
        Write-Host "      Removing old version: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }

$TargetJar = Join-Path $InstallDir $JarName
if ($ForceDownload -or (-not (Test-Path $TargetJar)) -or ((Get-Item $TargetJar).Length -lt 104857600)) {
    Write-Host "      Downloading $JarName (~700MB, fast silent mode)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetJar
    Write-Host "      [✓] Download completed." -ForegroundColor Green
} else {
    Write-Host "      [✓] $JarName is already up-to-date in $InstallDir." -ForegroundColor Green
}

# Checksums calculation
Write-Host "      Calculating cryptographic checksums..." -ForegroundColor DarkGray
$sha256 = (Get-FileHash -Path $TargetJar -Algorithm SHA256).Hash
$md5 = (Get-FileHash -Path $TargetJar -Algorithm MD5).Hash
Write-Host "      SHA256: $sha256" -ForegroundColor DarkCyan
Write-Host "      MD5:    $md5" -ForegroundColor DarkCyan

# ------------------------------------------------------------------------------
# 6. Copy Local Assets (.config.ini & burp_suite_pro.ico)
# ------------------------------------------------------------------------------
Write-Host "`n[6/8] Deploying local assets & icons..." -ForegroundColor Cyan

$LocalConfig = Join-Path $ScriptDir ".config.ini"
if (Test-Path $LocalConfig) {
    Copy-Item -Path $LocalConfig -Destination $InstallDir -Force
    Write-Host "      [✓] Copied .config.ini to $InstallDir" -ForegroundColor Green
}

$LocalIcon = Join-Path $ScriptDir "burp_suite_pro.ico"
$TargetIcon = Join-Path $InstallDir "burp_suite_pro.ico"
if (Test-Path $LocalIcon) {
    Copy-Item -Path $LocalIcon -Destination $InstallDir -Force
    Write-Host "      [✓] Copied official burp_suite_pro.ico to $InstallDir" -ForegroundColor Green
} else {
    Write-Warning "Local burp_suite_pro.ico not found at $LocalIcon."
}

# ------------------------------------------------------------------------------
# 7. Create Launchers & Desktop/Start Menu Shortcuts
# ------------------------------------------------------------------------------
Write-Host "`n[7/8] Creating launchers and Windows shortcuts..." -ForegroundColor Cyan

# 7A. Burp.bat (Direct / CLI launcher with Java 21 module flags)
$BatPath = Join-Path $InstallDir "Burp.bat"
$BatContent = @"
@echo off
setlocal
cd /d "%~dp0"
start "" javaw -XX:+UseG1GC --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:"%~dp0loader.jar" -noverify -jar "%~dp0$JarName" %*
endlocal
"@
Set-Content -Path $BatPath -Value $BatContent -Encoding ASCII
Write-Host "      [✓] Generated $BatPath" -ForegroundColor Green

# 7B. Burp-Suite-Pro.vbs (Completely silent execution without console window)
$VbsPath = Join-Path $InstallDir "Burp-Suite-Pro.vbs"
$VbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "cmd /c """ & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\Burp.bat""", 0, False
Set WshShell = Nothing
"@
Set-Content -Path $VbsPath -Value $VbsContent -Encoding ASCII
Write-Host "      [✓] Generated $VbsPath" -ForegroundColor Green

# 7C. Create burpsuitepro.cmd CLI wrapper for PATH
$CliCmdPath = Join-Path $InstallDir "burpsuitepro.cmd"
$CliCmdContent = "@call `"%~dp0Burp.bat`" %*"
Set-Content -Path $CliCmdPath -Value $CliCmdContent -Encoding ASCII

# Add to User PATH if not already present
$currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($currentUserPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$InstallDir", "User")
    Write-Host "      [✓] Added $InstallDir to User PATH (run 'burpsuitepro' in any terminal)." -ForegroundColor Green
}

# 7D. Windows Desktop and Start Menu Shortcuts with official .ico
Write-Host "      Configuring Windows Start Menu Search & Desktop shortcuts..." -ForegroundColor DarkCyan
try {
    $WshShell = New-Object -ComObject WScript.Shell

    # Prefer direct javaw.exe execution so Windows Search classifies it as a primary App
    $javawCmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
    $useDirectJavaw = $false
    $shortcutTarget = "wscript.exe"
    $shortcutArgs = "`"$VbsPath`""

    if ($javawCmd -and (Test-Path $javawCmd.Source)) {
        $shortcutTarget = $javawCmd.Source
        $shortcutArgs = "-XX:+UseG1GC --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:`"$TargetLoader`" -noverify -jar `"$TargetJar`""
        $useDirectJavaw = $true
    }

    # Helper function to create/update shortcut
    function Create-AppShortcut {
        param (
            [string]$Directory,
            [string]$Name,
            [string]$Description
        )
        if (-not (Test-Path $Directory)) { return }
        $lnkPath = Join-Path $Directory "$Name.lnk"
        $sc = $WshShell.CreateShortcut($lnkPath)
        $sc.TargetPath = $shortcutTarget
        $sc.Arguments = $shortcutArgs
        $sc.WorkingDirectory = $InstallDir
        $sc.Description = $Description
        $sc.WindowStyle = 1
        if (Test-Path $TargetIcon) {
            $sc.IconLocation = "$TargetIcon,0"
        }
        $sc.Save()
        Write-Host "      [✓] Shortcut ready: $lnkPath" -ForegroundColor Green
    }

    # 1. Desktop Shortcut
    $DesktopFolder = [Environment]::GetFolderPath("Desktop")
    Create-AppShortcut -Directory $DesktopFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"

    # 2. Start Menu Programs (Enables Windows Key -> Search "Burp Suite Pro" / "Burp Suite Professional")
    $ProgramsFolder = [Environment]::GetFolderPath("Programs")
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"

    # Also register in All Users Start Menu if running as Administrator
    $CommonPrograms = [Environment]::GetFolderPath("CommonPrograms")
    if (Test-Path $CommonPrograms) {
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"
    }

    # Refresh Windows Shell & Icon Cache so Search indexes it immediately
    try {
        $shellNotifyCode = @'
        [System.Runtime.InteropServices.DllImport("shell32.dll")]
        public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
        $shellNotify = Add-Type -MemberDefinition $shellNotifyCode -Name "ShellNotify" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
        if ($shellNotify) {
            [Win32.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero) # SHCNE_ASSOCCHANGED
        }
    } catch {}

} catch {
    Write-Warning "Could not register shell shortcuts: $($_.Exception.Message)"
}

# ------------------------------------------------------------------------------
# 8. Start Key Loader & Burp Suite Professional
# ------------------------------------------------------------------------------
Write-Host "`n[8/8] Starting Burp Suite Professional suite..." -ForegroundColor Cyan

if (-not $SkipLaunch) {
    if (Test-Path $TargetLoader) {
        Write-Host "      Launching Key Loader in background..." -ForegroundColor Yellow
        Start-Process -FilePath "java.exe" -ArgumentList "-jar `"$TargetLoader`""
    }

    Write-Host "      Launching Burp Suite Professional..." -ForegroundColor Yellow
    Start-Process -FilePath "wscript.exe" -ArgumentList "`"$VbsPath`""
} else {
    Write-Host "      Skipping launch (-SkipLaunch specified)." -ForegroundColor DarkGray
}

Write-Host @"

===============================================================
  Burp Suite Professional Installation Completed Successfully!
===============================================================
Directory: $InstallDir
Shortcut:  Desktop & Start Menu ("Burp Suite Professional")
CLI Command: burpsuitepro
===============================================================
"@ -ForegroundColor Green
