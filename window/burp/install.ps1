<#
.SYNOPSIS
    Automated Burp Suite Professional Installer for Windows.
.DESCRIPTION
    PowerShell installer for Burp Suite Professional:
    - Detects Java 21+ (PATH, Registry, Program Files).
    - Auto-installs Java 21 via winget (auto-installs winget via window/system/winget_install.ps1 if missing, with silent MSI fallback).
    - Resolves the Burp version in this order: -Version, $env:BURP_VERSION,
      -Channel stable|latest, then an interactive channel prompt (tested stable
      v2026.10.1 vs. newest PortSwigger release, marked UNTESTED). When no
      console is attached it defaults to tested stable without prompting, so
      automation never blocks.
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
    [string]$Version,
    [switch]$SkipLaunch,
    [switch]$ForceDownload,
    [switch]$Update,
    [string]$Channel
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Automatically set execution policy to Bypass for current process
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
} catch {}

# Enable modern TLS 1.2 and optionally TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 12288
} catch {}

Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "       Burp Suite Professional Installer for Windows           " -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# High-Speed Downloader (aria2c multi-stream / native Windows curl.exe auto-resume)
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

    # Method 1: Check for aria2c (16 parallel chunk streams - fastest accelerator)
    $aria2Cmd = Get-Command aria2c.exe -ErrorAction SilentlyContinue
    if ($aria2Cmd -and (Test-Path $aria2Cmd.Source)) {
        Write-Host "      Using aria2c accelerator (16 parallel streams)..." -ForegroundColor Magenta
        try {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $outDir = Split-Path -Parent $OutputFile
            $outFile = Split-Path -Leaf $OutputFile
            $ariaArgs = @(
                "-x", "16",
                "-s", "16",
                "-j", "16",
                "-k", "1M",
                "--file-allocation=none",
                "--summary-interval=1",
                "--continue=true",
                "-d", $outDir,
                "-o", $outFile,
                $Url
            )
            $p = Start-Process -FilePath $aria2Cmd.Source -ArgumentList $ariaArgs -NoNewWindow -Wait -PassThru
            $ErrorActionPreference = $prevEap

            if ($p.ExitCode -eq 0 -and (Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 0)) {
                return
            }
        } catch {}
    }

    # Method 2: Use native Windows curl.exe (High-speed C binary, HTTP/2, auto-resume)
    $curlExe = $null
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd -and (Test-Path $curlCmd.Source)) {
        $curlExe = $curlCmd.Source
    } elseif (Test-Path "$env:SystemRoot\System32\curl.exe") {
        $curlExe = "$env:SystemRoot\System32\curl.exe"
    }

    if ($curlExe) {
        Write-Host "      Using native curl.exe for high-speed download (with auto-resume)..." -ForegroundColor Cyan
        try {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'

            $curlArgs = @("-fL", "--retry", "3", "--retry-delay", "1", "-C", "-", "--progress-bar", "-o", $OutputFile, $Url)
            $p = Start-Process -FilePath $curlExe -ArgumentList $curlArgs -NoNewWindow -Wait -PassThru

            $ErrorActionPreference = $prevEap

            if ($p.ExitCode -eq 0 -and (Test-Path $OutputFile) -and ((Get-Item $OutputFile).Length -gt 0)) {
                return
            } else {
                Write-Warning "curl.exe returned exit code $($p.ExitCode). Falling back to .NET stream downloader..."
            }
        } catch {
            Write-Warning "curl.exe encountered an issue: $($_.Exception.Message). Falling back to stream downloader..."
        }
    }

    # Method 3: High-Speed .NET Stream Downloader (1MB buffer)
    $resp = $null
    $stream = $null
    $fileStream = $null
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        $req.Timeout = 180000
        $req.AllowAutoRedirect = $true
        $resp = $req.GetResponse()
        $totalBytes = $resp.ContentLength
        $stream = $resp.GetResponseStream()

        $fileStream = [System.IO.File]::Create($OutputFile)
        try {
            $buffer = New-Object byte[] 1048576
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
        } finally {
            if ($fileStream) {
                $fileStream.Dispose()
                $fileStream = $null
            }
        }
        if ($stream) { $stream.Dispose(); $stream = $null }
        if ($resp) { $resp.Dispose(); $resp = $null }
        Write-Progress -Activity $Description -Completed
    } catch {
        if ($fileStream) { $fileStream.Dispose(); $fileStream = $null }
        if ($stream) { $stream.Dispose(); $stream = $null }
        if ($resp) { $resp.Dispose(); $resp = $null }
        Write-Warning "Stream download encountered an issue: $($_.Exception.Message). Falling back to WebClient..."
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($Url, $OutputFile)
        Write-Progress -Activity $Description -Completed
    }
}

# ------------------------------------------------------------------------------
# 1. Directory Initialization & Process Check
# ------------------------------------------------------------------------------
$ScriptDir = if (![string]::IsNullOrEmpty($PSScriptRoot)) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { $PWD.Path }

$InstallDir = [System.IO.Path]::GetFullPath($InstallPath)
Write-Host "`n(1/8) Setting up installation target: $InstallDir" -ForegroundColor Cyan

# Check for running Burp Suite instances to prevent file locking
Write-Host "      Checking for active Burp Suite processes..." -ForegroundColor DarkGray
try {
    $runningBurp = @()
    try {
        $runningBurp = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(java|javaw|wscript)\.exe$') -and (
                $_.CommandLine -match 'burpsuite' -or 
                $_.CommandLine -match 'loader\.jar' -or 
                $_.CommandLine -match 'Burp-Suite-Pro\.vbs' -or
                $_.CommandLine -match 'Burp\.bat' -or
                ($InstallDir -and $_.CommandLine -like "*$InstallDir*")
            )
        }
    } catch {
        $runningBurp = Get-WmiObject Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(java|javaw|wscript)\.exe$') -and (
                $_.CommandLine -match 'burpsuite' -or 
                $_.CommandLine -match 'loader\.jar' -or 
                $_.CommandLine -match 'Burp-Suite-Pro\.vbs' -or
                $_.CommandLine -match 'Burp\.bat' -or
                ($InstallDir -and $_.CommandLine -like "*$InstallDir*")
            )
        }
    }

    if ($runningBurp) {
        Write-Host "      [*] Detected active Burp Suite processes. Stopping to prevent file locks..." -ForegroundColor Yellow
        foreach ($p in $runningBurp) {
            Write-Host "      Terminating process: ID $($p.ProcessId) ($($p.Name))" -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 800
        Write-Host "      [OK] Running processes cleanly terminated." -ForegroundColor Green
    } else {
        Write-Host "      [OK] No conflicting processes running." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not verify running processes: $($_.Exception.Message). Please ensure Burp Suite is closed."
}

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

    # Helper function to locate winget executable
    function Find-WinGetExecutable {
        $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }

        $defaultAlias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
        if (Test-Path $defaultAlias) { return $defaultAlias }

        $programFilesWinget = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps" -Filter "winget.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($programFilesWinget -and (Test-Path $programFilesWinget.FullName)) { return $programFilesWinget.FullName }

        return $null
    }

    $wingetExe = Find-WinGetExecutable

    # If winget is NOT installed, install it automatically via window/system/winget_install.ps1
    if (-not $wingetExe) {
        Write-Host "      [!] WinGet is not installed on this system. Installing WinGet first..." -ForegroundColor Yellow
        $wingetInstallerPath = Join-Path (Split-Path -Parent $ScriptDir) "system\winget_install.ps1"
        $wingetTempScript = $null

        if (-not (Test-Path $wingetInstallerPath)) {
            Write-Host "      Downloading winget_install.ps1 from repository..." -ForegroundColor Cyan
            $wingetTempScript = Join-Path $env:TEMP "winget_install.ps1"
            $wingetUrl = "https://raw.githubusercontent.com/aadish0day/post_install/main/window/system/winget_install.ps1"
            try {
                Download-FileWithProgress -Url $wingetUrl -OutputFile $wingetTempScript -Description "Downloading WinGet Installer"
                if (Test-Path $wingetTempScript) {
                    $wingetInstallerPath = $wingetTempScript
                }
            } catch {
                Write-Host "      Could not download winget_install.ps1 ($($_.Exception.Message))." -ForegroundColor DarkGray
            }
        }

        if ($wingetInstallerPath -and (Test-Path $wingetInstallerPath)) {
            try {
                Write-Host "      Executing $wingetInstallerPath -Action Install..." -ForegroundColor Cyan
                & $wingetInstallerPath -Action Install

                # Refresh environment PATH and aliases
                Refresh-EnvironmentPath
                Start-Sleep -Seconds 2

                $wingetExe = Find-WinGetExecutable
                if ($wingetExe) {
                    Write-Host "      [OK] WinGet successfully installed and detected: $wingetExe" -ForegroundColor Green
                }
            } catch {
                Write-Host "      WinGet installation encountered an error: $($_.Exception.Message)" -ForegroundColor DarkGray
            } finally {
                if ($wingetTempScript -and (Test-Path $wingetTempScript)) {
                    Remove-Item -Path $wingetTempScript -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Method 1A: High-speed installation via Chocolatey (if installed)
    $chocoCmd = Get-Command choco.exe -ErrorAction SilentlyContinue
    $chocoExe = if ($chocoCmd -and (Test-Path $chocoCmd.Source)) { $chocoCmd.Source }
                elseif (Test-Path "$env:SystemDrive\ProgramData\chocolatey\bin\choco.exe") { "$env:SystemDrive\ProgramData\chocolatey\bin\choco.exe" }
                else { $null }

    if ($chocoExe) {
        Write-Host "      Detected Chocolatey! Using choco to install Java 21..." -ForegroundColor Cyan
        $chocoPackages = @("openjdk21", "microsoft-openjdk21", "temurin21")
        foreach ($cpkg in $chocoPackages) {
            Write-Host "      Installing $cpkg via choco..." -ForegroundColor Yellow
            try {
                $cproc = Start-Process -FilePath $chocoExe -ArgumentList "install $cpkg -y --no-progress" -NoNewWindow -Wait -PassThru
                if ($cproc.ExitCode -eq 0 -or $cproc.ExitCode -eq 3010) {
                    Write-Host "      [OK] Successfully installed $cpkg via Chocolatey!" -ForegroundColor Green
                    $javaInstalledSuccess = $true
                    break
                } else {
                    Write-Host "      choco returned exit code $($cproc.ExitCode). Trying next package..." -ForegroundColor DarkGray
                }
            } catch {
                Write-Host "      choco install failed: $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
    }

    # Method 1B: Primary installation via winget (if choco was not used or failed)
    if ((-not $javaInstalledSuccess) -and $wingetExe) {
        Write-Host "      Using winget to install Java 21..." -ForegroundColor Cyan
        $wingetPackages = @("Microsoft.OpenJDK.21", "EclipseAdoptium.Temurin.21.JDK", "Oracle.JDK.21")

        foreach ($pkg in $wingetPackages) {
            Write-Host "      Installing $pkg via winget..." -ForegroundColor Yellow
            try {
                $process = Start-Process -FilePath $wingetExe -ArgumentList "install --id $pkg -e --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
                if ($process.ExitCode -eq 0) {
                    Write-Host "      [OK] Successfully installed $pkg via winget!" -ForegroundColor Green
                    $javaInstalledSuccess = $true
                    break
                } else {
                    Write-Host "      winget returned exit code $($process.ExitCode). Trying next package..." -ForegroundColor DarkGray
                }
            } catch {
                Write-Host "      winget install failed: $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
    }

    # Method 2: Fallback to direct high-speed MSI download if winget failed or unavailable
    if (-not $javaInstalledSuccess) {
        Write-Host "      Falling back to direct OpenJDK 21 MSI download (high-speed CDN)..." -ForegroundColor Cyan
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
                    if ($msiProcess.ExitCode -eq 0) {
                        $javaInstalledSuccess = $true
                        Write-Host "      [OK] OpenJDK 21 installation completed." -ForegroundColor Green
                        break
                    } else {
                        Write-Warning "msiexec returned exit code $($msiProcess.ExitCode). Trying next source..."
                    }
                }
            } catch {
                Write-Warning "MSI download from $msiUrl failed: $($_.Exception.Message)"
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
# 3. Dynamic Release Version Fetch from PortSwigger (Stable/Latest Channel + -Version Override)
# ------------------------------------------------------------------------------
Write-Host "`n(3/8) Resolving Burp Suite Professional version..." -ForegroundColor Cyan
$BURP_VERSION = $null
$isCustomVersion = $false
$BURP_STABLE_VERSION = "2026.10.1"

# A prompt is only safe when a real console is attached; redirected input,
# service hosts and `irm | iex` runs must never block waiting for a keypress.
function Test-InteractiveConsole {
    try {
        if (-not [Environment]::UserInteractive) { return $false }
        if (-not $Host.UI -or -not $Host.UI.RawUI) { return $false }
        if ([Console]::IsInputRedirected) { return $false }
    } catch {
        return $false
    }
    return $true
}

# Interactive channel chooser. Returns "stable" or "latest"; any failure,
# empty input or EOF falls back to the tested stable channel.
function Read-BurpChannelChoice {
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host ""
        Write-Host "      Burp Suite Professional - version channel" -ForegroundColor Cyan
        Write-Host "        1) Tested stable  v$BURP_STABLE_VERSION  (recommended)" -ForegroundColor Green
        Write-Host "        2) Latest         newest PortSwigger release (UNTESTED)" -ForegroundColor Yellow
        $answer = $null
        try {
            $answer = Read-Host "      Select [1]"
        } catch {
            Write-Host "      Could not read input. Using tested stable v$BURP_STABLE_VERSION." -ForegroundColor DarkGray
            return "stable"
        }
        if ($null -eq $answer) { return "stable" }
        $choice = ([string]$answer).Trim().ToLower()
        if ($choice -eq "") { return "stable" }
        switch ($choice) {
            "1"      { return "stable" }
            "s"      { return "stable" }
            "stable" { return "stable" }
            "2"      { return "latest" }
            "l"      { return "latest" }
            "latest" { return "latest" }
        }
        Write-Host "      Invalid selection '$answer'. Enter 1 (stable) or 2 (latest)." -ForegroundColor Yellow
    }
    Write-Host "      No valid selection after $maxAttempts attempts. Using tested stable v$BURP_STABLE_VERSION." -ForegroundColor DarkGray
    return "stable"
}

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $BURP_VERSION = $Version.Trim()
    $isCustomVersion = $true
    Write-Host "      Using user-specified version: $BURP_VERSION" -ForegroundColor Green
} elseif (-not [string]::IsNullOrWhiteSpace($env:BURP_VERSION)) {
    $BURP_VERSION = $env:BURP_VERSION.Trim()
    $isCustomVersion = $true
    Write-Host "      Using environment variable BURP_VERSION: $BURP_VERSION" -ForegroundColor Green
} else {
    # No -Version and no BURP_VERSION: honor an explicit -Channel, otherwise
    # ask on interactive consoles and fall back to tested stable everywhere else.
    if ([string]::IsNullOrWhiteSpace($Channel)) {
        if (Test-InteractiveConsole) {
            $Channel = Read-BurpChannelChoice
        } else {
            $Channel = "stable"
            Write-Host "      No version or channel supplied. Defaulting to tested stable v$BURP_STABLE_VERSION." -ForegroundColor DarkGray
        }
    }
    $Channel = $Channel.Trim().ToLower()

    if ($Channel -eq "stable") {
        $BURP_VERSION = $BURP_STABLE_VERSION
        Write-Host "      Using stable (tested) version: $BURP_VERSION" -ForegroundColor Green
    } elseif ($Channel -eq "latest") {
        Write-Host ""
        Write-Host "      ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "      ║  ⚠  WARNING: Latest channel selected (UNTESTED)            ║" -ForegroundColor Yellow
        Write-Host "      ║  This fetches the newest release from PortSwigger.          ║" -ForegroundColor Yellow
        Write-Host "      ║  It may contain breaking changes or compatibility issues.   ║" -ForegroundColor Yellow
        Write-Host "      ║  Use 'stable' channel for a known-good version.            ║" -ForegroundColor Yellow
        Write-Host "      ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "      Checking PortSwigger release API for latest version..." -ForegroundColor DarkGray
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
            $BURP_VERSION = $BURP_STABLE_VERSION
            Write-Host "      API unavailable. Falling back to stable version: $BURP_VERSION" -ForegroundColor Yellow
        } else {
            Write-Host "      Latest official release detected: $BURP_VERSION" -ForegroundColor Green
        }
    } else {
        Write-Error "ERROR: Invalid channel '$Channel'. Use 'stable' or 'latest'."
        exit 1
    }
}

$JarName = "burpsuite_pro_v$BURP_VERSION.jar"
$DownloadUrl = "https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VERSION&type=Jar"
Write-Host "      Target Release:     $BURP_VERSION" -ForegroundColor Cyan
Write-Host "      Target File:        $JarName" -ForegroundColor DarkGray

# ------------------------------------------------------------------------------
# 4. Download Key Loader
# ------------------------------------------------------------------------------
Write-Host "`n(4/8) Checking key loader..." -ForegroundColor Cyan
$TargetLoader = Join-Path $InstallDir "loader.jar"
$loaderSources = @(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar",
    "https://github.com/xiv3r/Burpsuite-Professional/raw/refs/heads/main/loader.jar"
)

$loaderDownloaded = $false
if ((Test-Path $TargetLoader) -and ((Get-Item $TargetLoader).Length -gt 10240) -and -not $ForceDownload) {
    $lBytes = (Get-Item $TargetLoader).Length
    Write-Host "      [OK] Existing loader.jar verified ($lBytes bytes). Skipping download." -ForegroundColor Green
    $loaderDownloaded = $true
} else {
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
}

if (-not $loaderDownloaded) {
    Write-Error "ERROR: Failed to download a valid loader.jar. Check your internet connection."
    exit 1
}

# ------------------------------------------------------------------------------
# 5. Clean Old Versions & Download Burp Suite Pro JAR (Skip if Equal or Greater)
# ------------------------------------------------------------------------------
Write-Host "`n(5/8) Managing Burp Suite Pro JAR releases..." -ForegroundColor Cyan

function Parse-VersionSafe {
    param ([string]$VerString)
    try {
        $clean = ($VerString -replace '[^\d\.]', '').Trim('.')
        $parts = $clean.Split('.')
        $nums = @(0, 0, 0, 0)
        for ($i = 0; $i -lt 4; $i++) {
            if ($i -lt $parts.Length -and $parts[$i] -match '^\d+$') {
                $nums[$i] = [int]$parts[$i]
            }
        }
        return [System.Version]::new($nums[0], $nums[1], $nums[2], $nums[3])
    } catch {
        return [System.Version]::new(0, 0, 0, 0)
    }
}

function Compare-VersionStrings {
    param ([string]$v1, [string]$v2)
    $ver1 = Parse-VersionSafe -VerString $v1
    $ver2 = Parse-VersionSafe -VerString $v2
    return $ver1.CompareTo($ver2)
}

$skipDownload = $false
$TargetJar = Join-Path $InstallDir $JarName

# Check for existing Burp Pro JARs in the installation folder
$existingJars = Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue

if ($existingJars -and -not $ForceDownload) {
    if ($isCustomVersion) {
        # Exact version requested: check if that specific version is already present
        $exactJar = $existingJars | Where-Object { $_.Name -eq $JarName -and $_.Length -gt 10485760 } | Select-Object -First 1
        if ($exactJar) {
            Write-Host "      [OK] Requested version $BURP_VERSION is already downloaded. Skipping download." -ForegroundColor Green
            $skipDownload = $true
            $TargetJar = $exactJar.FullName
        }
    } else {
        # Auto-latest mode: Sort existing JARs by version to find highest installed release
        $sortedJars = $existingJars | Sort-Object {
            $v = $_.BaseName -replace '^burpsuite_pro_v', ''
            Parse-VersionSafe -VerString $v
        }
        $highestJar = $sortedJars | Select-Object -Last 1

        if ($highestJar -and $highestJar.Length -gt 10485760) {
            $existingVersion = $highestJar.BaseName -replace '^burpsuite_pro_v', ''
            $cmp = Compare-VersionStrings -v1 $existingVersion -v2 $BURP_VERSION

            if ($cmp -eq 0) {
                Write-Host "      [OK] Burp Suite Professional $BURP_VERSION is already downloaded and up-to-date. Skipping download." -ForegroundColor Green
                $skipDownload = $true
                $JarName = $highestJar.Name
                $TargetJar = $highestJar.FullName
            } elseif ($cmp -gt 0) {
                Write-Host "      [OK] Installed version ($existingVersion) is newer than PortSwigger release ($BURP_VERSION). Skipping download." -ForegroundColor Green
                $skipDownload = $true
                $JarName = $highestJar.Name
                $TargetJar = $highestJar.FullName
            } else {
                Write-Host "      [*] Found older version ($existingVersion). Upgrading to latest ($BURP_VERSION)..." -ForegroundColor Yellow
            }
        } else {
            Write-Host "      [*] Existing JAR is incomplete or corrupted. Re-downloading..." -ForegroundColor Yellow
        }
    }
}

if (-not $skipDownload) {
    $tempTarget = "$TargetJar.tmp"
    Write-Host "      Downloading $JarName (~700MB)..." -ForegroundColor Yellow
    Download-FileWithProgress -Url $DownloadUrl -OutputFile $tempTarget -Description "Downloading Burp Suite Professional $BURP_VERSION"

    # Validate downloaded JAR integrity (> 100MB) before overwriting target
    if ((Test-Path $tempTarget) -and ((Get-Item $tempTarget).Length -gt 100MB)) {
        Move-Item -Path $tempTarget -Destination $TargetJar -Force
        Write-Host "      [OK] Download completed and verified ($([math]::Round((Get-Item $TargetJar).Length / 1MB, 1)) MB)." -ForegroundColor Green
    } else {
        if (Test-Path $tempTarget) {
            Remove-Item -Path $tempTarget -Force -ErrorAction SilentlyContinue
        }
        Write-Error "ERROR: Downloaded JAR file is invalid or smaller than 100MB. Download may have failed or been corrupted."
        exit 1
    }

    # Clean up older versions only after download succeeds
    Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $JarName } |
        ForEach-Object {
            Write-Host "      Removing old version: $($_.Name)" -ForegroundColor DarkGray
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }

    Write-Host "      Calculating cryptographic checksums..." -ForegroundColor DarkGray
    $sha256 = (Get-FileHash -Path $TargetJar -Algorithm SHA256).Hash
    $md5 = (Get-FileHash -Path $TargetJar -Algorithm MD5).Hash
    Write-Host "      SHA256: $sha256" -ForegroundColor DarkCyan
    Write-Host "      MD5:    $md5" -ForegroundColor DarkCyan
}

# ------------------------------------------------------------------------------
# 6. Deploy Assets (.config.ini & burp_suite_pro.ico)
# ------------------------------------------------------------------------------
Write-Host "`n(6/8) Deploying assets & icons..." -ForegroundColor Cyan

$LocalConfig = Join-Path $ScriptDir ".config.ini"
$TargetConfig = Join-Path $InstallDir ".config.ini"
if (Test-Path $LocalConfig) {
    Copy-Item -Path $LocalConfig -Destination $InstallDir -Force
    Write-Host "      [OK] Copied .config.ini to $InstallDir" -ForegroundColor Green
} elseif (-not (Test-Path $TargetConfig)) {
    try {
        $cfgUrl = "https://raw.githubusercontent.com/aadish0day/post_install/main/window/burp/.config.ini"
        (New-Object System.Net.WebClient).DownloadFile($cfgUrl, $TargetConfig)
        Write-Host "      [OK] Downloaded default .config.ini to $InstallDir" -ForegroundColor Green
    } catch {
        Write-Warning "Could not fetch remote .config.ini"
    }
}

$LocalIcon = Join-Path $ScriptDir "burp_suite_pro.ico"
$TargetIcon = Join-Path $InstallDir "burp_suite_pro.ico"
if (Test-Path $LocalIcon) {
    Copy-Item -Path $LocalIcon -Destination $InstallDir -Force
    Write-Host "      [OK] Copied official burp_suite_pro.ico to $InstallDir" -ForegroundColor Green
} elseif (-not (Test-Path $TargetIcon)) {
    try {
        $icoUrl = "https://raw.githubusercontent.com/aadish0day/post_install/main/window/burp/burp_suite_pro.ico"
        (New-Object System.Net.WebClient).DownloadFile($icoUrl, $TargetIcon)
        Write-Host "      [OK] Downloaded official burp_suite_pro.ico to $InstallDir" -ForegroundColor Green
    } catch {
        Write-Warning "Local burp_suite_pro.ico not found at $LocalIcon."
    }
}

# ------------------------------------------------------------------------------
# 7. Create Launchers & Desktop/Start Menu Shortcuts
# ------------------------------------------------------------------------------
Write-Host "`n(7/8) Creating launchers and Windows shortcuts..." -ForegroundColor Cyan

# 7A. Burp.bat (Direct / CLI launcher with Java 21 module flags)
$BatPath = Join-Path $InstallDir "Burp.bat"
$BatContent = "@echo off`r`nsetlocal`r`ncd /d `"%~dp0`"`r`nif exist `"%JAVA_HOME%\bin\javaw.exe`" (`r`n    set `"JAVA_BIN=%JAVA_HOME%\bin\javaw.exe`"`r`n) else (`r`n    set `"JAVA_BIN=javaw`"`r`n)`r`nstart `"`" `"%JAVA_BIN%`" -XX:+UseG1GC --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:`"%~dp0loader.jar`" -noverify -jar `"%~dp0$JarName`" %*`r`nendlocal`r`n"
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

    $javawPath = $null
    if ($validJava -and (Test-Path $validJava.Path)) {
        $candidateJavaw = Join-Path (Split-Path -Parent $validJava.Path) "javaw.exe"
        if (Test-Path $candidateJavaw) {
            $javawPath = $candidateJavaw
        }
    }
    if (-not $javawPath) {
        $javawCmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
        if ($javawCmd -and (Test-Path $javawCmd.Source)) {
            $javawPath = $javawCmd.Source
        }
    }

    $shortcutTarget = "wscript.exe"
    $shortcutArgs = "`"$VbsPath`""

    if ($javawPath) {
        $shortcutTarget = $javawPath
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
        $javaLaunchExe = if ($validJava -and (Test-Path $validJava.Path)) { $validJava.Path } else { "java.exe" }
        Start-Process -FilePath $javaLaunchExe -ArgumentList "-jar `"$TargetLoader`""
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
