<#
.SYNOPSIS
    Automated Burp Suite Professional Installer for Windows.
.DESCRIPTION
    PowerShell installer for Burp Suite Professional:
    - Detects Java 21+ (PATH, Registry, Program Files).
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
$ProgressPreference = 'Continue'

# Enable modern TLS 1.2 and TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "       Burp Suite Professional Installer for Windows           " -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# High-Speed Throttled Stream Downloader (Shows Visual Progress & Speed without Slowdown)
# ------------------------------------------------------------------------------
function Download-FileWithProgress {
    param (
        [string]$Url,
        [string]$OutputFile,
        [string]$Description = "Downloading"
    )

    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        $req.Timeout = 180000
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        $totalBytes = $resp.ContentLength
        $stream = $resp.GetResponseStream()

        $parentDir = Split-Path -Parent $OutputFile
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        $fileStream = [System.IO.File]::Create($OutputFile)
        $buffer = New-Object byte[] 65536
        $downloaded = 0
        $lastUpdate = [DateTime]::MinValue
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $downloaded += $read
            $now = [DateTime]::UtcNow

            # Throttle UI progress updates to every 250ms to maximize throughput
            if (($now - $lastUpdate).TotalMilliseconds -ge 250 -or $downloaded -eq $totalBytes) {
                $lastUpdate = $now
                if ($totalBytes -gt 0) {
                    $pct = [int][math]::Min(100, [math]::Max(0, ($downloaded * 100 / $totalBytes)))
                    $mbDown = [math]::Round($downloaded / 1MB, 1)
                    $mbTotal = [math]::Round($totalBytes / 1MB, 1)
                    $sec = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
                    $speed = [math]::Round(($downloaded / 1MB) / $sec, 1)
                    Write-Progress -Activity $Description -Status "$mbDown MB / $mbTotal MB ($pct%) at $speed MB/s" -PercentComplete $pct
                } else {
                    $mbDown = [math]::Round($downloaded / 1MB, 1)
                    Write-Progress -Activity $Description -Status "$mbDown MB downloaded"
                }
            }
        }
        $fileStream.Dispose()
        $stream.Dispose()
        $resp.Dispose()
        Write-Progress -Activity $Description -Completed
    } catch {
        Write-Warning "Stream download encountered an issue: $($_.Exception.Message). Falling back to WebClient..."
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($Url, $OutputFile)
        Write-Progress -Activity $Description -Completed
    }
}

# ------------------------------------------------------------------------------
# 1. Directory Initialization
# ------------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = (Get-Location).Path
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallPath)
Write-Host "`n(1/8) Setting up installation target: $InstallDir" -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "      Created directory: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "      Target directory exists." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 2. Comprehensive Java 21+ Detection & Auto-Installation
# ------------------------------------------------------------------------------
Write-Host "`n(2/8) Checking Java runtime environment (Requires Java 21+)..." -ForegroundColor Cyan

function Refresh-EnvironmentPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-JavaVersion {
    param ([string]$ExecutablePath)
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $null }
    if (-not (Test-Path $ExecutablePath)) { return $null }
    try {
        # Use cmd.exe /c to guarantee clean text capture from stderr without ErrorRecord exceptions
        $rawOut = (cmd.exe /c "`"$ExecutablePath`" -version 2>&1") | Out-String
        if ([string]::IsNullOrWhiteSpace($rawOut)) { return $null }

        $major = 0
        if ($rawOut -match '(?i)(?:version\s+"?|openjdk\s+|java\s+)(\d+)') {
            $major = [int]$matches[1]
            if ($major -eq 1 -and $rawOut -match '1\.(\d+)') {
                $major = [int]$matches[1]
            }
        }

        if ($major -gt 0) {
            return [PSCustomObject]@{
                Path  = $ExecutablePath
                Major = $major
                Raw   = $rawOut.Trim()
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
        Write-Host "      [OK] Compatible Java found in PATH: Java $($validJava.Major) ($($validJava.Path))" -ForegroundColor Green
    } elseif ($testResult) {
        Write-Host "      [*] Java in PATH is version $($testResult.Major) (Burp Suite Pro requires Java 21+)." -ForegroundColor Yellow
    }
}

# 2B. Check JAVA_HOME environment variables (Session, Machine, User)
if (-not $validJava) {
    $javaHomeCandidates = @(
        $env:JAVA_HOME,
        [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine"),
        [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($jh in $javaHomeCandidates) {
        $exeCandidate = Join-Path $jh "bin\java.exe"
        $testResult = Test-JavaVersion -ExecutablePath $exeCandidate
        if ($testResult -and $testResult.Major -ge 21) {
            $validJava = $testResult
            Write-Host "      [OK] Found compatible Java in JAVA_HOME: Java $($validJava.Major) ($($validJava.Path))" -ForegroundColor Green
            break
        }
    }
}

# 2C. Deep Scan of Windows Registry and Program Files directories
if (-not $validJava) {
    Write-Host "      Scanning registry and disk for existing JDK 21+ installations..." -ForegroundColor DarkCyan

    $candidateExeList = [System.Collections.Generic.List[string]]::new()

    # Registry lookups
    $regPaths = @(
        "HKLM:\SOFTWARE\JavaSoft\JDK",
        "HKLM:\SOFTWARE\JavaSoft\Java Development Kit",
        "HKLM:\SOFTWARE\Microsoft\JDK",
        "HKLM:\SOFTWARE\Eclipse Adoptium\JDK"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            Get-ChildItem -Path $rp -ErrorAction SilentlyContinue | ForEach-Object {
                $subKey = $_.PSPath
                $jHome = (Get-ItemProperty -Path $subKey -Name "JavaHome" -ErrorAction SilentlyContinue).JavaHome
                if (-not $jHome) {
                    $jHome = (Get-ItemProperty -Path $subKey -Name "Path" -ErrorAction SilentlyContinue).Path
                }
                if ($jHome) {
                    $c = Join-Path $jHome "bin\java.exe"
                    if (Test-Path $c) { $candidateExeList.Add($c) }
                }
            }
        }
    }

    # Safe filesystem search (does NOT throw if directory is missing)
    $searchRoots = @(
        "$env:ProgramFiles\Java",
        "$env:ProgramFiles\Microsoft",
        "$env:ProgramFiles\Eclipse Adoptium",
        "$env:ProgramFiles\Amazon Corretto",
        "$env:ProgramFiles\BellSoft",
        "$env:ProgramFiles\Zulu",
        "$env:ProgramFiles\Semeru",
        "${env:ProgramFiles(x86)}\Java",
        "$env:LOCALAPPDATA\Programs\Eclipse Adoptium"
    )

    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Filter "java.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                ForEach-Object { $candidateExeList.Add($_.FullName) }
        }
    }

    # Test all found java.exe binaries
    foreach ($exe in ($candidateExeList | Select-Object -Unique)) {
        $testResult = Test-JavaVersion -ExecutablePath $exe
        if ($testResult -and $testResult.Major -ge 21) {
            $validJava = $testResult
            $javaBin = Split-Path -Parent $validJava.Path
            $env:Path = "$javaBin;" + $env:Path
            $env:JAVA_HOME = Split-Path -Parent $javaBin
            Write-Host "      [OK] Detected existing Java $($validJava.Major) at: $($validJava.Path)" -ForegroundColor Green
            break
        }
    }
}

# 2D. ONLY if Java 21+ was NOT found anywhere, download and install OpenJDK 21
if (-not $validJava) {
    Write-Host "      [*] Java 21+ was not detected on this system. Starting automated installer..." -ForegroundColor Yellow
    $javaInstalledSuccess = $false

    # Method 1: Fast direct MSI download from Microsoft / Adoptium CDN
    Write-Host "      Downloading OpenJDK 21 MSI directly (high-speed CDN)..." -ForegroundColor Cyan
    $msiSources = @(
        "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi",
        "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/OpenJDK21U-jdk_x64_windows_hotspot_21.0.6_7.msi"
    )
    $msiFile = Join-Path $env:TEMP "openjdk21_installer.msi"

    foreach ($msiUrl in $msiSources) {
        try {
            Write-Host "      Connecting to $msiUrl ..." -ForegroundColor DarkGray
            Download-FileWithProgress -Url $msiUrl -OutputFile $msiFile -Description "Downloading OpenJDK 21 MSI (~170MB)"
            if ((Test-Path $msiFile) -and ((Get-Item $msiFile).Length -gt 50000000)) {
                Write-Host "      Installing OpenJDK 21 silently via msiexec (takes ~10 seconds)..." -ForegroundColor Yellow
                $installArgs = "/i `"$msiFile`" /quiet /qn /norestart"
                $msiProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

                if (Test-Path $msiFile) { Remove-Item -Path $msiFile -Force -ErrorAction SilentlyContinue }
                $javaInstalledSuccess = $true
                Write-Host "      [OK] OpenJDK 21 installation completed." -ForegroundColor Green
                break
            }
        } catch {
            Write-Warning "MSI download from $msiUrl failed: $($_.Exception.Message)"
        }
    }

    # Method 2: Fallback to winget if direct MSI failed
    if (-not $javaInstalledSuccess) {
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            Write-Host "      Attempting winget installation as fallback..." -ForegroundColor Cyan
            $wingetPackages = @("Microsoft.OpenJDK.21", "EclipseAdoptium.Temurin.21.JDK", "Oracle.JDK.21")

            foreach ($pkg in $wingetPackages) {
                Write-Host "      Installing $pkg via winget..." -ForegroundColor Yellow
                try {
                    $process = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $pkg -e --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
                    if ($process.ExitCode -eq 0) {
                        Write-Host "      [OK] Successfully installed $pkg via winget!" -ForegroundColor Green
                        $javaInstalledSuccess = $true
                        break
                    }
                } catch {
                    Write-Host "      Winget install of $pkg failed, trying next..." -ForegroundColor DarkGray
                }
            }
        }
    }

    # Refresh PATH and verify after installation
    Refresh-EnvironmentPath
    $recheck = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($recheck) {
        $validJava = Test-JavaVersion -ExecutablePath $recheck.Source
    }

    if (-not $validJava) {
        $searchRoots = @("$env:ProgramFiles\Microsoft", "$env:ProgramFiles\Eclipse Adoptium", "$env:ProgramFiles\Java")
        foreach ($root in $searchRoots) {
            if (Test-Path $root) {
                $foundExe = Get-ChildItem -Path $root -Filter "java.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundExe) {
                    $validJava = Test-JavaVersion -ExecutablePath $foundExe.FullName
                    if ($validJava -and $validJava.Major -ge 21) {
                        $javaBin = Split-Path -Parent $validJava.Path
                        $env:Path = "$javaBin;" + $env:Path
                        $env:JAVA_HOME = Split-Path -Parent $javaBin
                        break
                    }
                }
            }
        }
    }

    if (-not $validJava) {
        Write-Error "ERROR: Could not verify Java 21+ installation. Please manually install JDK 21 from https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi and rerun."
        exit 1
    } else {
        Write-Host "      [OK] Java 21+ verified successfully: $($validJava.Raw)" -ForegroundColor Green
    }
} else {
    Write-Host "      [OK] Java 21+ already satisfied. Skipping download/installation." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 3. Dynamic Release Version Fetch from PortSwigger
# ------------------------------------------------------------------------------
Write-Host "`n(3/8) Fetching latest Burp Suite Professional version from PortSwigger..." -ForegroundColor Cyan
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
Write-Host "`n(4/8) Downloading key loader..." -ForegroundColor Cyan
$TargetLoader = Join-Path $InstallDir "loader.jar"
$loaderSources = @(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar",
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
)

$loaderDownloaded = $false
foreach ($url in $loaderSources) {
    try {
        Write-Host "      Fetching from $url ..." -ForegroundColor DarkGray
        Download-FileWithProgress -Url $url -OutputFile $TargetLoader -Description "Downloading Key Loader"
        if ((Test-Path $TargetLoader) -and ((Get-Item $TargetLoader).Length -gt 10240)) {
            $lBytes = (Get-Item $TargetLoader).Length
            Write-Host "      [OK] Loader verified ($lBytes bytes)." -ForegroundColor Green
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
Write-Host "`n(5/8) Managing Burp Suite Pro JAR releases..." -ForegroundColor Cyan

Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $JarName } |
    ForEach-Object {
        $oldFile = $_.Name
        Write-Host "      Removing old version: $oldFile" -ForegroundColor DarkGray
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }

$TargetJar = Join-Path $InstallDir $JarName
if ($ForceDownload -or (-not (Test-Path $TargetJar)) -or ((Get-Item $TargetJar).Length -lt 104857600)) {
    Write-Host "      Downloading $JarName (~700MB)..." -ForegroundColor Yellow
    Download-FileWithProgress -Url $DownloadUrl -OutputFile $TargetJar -Description "Downloading Burp Suite Professional $BURP_VERSION"
    Write-Host "      [OK] Download completed." -ForegroundColor Green
} else {
    Write-Host "      [OK] $JarName is already up-to-date in $InstallDir." -ForegroundColor Green
}

Write-Host "      Calculating cryptographic checksums..." -ForegroundColor DarkGray
$sha256 = (Get-FileHash -Path $TargetJar -Algorithm SHA256).Hash
$md5 = (Get-FileHash -Path $TargetJar -Algorithm MD5).Hash
Write-Host "      SHA256: $sha256" -ForegroundColor DarkCyan
Write-Host "      MD5:    $md5" -ForegroundColor DarkCyan

# ------------------------------------------------------------------------------
# 6. Copy Local Assets (.config.ini & burp_suite_pro.ico)
# ------------------------------------------------------------------------------
Write-Host "`n(6/8) Deploying local assets & icons..." -ForegroundColor Cyan

$LocalConfig = Join-Path $ScriptDir ".config.ini"
if (Test-Path $LocalConfig) {
    Copy-Item -Path $LocalConfig -Destination $InstallDir -Force
    Write-Host "      [OK] Copied .config.ini to $InstallDir" -ForegroundColor Green
}

$LocalIcon = Join-Path $ScriptDir "burp_suite_pro.ico"
$TargetIcon = Join-Path $InstallDir "burp_suite_pro.ico"
if (Test-Path $LocalIcon) {
    Copy-Item -Path $LocalIcon -Destination $InstallDir -Force
    Write-Host "      [OK] Copied official burp_suite_pro.ico to $InstallDir" -ForegroundColor Green
} else {
    Write-Warning "Local burp_suite_pro.ico not found at $LocalIcon."
}

# ------------------------------------------------------------------------------
# 7. Create Launchers & Desktop/Start Menu Shortcuts
# ------------------------------------------------------------------------------
Write-Host "`n(7/8) Creating launchers and Windows shortcuts..." -ForegroundColor Cyan

# 7A. Burp.bat (Direct / CLI launcher with Java 21 module flags)
$BatPath = Join-Path $InstallDir "Burp.bat"
$BatContent = "@echo off`r`nsetlocal`r`ncd /d `"%~dp0`"`r`nstart `"`" javaw -XX:+UseG1GC --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:`"%~dp0loader.jar`" -noverify -jar `"%~dp0$JarName`" %*`r`nendlocal`r`n"
[System.IO.File]::WriteAllText($BatPath, $BatContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $BatPath" -ForegroundColor Green

# 7B. Burp-Suite-Pro.vbs (Completely silent execution without console window)
$VbsPath = Join-Path $InstallDir "Burp-Suite-Pro.vbs"
$VbsContent = "Set WshShell = CreateObject(`"WScript.Shell`")`r`nWshShell.Run `"cmd /c `"`"`" & CreateObject(`"Scripting.FileSystemObject`").GetParentFolderName(WScript.ScriptFullName) & `"\Burp.bat`"`"`", 0, False`r`nSet WshShell = Nothing`r`n"
[System.IO.File]::WriteAllText($VbsPath, $VbsContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $VbsPath" -ForegroundColor Green

# 7C. Create burpsuitepro.cmd CLI wrapper for PATH
$CliCmdPath = Join-Path $InstallDir "burpsuitepro.cmd"
$CliCmdContent = "@call `"%~dp0Burp.bat`" %*`r`n"
[System.IO.File]::WriteAllText($CliCmdPath, $CliCmdContent, [System.Text.Encoding]::ASCII)

$currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($currentUserPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$InstallDir", "User")
    Write-Host "      [OK] Added $InstallDir to User PATH (run 'burpsuitepro' in any terminal)." -ForegroundColor Green
}

# 7D. Windows Desktop and Start Menu Shortcuts with official .ico
Write-Host "      Configuring Windows Start Menu Search & Desktop shortcuts..." -ForegroundColor DarkCyan
try {
    $WshShell = New-Object -ComObject WScript.Shell

    $javawCmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
    $shortcutTarget = "wscript.exe"
    $shortcutArgs = "`"$VbsPath`""

    if ($javawCmd -and (Test-Path $javawCmd.Source)) {
        $shortcutTarget = $javawCmd.Source
        $shortcutArgs = "-XX:+UseG1GC --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:`"$TargetLoader`" -noverify -jar `"$TargetJar`""
    }

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
        Write-Host "      [OK] Shortcut ready: $lnkPath" -ForegroundColor Green
    }

    # Desktop Shortcut
    $DesktopFolder = [Environment]::GetFolderPath("Desktop")
    Create-AppShortcut -Directory $DesktopFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"

    # Start Menu Programs (Enables Windows Key -> Search "Burp Suite Pro" / "Burp Suite Professional")
    $ProgramsFolder = [Environment]::GetFolderPath("Programs")
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"

    $CommonPrograms = [Environment]::GetFolderPath("CommonPrograms")
    if (Test-Path $CommonPrograms) {
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"
    }

    # Refresh Windows Shell & Icon Cache so Search indexes it immediately
    try {
        $shellNotifyCode = '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);'
        $shellNotify = Add-Type -MemberDefinition $shellNotifyCode -Name "ShellNotify" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
        if ($shellNotify) {
            [Win32.ShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        }
    } catch {}

} catch {
    Write-Warning "Could not register shell shortcuts: $($_.Exception.Message)"
}

# ------------------------------------------------------------------------------
# 8. Start Key Loader & Burp Suite Professional
# ------------------------------------------------------------------------------
Write-Host "`n(8/8) Starting Burp Suite Professional suite..." -ForegroundColor Cyan

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

Write-Host "`n===============================================================" -ForegroundColor Green
Write-Host "  Burp Suite Professional Installation Completed Successfully! " -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
Write-Host "Directory:   $InstallDir"
Write-Host "Shortcut:    Desktop & Start Menu ('Burp Suite Professional')"
Write-Host "CLI Command: burpsuitepro"
Write-Host "===============================================================" -ForegroundColor Green
