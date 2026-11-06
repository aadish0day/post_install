<#
.SYNOPSIS
    Automated Burp Suite Professional Installer for Windows.
.DESCRIPTION
    PowerShell installer for Burp Suite Professional:
    - Target folder preservation: never deletes or wipes the installation directory.
    - Detects Java 21+ (PATH, Registry, Program Files).
    - Auto-installs Java 21 via winget (auto-installs winget via window/system/winget_install.ps1 if missing, with silent MSI fallback).
    - Resolves the Burp version in this order: -Version, $env:BURP_VERSION,
      -Channel stable|latest, then an interactive channel prompt (tested stable
      v2026.10.1 vs. newest PortSwigger release, marked UNTESTED). When no
      console is attached it defaults to tested stable without prompting, so
      automation never blocks.
    - Dynamically queries PortSwigger release API for the latest Pro JAR.
    - Smart caching: skips downloading loader.jar, Jython 2.7.4, JRuby 9.4.9.0, and Burp Suite Pro JAR if valid and matching/newer versions exist.
    - Built-in Jython 2.7.4 & JRuby 9.4.9.0 Standalone: automatically downloads and configures UserConfigPro.json & UserConfig.json for Python & Ruby BApps.
    - Non-destructive updates: backs up older Burp Suite Pro JARs with .bk extension (never deletes them).
    - Pre-seeds JRE warning suppression flags in Windows Java Preferences registry.
    - Auto-trust Burp CA Certificate flag (--trust-ca / -t) for Windows Root Store and Firefox forks (Zen, LibreWolf, Floorp, Waterfox).
    - Generates optimized launchers (Burp.bat, burpsuitepro.cmd & Burp-Suite-Pro.vbs) with dynamic Generational ZGC (G1GC fallback), configurable RAM (BURP_MAX_RAM / 50%), HiDPI scaling, port 8080 conflict guard, and crash catcher.
    - Windows file associations (.burp and .burpstate) registered in HKCU:\Software\Classes with official icon and context menu.
    - Creates Desktop & Start Menu shortcuts for Burp Suite Professional.
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
    [string]$Channel,
    [Alias("trust-ca", "t")]
    [switch]$TrustCA
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
# Auto-Trust Burp CA Certificate Function
# ------------------------------------------------------------------------------
function Install-BurpTrustedCA {
    $certUrl = "http://127.0.0.1:8080/cert"
    $tempCert = Join-Path $env:TEMP "burpsuite-ca.cer"

    Write-Host "Checking Burp Suite proxy on http://127.0.0.1:8080..." -ForegroundColor Cyan

    $downloadSuccess = $false
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($certUrl)
        $req.Timeout = 4000
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fileStream = [System.IO.File]::Create($tempCert)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $resp.Close()
        if ((Test-Path $tempCert) -and ((Get-Item $tempCert).Length -gt 0)) {
            $downloadSuccess = $true
        }
    } catch {
        $downloadSuccess = $false
    }

    if (-not $downloadSuccess) {
        Write-Host "Burp proxy not detected on http://127.0.0.1:8080. Start Burp Suite first, then re-run 'burpsuitepro --trust-ca'" -ForegroundColor Yellow
        return $false
    }

    Write-Host "Importing Burp CA Certificate into Windows Root Certificate Store (CurrentUser)..." -ForegroundColor Cyan
    $imported = $false

    try {
        Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null
        $imported = $true
    } catch {
        try {
            certutil.exe -addstore -user -f "Root" $tempCert | Out-Null
            $imported = $true
        } catch {
            try {
                certutil.exe -addstore -f "Root" $tempCert | Out-Null
                $imported = $true
            } catch {
                Write-Error "Failed to import certificate into Windows store: $($_.Exception.Message)"
                return $false
            }
        }
    }

    if ($imported) {
        Write-Host "      [OK] Burp Suite CA Certificate successfully imported into Windows Root Certificate Store (CurrentUser)." -ForegroundColor Green
    }

    # Support Firefox and Gecko forks: Zen Browser (%APPDATA%\Zen), LibreWolf, Floorp, Waterfox, etc.
    Write-Host "Scanning for Firefox and Gecko-based browsers..." -ForegroundColor Cyan
    $browserDefinitions = @(
        @{ Name = "Firefox"; Roots = @((Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"), (Join-Path $env:APPDATA "Mozilla\Firefox")) },
        @{ Name = "Zen Browser"; Roots = @((Join-Path $env:APPDATA "zen\Profiles"), (Join-Path $env:APPDATA "Zen\Profiles"), (Join-Path $env:APPDATA "zen"), (Join-Path $env:APPDATA "Zen")) },
        @{ Name = "LibreWolf"; Roots = @((Join-Path $env:APPDATA "LibreWolf\Profiles"), (Join-Path $env:APPDATA "LibreWolf")) },
        @{ Name = "Floorp"; Roots = @((Join-Path $env:APPDATA "Floorp\Profiles"), (Join-Path $env:APPDATA "Floorp")) },
        @{ Name = "Waterfox"; Roots = @((Join-Path $env:APPDATA "Waterfox\Profiles"), (Join-Path $env:APPDATA "Waterfox"), (Join-Path $env:APPDATA "Waterfox Projects\Waterfox\Profiles"), (Join-Path $env:APPDATA "Waterfox Projects\Waterfox")) }
    )

    $detectedBrowsers = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($bDef in $browserDefinitions) {
        $profiles = [System.Collections.Generic.List[string]]::new()
        foreach ($r in $bDef.Roots) {
            if (Test-Path $r) {
                $dbs = Get-ChildItem -Path $r -Recurse -Depth 4 -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @("cert9.db", "prefs.js") }
                foreach ($db in $dbs) {
                    $dir = $db.DirectoryName
                    if (-not $profiles.Contains($dir)) {
                        $profiles.Add($dir)
                    }
                }
            }
        }
        if ($profiles.Count -gt 0) {
            $detectedBrowsers.Add([PSCustomObject]@{
                Name     = $bDef.Name
                Profiles = $profiles
            })
        }
    }

    if ($detectedBrowsers.Count -gt 0) {
        $isInteractive = $false
        try {
            if ([Environment]::UserInteractive -and $Host.UI -and $Host.UI.RawUI -and -not [Console]::IsInputRedirected) {
                $isInteractive = $true
            }
        } catch {}

        $selectedIndices = @()
        if ($isInteractive) {
            Write-Host ""
            Write-Host "=== Detected Browsers ===" -ForegroundColor Cyan
            for ($i = 0; $i -lt $detectedBrowsers.Count; $i++) {
                $pCount = $detectedBrowsers[$i].Profiles.Count
                $suffix = if ($pCount -eq 1) { "found 1 profile" } else { "found $pCount profiles" }
                Write-Host "  [$($i + 1)] $($detectedBrowsers[$i].Name) ($suffix)" -ForegroundColor White
            }
            Write-Host "  -------------------------------------" -ForegroundColor DarkGray
            Write-Host "  [A] All detected browsers (Default)" -ForegroundColor Green
            Write-Host "  [N] None (Windows System Store only)" -ForegroundColor Yellow
            Write-Host ""

            $selection = ""
            try {
                $selection = (Read-Host "Select browsers to trust [A/N or numbers like 1,2] (Default: A)").Trim()
            } catch {
                $selection = "A"
            }

            if ([string]::IsNullOrWhiteSpace($selection) -or $selection -match '^(?i)a(ll)?$') {
                $selectedIndices = @(0..($detectedBrowsers.Count - 1))
            } elseif ($selection -match '^(?i)n(one)?$') {
                $selectedIndices = @()
                Write-Host "Skipping browser-specific injection (Windows System Store only)." -ForegroundColor DarkGray
            } else {
                $parts = $selection -split '[,;\s]+'
                foreach ($p in $parts) {
                    if ($p -match '^\d+$') {
                        $num = [int]$p
                        if ($num -ge 1 -and $num -le $detectedBrowsers.Count) {
                            $idx = $num - 1
                            if ($selectedIndices -notcontains $idx) {
                                $selectedIndices += $idx
                            }
                        }
                    }
                }
                if ($selectedIndices.Count -eq 0) {
                    Write-Host "Unrecognized selection '$selection', defaulting to all detected browsers." -ForegroundColor Yellow
                    $selectedIndices = @(0..($detectedBrowsers.Count - 1))
                }
            }
        } else {
            # Non-interactive: default to all detected browsers
            $selectedIndices = @(0..($detectedBrowsers.Count - 1))
        }

        foreach ($idx in $selectedIndices) {
            $targetBrowser = $detectedBrowsers[$idx]
            Write-Host "Configuring $($targetBrowser.Name)..." -ForegroundColor Cyan
            foreach ($pDir in $targetBrowser.Profiles) {
                $pName = Split-Path -Leaf $pDir
                try {
                    $userJsPath = Join-Path $pDir "user.js"
                    $prefLine = 'user_pref("security.enterprise_roots.enabled", true);'
                    $existingContent = if (Test-Path $userJsPath) { Get-Content -Path $userJsPath -Raw -ErrorAction SilentlyContinue } else { "" }
                    if ($existingContent -notlike "*security.enterprise_roots.enabled*") {
                        Add-Content -Path $userJsPath -Value "`r`n$prefLine" -Force -Encoding UTF8
                    }
                    Write-Host "      [OK] $($targetBrowser.Name) ($pName): Enterprise root CA trust enabled" -ForegroundColor Green
                } catch {
                    Write-Warning "Could not update user.js in $pName"
                }

                # If Mozilla NSS certutil is available, also import directly into cert9.db
                $nssCertUtil = Get-Command certutil.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike "*System32*" }
                if ($nssCertUtil) {
                    try {
                        & $nssCertUtil.Source -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i $tempCert -d "sql:$pDir" 2>$null
                    } catch {}
                }
            }
        }
    } else {
        Write-Host "      [*] No active Firefox/Zen/LibreWolf/Floorp/Waterfox profiles detected in %APPDATA%." -ForegroundColor DarkGray
    }

    Remove-Item -Path $tempCert -Force -ErrorAction SilentlyContinue
    if ($selectedIndices.Count -gt 0) {
        Write-Host "`n[OK] Burp Suite CA Certificate successfully trusted across Windows & selected browsers!" -ForegroundColor Green
    } else {
        Write-Host "`n[OK] Burp Suite CA Certificate successfully trusted in Windows Root Certificate Store!" -ForegroundColor Green
    }
    return $true
}

if ($TrustCA) {
    Write-Host "Executing Burp CA certificate auto-trust utility..." -ForegroundColor Cyan
    $res = Install-BurpTrustedCA
    if ($res) { exit 0 } else { exit 1 }
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
    Write-Host "      Target directory exists. Preserving existing contents (non-destructive)." -ForegroundColor DarkGray
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
    $BURP_VERSION = ($Version.Trim() -replace '^v', '')
    $isCustomVersion = $true
    Write-Host "      Using user-specified version: $BURP_VERSION" -ForegroundColor Green
} elseif (-not [string]::IsNullOrWhiteSpace($env:BURP_VERSION)) {
    $BURP_VERSION = ($env:BURP_VERSION.Trim() -replace '^v', '')
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
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
)

$loaderDownloaded = $false
if ((Test-Path $TargetLoader) -and ((Get-Item $TargetLoader).Length -gt 10240) -and -not $ForceDownload) {
    $lBytes = (Get-Item $TargetLoader).Length
    $lKb = [math]::Round($lBytes / 1KB, 1)
    Write-Host "      [OK] Valid loader.jar already exists in $InstallDir ($lKb KB). Skipping download." -ForegroundColor Green
    $loaderDownloaded = $true
} else {
    if ($ForceDownload -and (Test-Path $TargetLoader)) {
        Write-Host "      [*] -ForceDownload specified. Re-downloading loader.jar..." -ForegroundColor Yellow
    }
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
# 5. Manage Burp Suite Pro JAR Releases (Smart Caching & Non-Destructive Backup)
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

# Smart caching / download skipping check
if (-not $ForceDownload) {
    # Check 1: Check if the exact requested version $JarName already exists and is valid (> 10MB)
    if ((Test-Path $TargetJar) -and ((Get-Item $TargetJar).Length -gt 10485760)) {
        $jarSizeMb = [math]::Round((Get-Item $TargetJar).Length / 1MB, 1)
        Write-Host "      [OK] Exact requested version $BURP_VERSION ($JarName) already exists in target directory ($jarSizeMb MB)." -ForegroundColor Green
        Write-Host "      Matching version found. Skipping download." -ForegroundColor Green
        $skipDownload = $true
    } else {
        # Check 2: Check if any existing JAR in $InstallDir has version >= requested version
        $existingJars = Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.jar' -and $_.Length -gt 10485760 -and $_.BaseName -match '^burpsuite_pro_v(\d+.*)$' }

        if ($existingJars) {
            $sortedJars = $existingJars | Sort-Object {
                $v = $_.BaseName -replace '^burpsuite_pro_v', ''
                Parse-VersionSafe -VerString $v
            }
            $highestJar = $sortedJars | Select-Object -Last 1

            if ($highestJar) {
                $existingVersion = $highestJar.BaseName -replace '^burpsuite_pro_v', ''
                $cmp = Compare-VersionStrings -v1 $existingVersion -v2 $BURP_VERSION

                if ($cmp -ge 0) {
                    $jarSizeMb = [math]::Round($highestJar.Length / 1MB, 1)
                    if ($cmp -eq 0) {
                        Write-Host "      [OK] Existing version ($existingVersion, $jarSizeMb MB) matches requested version ($BURP_VERSION). Skipping download." -ForegroundColor Green
                    } else {
                        Write-Host "      [OK] Installed version ($existingVersion, $jarSizeMb MB) is newer than requested version ($BURP_VERSION). Skipping download." -ForegroundColor Green
                    }
                    $skipDownload = $true
                    $BURP_VERSION = $existingVersion
                    $JarName = $highestJar.Name
                    $TargetJar = $highestJar.FullName
                } else {
                    Write-Host "      [*] Found older version ($existingVersion). Upgrading to requested version ($BURP_VERSION)..." -ForegroundColor Yellow
                }
            }
        }
    }
} else {
    Write-Host "      [*] -ForceDownload specified. Forcing fresh download of $JarName..." -ForegroundColor Yellow
}

if (-not $skipDownload) {
    # Ensure TargetJar and DownloadUrl match the active version being downloaded
    $TargetJar = Join-Path $InstallDir $JarName
    $DownloadUrl = "https://portswigger.net/burp/releases/download?product=desktop&version=$BURP_VERSION&type=Jar"
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

    Write-Host "      Calculating cryptographic checksums..." -ForegroundColor DarkGray
    $sha256 = (Get-FileHash -Path $TargetJar -Algorithm SHA256).Hash
    $md5 = (Get-FileHash -Path $TargetJar -Algorithm MD5).Hash
    Write-Host "      SHA256: $sha256" -ForegroundColor DarkCyan
    Write-Host "      MD5:    $md5" -ForegroundColor DarkCyan
}

# ------------------------------------------------------------------------------
# Backup older JARs with .bk extension (DO NOT DELETE - Non-Destructive)
# ------------------------------------------------------------------------------
$olderJars = Get-ChildItem -Path $InstallDir -Filter "burpsuite_pro_v*.jar" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.jar' -and $_.Name -ne $JarName }

if ($olderJars) {
    Write-Host "      Backing up older Burp Suite Pro JAR files with .bk extension..." -ForegroundColor Cyan
    foreach ($oldJar in $olderJars) {
        $bkName = "$($oldJar.Name).bk"
        $bkPath = Join-Path $InstallDir $bkName
        Write-Host "      Backing up older version: $($oldJar.Name) -> $bkName" -ForegroundColor DarkGray
        try {
            if (Test-Path $bkPath) {
                Remove-Item -Path $bkPath -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $oldJar.FullName -NewName $bkName -Force
            Write-Host "      [OK] Preserved older release: $($oldJar.Name) -> $bkName" -ForegroundColor Green
        } catch {
            Write-Warning "Could not backup $($oldJar.Name) to $bkName: $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------------------------------------------
# 6. Deploy Assets, Built-in Jython 2.7.4 & User Configuration
# ------------------------------------------------------------------------------
Write-Host "`n(6/8) Deploying assets, Jython 2.7.4, JRuby 9.4.9.0 & preferences..." -ForegroundColor Cyan

# 6A. Deploy Assets (.config.ini & burp_suite_pro.ico)
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

# 6B. Built-in Jython Standalone 2.7.4 Support
Write-Host "      Configuring Jython Standalone 2.7.4 (Python BApps support)..." -ForegroundColor DarkCyan
$TargetJython = Join-Path $InstallDir "jython-standalone-2.7.4.jar"
$jythonSources = @(
    "https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar",
    "https://search.maven.org/remotecontent?filepath=org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"
)

$jythonReady = $false
if ((Test-Path $TargetJython) -and ((Get-Item $TargetJython).Length -gt 20MB) -and -not $ForceDownload) {
    $jMb = [math]::Round((Get-Item $TargetJython).Length / 1MB, 1)
    Write-Host "      [OK] Valid jython-standalone-2.7.4.jar already exists in $InstallDir ($jMb MB). Skipping download." -ForegroundColor Green
    $jythonReady = $true
} else {
    if ($ForceDownload -and (Test-Path $TargetJython)) {
        Write-Host "      [*] -ForceDownload specified. Re-downloading Jython 2.7.4..." -ForegroundColor Yellow
    }
    $tempJython = "$TargetJython.tmp"
    foreach ($url in $jythonSources) {
        try {
            Write-Host "      Downloading Jython 2.7.4 from $url (~48MB)..." -ForegroundColor Yellow
            Download-FileWithProgress -Url $url -OutputFile $tempJython -Description "Downloading Jython Standalone 2.7.4"
            if ((Test-Path $tempJython) -and ((Get-Item $tempJython).Length -gt 20MB)) {
                Move-Item -Path $tempJython -Destination $TargetJython -Force
                $jMb = [math]::Round((Get-Item $TargetJython).Length / 1MB, 1)
                Write-Host "      [OK] Downloaded and verified jython-standalone-2.7.4.jar ($jMb MB)." -ForegroundColor Green
                $jythonReady = $true
                break
            } else {
                if (Test-Path $tempJython) {
                    Remove-Item -Path $tempJython -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            if (Test-Path $tempJython) {
                Remove-Item -Path $tempJython -Force -ErrorAction SilentlyContinue
            }
            Write-Warning "Download from $url failed: $($_.Exception.Message)"
        }
    }
}

# 6C. Built-in JRuby Standalone 9.4.9.0 Support
Write-Host "      Configuring JRuby Standalone 9.4.9.0 (Ruby BApps support)..." -ForegroundColor DarkCyan
$TargetJruby = Join-Path $InstallDir "jruby-complete-9.4.9.0.jar"
$jrubySources = @(
    "https://repo1.maven.org/maven2/org/jruby/jruby-complete/9.4.9.0/jruby-complete-9.4.9.0.jar",
    "https://search.maven.org/remotecontent?filepath=org/jruby/jruby-complete/9.4.9.0/jruby-complete-9.4.9.0.jar",
    "https://repo.maven.apache.org/maven2/org/jruby/jruby-complete/9.4.9.0/jruby-complete-9.4.9.0.jar"
)

$jrubyReady = $false
if ((Test-Path $TargetJruby) -and ((Get-Item $TargetJruby).Length -gt 30MB) -and -not $ForceDownload) {
    $rMb = [math]::Round((Get-Item $TargetJruby).Length / 1MB, 1)
    Write-Host "      [OK] Valid jruby-complete-9.4.9.0.jar already exists in $InstallDir ($rMb MB). Skipping download." -ForegroundColor Green
    $jrubyReady = $true
} else {
    if ($ForceDownload -and (Test-Path $TargetJruby)) {
        Write-Host "      [*] -ForceDownload specified. Re-downloading JRuby 9.4.9.0..." -ForegroundColor Yellow
    }
    $tempJruby = "$TargetJruby.tmp"
    foreach ($url in $jrubySources) {
        try {
            Write-Host "      Downloading JRuby 9.4.9.0 from $url (~32MB)..." -ForegroundColor Yellow
            Download-FileWithProgress -Url $url -OutputFile $tempJruby -Description "Downloading JRuby Standalone 9.4.9.0"
            if ((Test-Path $tempJruby) -and ((Get-Item $tempJruby).Length -gt 30MB)) {
                Move-Item -Path $tempJruby -Destination $TargetJruby -Force
                $rMb = [math]::Round((Get-Item $TargetJruby).Length / 1MB, 1)
                Write-Host "      [OK] Downloaded and verified jruby-complete-9.4.9.0.jar ($rMb MB)." -ForegroundColor Green
                $jrubyReady = $true
                break
            } else {
                if (Test-Path $tempJruby) {
                    Remove-Item -Path $tempJruby -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            if (Test-Path $tempJruby) {
                Remove-Item -Path $tempJruby -Force -ErrorAction SilentlyContinue
            }
            Write-Warning "Download from $url failed: $($_.Exception.Message)"
        }
    }
}

# 6D. Automatically configure Burp User Config (UserConfigPro.json and UserConfig.json) in User Profile and AppData
Write-Host "      Configuring BApp extender paths in Burp user configuration..." -ForegroundColor DarkCyan
$configTargets = [System.Collections.Generic.List[string]]::new()
if ($env:USERPROFILE) {
    $configTargets.Add((Join-Path $env:USERPROFILE ".BurpSuite\UserConfigPro.json"))
    $configTargets.Add((Join-Path $env:USERPROFILE ".BurpSuite\UserConfig.json"))
}
if ($env:APPDATA) {
    $configTargets.Add((Join-Path $env:APPDATA "BurpSuite\UserConfigPro.json"))
    $configTargets.Add((Join-Path $env:APPDATA "BurpSuite\UserConfig.json"))
}

foreach ($cfgPath in $configTargets) {
    try {
        $cfgDir = Split-Path -Parent $cfgPath
        if (-not (Test-Path $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }

        $cfgObj = $null
        if (Test-Path $cfgPath) {
            try {
                $rawText = Get-Content -Path $cfgPath -Raw -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($rawText)) {
                    $cfgObj = $rawText | ConvertFrom-Json -ErrorAction Stop
                }
            } catch {
                Write-Warning "Could not parse existing $cfgPath as JSON. Creating backup."
                Copy-Item -Path $cfgPath -Destination "$cfgPath.bk" -Force -ErrorAction SilentlyContinue
                $cfgObj = $null
            }
        }

        if ($null -eq $cfgObj) {
            $cfgObj = [PSCustomObject]@{
                user_options = [PSCustomObject]@{
                    extender = [PSCustomObject]@{
                        python = [PSCustomObject]@{
                            location_of_jython_standalone_jar_file = if (Test-Path $TargetJython) { $TargetJython } else { "" }
                        }
                        ruby = [PSCustomObject]@{
                            location_of_jruby_jar_file = if (Test-Path $TargetJruby) { $TargetJruby } else { "" }
                        }
                    }
                }
            }
        } else {
            if (-not ($cfgObj.PSObject.Properties['user_options']) -or ($null -eq $cfgObj.user_options)) {
                $cfgObj | Add-Member -NotePropertyName "user_options" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            if (-not ($cfgObj.user_options.PSObject.Properties['extender']) -or ($null -eq $cfgObj.user_options.extender)) {
                $cfgObj.user_options | Add-Member -NotePropertyName "extender" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            if (-not ($cfgObj.user_options.extender.PSObject.Properties['python']) -or ($null -eq $cfgObj.user_options.extender.python)) {
                $cfgObj.user_options.extender | Add-Member -NotePropertyName "python" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            if (-not ($cfgObj.user_options.extender.PSObject.Properties['ruby']) -or ($null -eq $cfgObj.user_options.extender.ruby)) {
                $cfgObj.user_options.extender | Add-Member -NotePropertyName "ruby" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }

            if (Test-Path $TargetJython) {
                if ($cfgObj.user_options.extender.python.PSObject.Properties['location_of_jython_standalone_jar_file']) {
                    $cfgObj.user_options.extender.python.location_of_jython_standalone_jar_file = $TargetJython
                } else {
                    $cfgObj.user_options.extender.python | Add-Member -NotePropertyName "location_of_jython_standalone_jar_file" -NotePropertyValue $TargetJython -Force
                }
            }

            if (Test-Path $TargetJruby) {
                if ($cfgObj.user_options.extender.ruby.PSObject.Properties['location_of_jruby_jar_file']) {
                    $cfgObj.user_options.extender.ruby.location_of_jruby_jar_file = $TargetJruby
                } else {
                    $cfgObj.user_options.extender.ruby | Add-Member -NotePropertyName "location_of_jruby_jar_file" -NotePropertyValue $TargetJruby -Force
                }
            }
        }

        $jsonOut = $cfgObj | ConvertTo-Json -Depth 32
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($cfgPath, $jsonOut, $utf8NoBom)
        Write-Host "      [OK] Configured Jython & JRuby paths in: $cfgPath" -ForegroundColor Green
    } catch {
        Write-Warning "Could not configure extender paths in $cfgPath: $($_.Exception.Message)"
    }
}

# 6E. Pre-seed JRE Warning Suppression in Windows Java Preferences
function Set-BurpJreWarningSuppression {
    Write-Host "      Configuring JRE warning suppression in Windows Java Preferences registry..." -ForegroundColor DarkCyan
    try {
        $burpPrefKey = "HKCU:\Software\JavaSoft\Prefs\burp"
        if (-not (Test-Path $burpPrefKey)) {
            New-Item -Path $burpPrefKey -Force | Out-Null
        }

        $jreAlertValues = [ordered]@{
            "suite.alertsdisabledforjre-3189538875"      = "true"
            "suite.alertsdisabledforjre-1115054815"      = "true"
            "burp.suite.alertsdisabledforjre-3189538875" = "true"
            "burp.suite.alertsdisabledforjre-1115054815" = "true"
            "burp.suite.alertsdisabledforjre-1872878544" = "true"
            "burp.suite.alertsdisabledforjre-413592390"  = "true"
        }

        foreach ($entry in $jreAlertValues.GetEnumerator()) {
            Set-ItemProperty -Path $burpPrefKey -Name $entry.Key -Value $entry.Value -Type String -Force
        }
        Write-Host "      [OK] Pre-seeded JRE warning suppression flags in $burpPrefKey" -ForegroundColor Green
    } catch {
        Write-Warning "Could not pre-seed JRE warning suppression registry keys: $($_.Exception.Message)"
    }
}
Set-BurpJreWarningSuppression

# ------------------------------------------------------------------------------
# 7. Create Launchers & Desktop/Start Menu Shortcuts
# ------------------------------------------------------------------------------
Write-Host "`n(7/8) Creating launchers and Windows shortcuts..." -ForegroundColor Cyan

# 7A. Burp.bat (Direct / CLI launcher with Generational ZGC, High-RAM, HiDPI, Port 8080 Guard, and Crash Catcher)
$BatPath = Join-Path $InstallDir "Burp.bat"
$BatLines = @(
    "@echo off",
    "setlocal",
    "cd /d `"%~dp0`"",
    "",
    "rem CLI helper flags for Burp Suite Professional",
    "if /i `"%~1`"==`"--keygen`" goto keygen",
    "if /i `"%~1`"==`"-k`" goto keygen",
    "if /i `"%~1`"==`"--trust-ca`" goto trust_ca",
    "if /i `"%~1`"==`"-t`" goto trust_ca",
    "if /i `"%~1`"==`"--version`" goto version",
    "if /i `"%~1`"==`"-v`" goto version",
    "if /i `"%~1`"==`"--path`" goto path",
    "if /i `"%~1`"==`"-p`" goto path",
    "if /i `"%~1`"==`"--help`" goto help",
    "if /i `"%~1`"==`"-h`" goto help",
    "goto launch",
    "",
    ":keygen",
    "if exist `"$($validJava.Path)`" (",
    "    start `"`" `"$($validJava.Path)`" -jar `"%~dp0loader.jar`"",
    ") else if exist `"%JAVA_HOME%\bin\java.exe`" (",
    "    start `"`" `"%JAVA_HOME%\bin\java.exe`" -jar `"%~dp0loader.jar`"",
    ") else (",
    "    start `"`" java -jar `"%~dp0loader.jar`"",
    ")",
    "endlocal",
    "exit /b 0",
    "",
    ":trust_ca",
    "if exist `"%~dp0trust-ca.ps1`" (",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0trust-ca.ps1`"",
    ") else (",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"`$u='http://127.0.0.1:8080/cert'; `$c=Join-Path `$env:TEMP 'burpsuite-ca.cer'; try { `$req=[System.Net.HttpWebRequest][System.Net.WebRequest]::Create(`$u); `$req.Timeout=4000; `$resp=`$req.GetResponse(); `$s=`$resp.GetResponseStream(); `$fs=[System.IO.File]::Create(`$c); `$s.CopyTo(`$fs); `$fs.Close(); `$resp.Close(); } catch { Write-Host 'Burp proxy not detected on http://127.0.0.1:8080. Start Burp Suite first, then re-run ''burpsuitepro --trust-ca''' -ForegroundColor Yellow; exit 1 }; if ((Test-Path `$c) -and ((Get-Item `$c).Length -gt 0)) { try { Import-Certificate -FilePath `$c -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null } catch { certutil.exe -addstore -f Root `$c | Out-Null }; Write-Host '[OK] Burp Suite CA Certificate successfully imported into Windows Root Certificate Store (CurrentUser).' -ForegroundColor Green; Remove-Item `$c -Force -ErrorAction SilentlyContinue; exit 0 } else { Write-Host 'Burp proxy not detected on http://127.0.0.1:8080. Start Burp Suite first, then re-run ''burpsuitepro --trust-ca''' -ForegroundColor Yellow; exit 1 }`"",
    ")",
    "endlocal",
    "exit /b %ERRORLEVEL%",
    "",
    ":version",
    "echo Burp Suite Professional v$BURP_VERSION ($JarName)",
    "endlocal",
    "exit /b 0",
    "",
    ":path",
    "echo %~dp0",
    "endlocal",
    "exit /b 0",
    "",
    ":help",
    "echo Burp Suite Professional Launcher",
    "echo.",
    "echo Usage:",
    "echo   burpsuitepro [options] [burp-arguments]",
    "echo   Burp.bat [options] [burp-arguments]",
    "echo.",
    "echo Options:",
    "echo   -k, --keygen    Launch the key loader GUI (loader.jar)",
    "echo   -t, --trust-ca  Import and trust Burp CA certificate in Windows ^& browsers",
    "echo   -v, --version   Print current version and JAR name",
    "echo   -p, --path      Print installation directory path",
    "echo   -h, --help      Show quick usage help",
    "echo.",
    "echo All other arguments are passed directly to Burp Suite Pro.",
    "endlocal",
    "exit /b 0",
    "",
    ":launch",
    "rem 1. Resolve Java 21+ binary",
    "if exist `"$($validJava.Path)`" (",
    "    set `"JAVA_BIN=$($validJava.Path)`"",
    ") else if exist `"%JAVA_HOME%\bin\java.exe`" (",
    "    set `"JAVA_BIN=%JAVA_HOME%\bin\java.exe`"",
    ") else (",
    "    set `"JAVA_BIN=java.exe`"",
    ")",
    "",
    "rem 2. Dynamic Memory Sizing: BURP_MAX_RAM, BURP_RAM, BURP_MEMORY or default to 50% RAM",
    "set `"MEM_OPTS=-XX:MaxRAMPercentage=50`"",
    "set `"BURP_MEM_VAL=`"",
    "if defined BURP_MAX_RAM set `"BURP_MEM_VAL=%BURP_MAX_RAM%`"",
    "if not defined BURP_MEM_VAL if defined BURP_RAM set `"BURP_MEM_VAL=%BURP_RAM%`"",
    "if not defined BURP_MEM_VAL if defined BURP_MEMORY set `"BURP_MEM_VAL=%BURP_MEMORY%`"",
    "if defined BURP_MEM_VAL (",
    "    echo %BURP_MEM_VAL% | findstr /i `"^-Xmx`" >nul",
    "    if errorlevel 1 (",
    "        set `"MEM_OPTS=-Xmx%BURP_MEM_VAL%`"",
    "    ) else (",
    "        set `"MEM_OPTS=%BURP_MEM_VAL%`"",
    "    )",
    ")",
    "",
    "rem 3. Advanced JVM Garbage Collector: Generational ZGC check with G1GC fallback",
    "set `"GC_OPTS=-XX:+UseG1GC`"",
    "`"%JAVA_BIN%`" -XX:+UseZGC -XX:+ZGenerational -version >nul 2>&1",
    "if %ERRORLEVEL% equ 0 (",
    "    set `"GC_OPTS=-XX:+UseZGC -XX:+ZGenerational`"",
    ")",
    "",
    "rem 4. Port 8080 Conflict Guard",
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { exit 10 }`" >nul 2>&1",
    "if %ERRORLEVEL% equ 10 (",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Write-Host '[!] Warning: Port 8080 is already occupied by another process. Burp proxy may encounter a bind collision.' -ForegroundColor Yellow`"",
    "    start `"`" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Warning: Port 8080 is already occupied by another process. Burp proxy may encounter a bind collision.', 'Burp Suite Port Warning', 0, 48)`"",
    ")",
    "",
    "rem 5. HiDPI & Antialiasing Flags",
    "set `"UI_OPTS=-Dsun.java2d.uiScale=auto -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true`"",
    "",
    "rem 6. Module Access Options",
    "set `"MODULE_OPTS=--add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED`"",
    "",
    "rem 7. Execute Burp Suite Professional and trap exit code",
    "`"%JAVA_BIN%`" %GC_OPTS% %MEM_OPTS% %UI_OPTS% %MODULE_OPTS% -javaagent:`"%~dp0loader.jar`" -jar `"%~dp0$JarName`" %*",
    "set `"BURP_EXIT_CODE=%ERRORLEVEL%`"",
    "",
    "rem 8. Crash Catcher & Error Dialog",
    "if %BURP_EXIT_CODE% neq 0 (",
    "    echo [!] Burp Suite Pro exited with error code %BURP_EXIT_CODE%.",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Burp Suite Professional exited with error code ' + `$env:BURP_EXIT_CODE + '. Please check Java runtime and configuration.', 'Burp Suite Error', 0, 16)`"",
    ")",
    "",
    "endlocal",
    "exit /b %BURP_EXIT_CODE%",
    ""
)
$BatContent = $BatLines -join "`r`n"
[System.IO.File]::WriteAllText($BatPath, $BatContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $BatPath" -ForegroundColor Green

# 7B. Burp-Suite-Pro.vbs (Silent launcher forwarding arguments to Burp.bat without console window)
$VbsPath = Join-Path $InstallDir "Burp-Suite-Pro.vbs"
$VbsLines = @(
    "Set WshShell = CreateObject(`"WScript.Shell`")",
    "Set fso = CreateObject(`"Scripting.FileSystemObject`")",
    "batPath = fso.GetParentFolderName(WScript.ScriptFullName) & `"\Burp.bat`"",
    "args = `"`"",
    "For Each arg In WScript.Arguments",
    "    args = args & `" `" & Chr(34) & Replace(arg, Chr(34), Chr(34) & Chr(34)) & Chr(34)",
    "Next",
    "WshShell.Run Chr(34) & batPath & Chr(34) & args, 0, False",
    "Set WshShell = Nothing",
    "Set fso = Nothing"
)
$VbsContent = ($VbsLines -join "`r`n") + "`r`n"
[System.IO.File]::WriteAllText($VbsPath, $VbsContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $VbsPath" -ForegroundColor Green

# 7C. trust-ca.ps1 (Burp CA Certificate Trust Utility with Browser Selection Menu)
$TrustCaPath = Join-Path $InstallDir "trust-ca.ps1"
$TrustCaLines = @(
    "<#",
    ".SYNOPSIS",
    "    Automated Burp Suite CA Certificate Trust Utility for Windows.",
    ".DESCRIPTION",
    "    Checks Burp proxy on http://127.0.0.1:8080/cert, downloads CA certificate,",
    "    imports into Windows Root Certificate Store (CurrentUser), and provides an interactive",
    "    selection menu for Firefox and forks (Zen Browser, LibreWolf, Floorp, Waterfox).",
    "#>",
    "[CmdletBinding()]",
    "param()",
    "",
    "`$ErrorActionPreference = 'Stop'",
    "`$certUrl = 'http://127.0.0.1:8080/cert'",
    "`$tempCert = Join-Path `$env:TEMP 'burpsuite-ca.cer'",
    "",
    "Write-Host 'Checking Burp Suite proxy on http://127.0.0.1:8080...' -ForegroundColor Cyan",
    "",
    "`$downloadSuccess = `$false",
    "try {",
    "    `$req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create(`$certUrl)",
    "    `$req.Timeout = 4000",
    "    `$resp = `$req.GetResponse()",
    "    `$stream = `$resp.GetResponseStream()",
    "    `$fileStream = [System.IO.File]::Create(`$tempCert)",
    "    `$stream.CopyTo(`$fileStream)",
    "    `$fileStream.Close()",
    "    `$resp.Close()",
    "    if ((Test-Path `$tempCert) -and ((Get-Item `$tempCert).Length -gt 0)) {",
    "        `$downloadSuccess = `$true",
    "    }",
    "} catch {",
    "    `$downloadSuccess = `$false",
    "}",
    "",
    "if (-not `$downloadSuccess) {",
    "    Write-Host 'Burp proxy not detected on http://127.0.0.1:8080. Start Burp Suite first, then re-run ''burpsuitepro --trust-ca''' -ForegroundColor Yellow",
    "    exit 1",
    "}",
    "",
    "Write-Host 'Importing Burp CA Certificate into Windows Root Certificate Store (CurrentUser)...' -ForegroundColor Cyan",
    "`$imported = `$false",
    "",
    "try {",
    "    Import-Certificate -FilePath `$tempCert -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null",
    "    `$imported = `$true",
    "} catch {",
    "    try {",
    "        certutil.exe -addstore -user -f 'Root' `$tempCert | Out-Null",
    "        `$imported = `$true",
    "    } catch {",
    "        try {",
    "            certutil.exe -addstore -f 'Root' `$tempCert | Out-Null",
    "            `$imported = `$true",
    "        } catch {",
    "            Write-Error `"Failed to import certificate into Windows store: `$(`$_.Exception.Message)`"",
    "            exit 1",
    "        }",
    "    }",
    "}",
    "",
    "if (`$imported) {",
    "    Write-Host '      [OK] Burp Suite CA Certificate successfully imported into Windows Root Certificate Store (CurrentUser).' -ForegroundColor Green",
    "}",
    "",
    "# Support Firefox and Gecko forks: Zen Browser (%APPDATA%\Zen), LibreWolf, Floorp, Waterfox, etc.",
    "Write-Host 'Scanning for Firefox and Gecko-based browsers...' -ForegroundColor Cyan",
    "`$browserDefinitions = @(",
    "    @{ Name = 'Firefox'; Roots = @((Join-Path `$env:APPDATA 'Mozilla\Firefox\Profiles'), (Join-Path `$env:APPDATA 'Mozilla\Firefox')) },",
    "    @{ Name = 'Zen Browser'; Roots = @((Join-Path `$env:APPDATA 'zen\Profiles'), (Join-Path `$env:APPDATA 'Zen\Profiles'), (Join-Path `$env:APPDATA 'zen'), (Join-Path `$env:APPDATA 'Zen')) },",
    "    @{ Name = 'LibreWolf'; Roots = @((Join-Path `$env:APPDATA 'LibreWolf\Profiles'), (Join-Path `$env:APPDATA 'LibreWolf')) },",
    "    @{ Name = 'Floorp'; Roots = @((Join-Path `$env:APPDATA 'Floorp\Profiles'), (Join-Path `$env:APPDATA 'Floorp')) },",
    "    @{ Name = 'Waterfox'; Roots = @((Join-Path `$env:APPDATA 'Waterfox\Profiles'), (Join-Path `$env:APPDATA 'Waterfox'), (Join-Path `$env:APPDATA 'Waterfox Projects\Waterfox\Profiles'), (Join-Path `$env:APPDATA 'Waterfox Projects\Waterfox')) }",
    ")",
    "",
    "`$detectedBrowsers = [System.Collections.Generic.List[PSCustomObject]]::new()",
    "foreach (`$bDef in `$browserDefinitions) {",
    "    `$profiles = [System.Collections.Generic.List[string]]::new()",
    "    foreach (`$r in `$bDef.Roots) {",
    "        if (Test-Path `$r) {",
    "            `$dbs = Get-ChildItem -Path `$r -Recurse -Depth 4 -ErrorAction SilentlyContinue | Where-Object { `$_.Name -in @('cert9.db', 'prefs.js') }",
    "            foreach (`$db in `$dbs) {",
    "                `$dir = `$db.DirectoryName",
    "                if (-not `$profiles.Contains(`$dir)) {",
    "                    `$profiles.Add(`$dir)",
    "                }",
    "            }",
    "        }",
    "    }",
    "    if (`$profiles.Count -gt 0) {",
    "        `$detectedBrowsers.Add([PSCustomObject]@{",
    "            Name     = `$bDef.Name",
    "            Profiles = `$profiles",
    "        })",
    "    }",
    "}",
    "",
    "if (`$detectedBrowsers.Count -gt 0) {",
    "    `$isInteractive = `$false",
    "    try {",
    "        if ([Environment]::UserInteractive -and `$Host.UI -and `$Host.UI.RawUI -and -not [Console]::IsInputRedirected) {",
    "            `$isInteractive = `$true",
    "        }",
    "    } catch {}",
    "",
    "    `$selectedIndices = @()",
    "    if (`$isInteractive) {",
    "        Write-Host ''",
    "        Write-Host '=== Detected Browsers ===' -ForegroundColor Cyan",
    "        for (`$i = 0; `$i -lt `$detectedBrowsers.Count; `$i++) {",
    "            `$pCount = `$detectedBrowsers[`$i].Profiles.Count",
    "            `$suffix = if (`$pCount -eq 1) { 'found 1 profile' } else { `"found `$pCount profiles`" }",
    "            Write-Host `"  [`$(`$i + 1)] `$(`$detectedBrowsers[`$i].Name) (`$suffix)`" -ForegroundColor White",
    "        }",
    "        Write-Host '  -------------------------------------' -ForegroundColor DarkGray",
    "        Write-Host '  [A] All detected browsers (Default)' -ForegroundColor Green",
    "        Write-Host '  [N] None (Windows System Store only)' -ForegroundColor Yellow",
    "        Write-Host ''",
    "",
    "        `$selection = ''",
    "        try {",
    "            `$selection = (Read-Host 'Select browsers to trust [A/N or numbers like 1,2] (Default: A)').Trim()",
    "        } catch {",
    "            `$selection = 'A'",
    "        }",
    "",
    "        if ([string]::IsNullOrWhiteSpace(`$selection) -or `$selection -match '^(?i)a(ll)?$') {",
    "            `$selectedIndices = @(0..(`$detectedBrowsers.Count - 1))",
    "        } elseif (`$selection -match '^(?i)n(one)?$') {",
    "            `$selectedIndices = @()",
    "            Write-Host 'Skipping browser-specific injection (Windows System Store only).' -ForegroundColor DarkGray",
    "        } else {",
    "            `$parts = `$selection -split '[,;\s]+'",
    "            foreach (`$p in `$parts) {",
    "                if (`$p -match '^\d+$') {",
    "                    `$num = [int]`$p",
    "                    if (`$num -ge 1 -and `$num -le `$detectedBrowsers.Count) {",
    "                        `$idx = `$num - 1",
    "                        if (`$selectedIndices -notcontains `$idx) {",
    "                            `$selectedIndices += `$idx",
    "                        }",
    "                    }",
    "                }",
    "            }",
    "            if (`$selectedIndices.Count -eq 0) {",
    "                Write-Host `"Unrecognized selection '`$selection', defaulting to all detected browsers.`" -ForegroundColor Yellow",
    "                `$selectedIndices = @(0..(`$detectedBrowsers.Count - 1))",
    "            }",
    "        }",
    "    } else {",
    "        # Non-interactive: default to all detected browsers",
    "        `$selectedIndices = @(0..(`$detectedBrowsers.Count - 1))",
    "    }",
    "",
    "    foreach (`$idx in `$selectedIndices) {",
    "        `$targetBrowser = `$detectedBrowsers[`$idx]",
    "        Write-Host `"Configuring `$(`$targetBrowser.Name)...`" -ForegroundColor Cyan",
    "        foreach (`$pDir in `$targetBrowser.Profiles) {",
    "            `$pName = Split-Path -Leaf `$pDir",
    "            try {",
    "                `$userJsPath = Join-Path `$pDir 'user.js'",
    "                `$prefLine = 'user_pref(`"security.enterprise_roots.enabled`", true);'",
    "                `$existingContent = if (Test-Path `$userJsPath) { Get-Content -Path `$userJsPath -Raw -ErrorAction SilentlyContinue } else { '' }",
    "                if (`$existingContent -notlike '*security.enterprise_roots.enabled*') {",
    "                    Add-Content -Path `$userJsPath -Value `"`r`n`$prefLine`" -Force -Encoding UTF8",
    "                }",
    "                Write-Host `"      [OK] `$(`$targetBrowser.Name) (`$pName): Enterprise root CA trust enabled`" -ForegroundColor Green",
    "            } catch {",
    "                Write-Warning `"Could not update user.js in `$pName`"",
    "            }",
    "            `$nssCertUtil = Get-Command certutil.exe -ErrorAction SilentlyContinue | Where-Object { `$_.Source -notlike '*System32*' }",
    "            if (`$nssCertUtil) {",
    "                try {",
    "                    & `$nssCertUtil.Source -A -n 'PortSwigger CA' -t 'TCu,Cu,Tu' -i `$tempCert -d `"sql:`$pDir`" 2>`$null",
    "                } catch {}",
    "            }",
    "        }",
    "    }",
    "} else {",
    "    Write-Host '      [*] No active Firefox/Zen/LibreWolf/Floorp/Waterfox profiles detected in %APPDATA%.' -ForegroundColor DarkGray",
    "}",
    "",
    "Remove-Item -Path `$tempCert -Force -ErrorAction SilentlyContinue",
    "if (`$selectedIndices.Count -gt 0) {",
    "    Write-Host '`n[OK] Burp Suite CA Certificate successfully trusted across Windows & selected browsers!' -ForegroundColor Green",
    "} else {",
    "    Write-Host '`n[OK] Burp Suite CA Certificate successfully trusted in Windows Root Certificate Store!' -ForegroundColor Green",
    "}",
    "exit 0"
)
$TrustCaContent = $TrustCaLines -join "`r`n"
[System.IO.File]::WriteAllText($TrustCaPath, $TrustCaContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $TrustCaPath" -ForegroundColor Green

# 7D. Create burpsuitepro.cmd CLI wrapper for PATH
$CliCmdPath = Join-Path $InstallDir "burpsuitepro.cmd"
$CliCmdLines = @(
    "@echo off",
    "setlocal",
    "cd /d `"%~dp0`"",
    "",
    "rem CLI helper flags for burpsuitepro",
    "if /i `"%~1`"==`"--keygen`" goto keygen",
    "if /i `"%~1`"==`"-k`" goto keygen",
    "if /i `"%~1`"==`"--trust-ca`" goto trust_ca",
    "if /i `"%~1`"==`"-t`" goto trust_ca",
    "if /i `"%~1`"==`"--version`" goto version",
    "if /i `"%~1`"==`"-v`" goto version",
    "if /i `"%~1`"==`"--path`" goto path",
    "if /i `"%~1`"==`"-p`" goto path",
    "if /i `"%~1`"==`"--help`" goto help",
    "if /i `"%~1`"==`"-h`" goto help",
    "goto launch",
    "",
    ":keygen",
    "if exist `"%~dp0Burp.bat`" (",
    "    call `"%~dp0Burp.bat`" --keygen",
    "    endlocal",
    "    exit /b %ERRORLEVEL%",
    ")",
    "if exist `"$($validJava.Path)`" (",
    "    start `"`" `"$($validJava.Path)`" -jar `"%~dp0loader.jar`"",
    ") else if exist `"%JAVA_HOME%\bin\java.exe`" (",
    "    start `"`" `"%JAVA_HOME%\bin\java.exe`" -jar `"%~dp0loader.jar`"",
    ") else (",
    "    start `"`" java -jar `"%~dp0loader.jar`"",
    ")",
    "endlocal",
    "exit /b 0",
    "",
    ":trust_ca",
    "if exist `"%~dp0Burp.bat`" (",
    "    call `"%~dp0Burp.bat`" --trust-ca",
    "    endlocal",
    "    exit /b %ERRORLEVEL%",
    ")",
    "if exist `"%~dp0trust-ca.ps1`" (",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0trust-ca.ps1`"",
    ")",
    "endlocal",
    "exit /b %ERRORLEVEL%",
    "",
    ":version",
    "echo Burp Suite Professional v$BURP_VERSION ($JarName)",
    "endlocal",
    "exit /b 0",
    "",
    ":path",
    "echo %~dp0",
    "endlocal",
    "exit /b 0",
    "",
    ":help",
    "echo Burp Suite Professional",
    "echo.",
    "echo Usage:",
    "echo   burpsuitepro [options] [burp-arguments]",
    "echo.",
    "echo Options:",
    "echo   -k, --keygen    Launch the key loader GUI (loader.jar)",
    "echo   -t, --trust-ca  Import and trust Burp CA certificate in Windows ^& browsers",
    "echo   -v, --version   Print current version and JAR name",
    "echo   -p, --path      Print installation directory path",
    "echo   -h, --help      Show quick usage help",
    "echo.",
    "echo All other arguments are passed directly to Burp Suite Pro.",
    "endlocal",
    "exit /b 0",
    "",
    ":launch",
    "if exist `"%~dp0Burp.bat`" (",
    "    call `"%~dp0Burp.bat`" %*",
    "    endlocal",
    "    exit /b %ERRORLEVEL%",
    ")",
    "",
    "rem Standalone fallback if Burp.bat is not found",
    "if exist `"$($validJava.Path)`" (",
    "    set `"JAVA_BIN=$($validJava.Path)`"",
    ") else if exist `"%JAVA_HOME%\bin\java.exe`" (",
    "    set `"JAVA_BIN=%JAVA_HOME%\bin\java.exe`"",
    ") else (",
    "    set `"JAVA_BIN=java.exe`"",
    ")",
    "",
    "rem Dynamic Memory Sizing: BURP_MAX_RAM, BURP_RAM, BURP_MEMORY or default to 50% RAM",
    "set `"MEM_OPTS=-XX:MaxRAMPercentage=50`"",
    "set `"BURP_MEM_VAL=`"",
    "if defined BURP_MAX_RAM set `"BURP_MEM_VAL=%BURP_MAX_RAM%`"",
    "if not defined BURP_MEM_VAL if defined BURP_RAM set `"BURP_MEM_VAL=%BURP_RAM%`"",
    "if not defined BURP_MEM_VAL if defined BURP_MEMORY set `"BURP_MEM_VAL=%BURP_MEMORY%`"",
    "if defined BURP_MEM_VAL (",
    "    echo %BURP_MEM_VAL% | findstr /i `"^-Xmx`" >nul",
    "    if errorlevel 1 (",
    "        set `"MEM_OPTS=-Xmx%BURP_MEM_VAL%`"",
    "    ) else (",
    "        set `"MEM_OPTS=%BURP_MEM_VAL%`"",
    "    )",
    ")",
    "",
    "rem Advanced JVM Garbage Collector: Generational ZGC check with G1GC fallback",
    "set `"GC_OPTS=-XX:+UseG1GC`"",
    "`"%JAVA_BIN%`" -XX:+UseZGC -XX:+ZGenerational -version >nul 2>&1",
    "if %ERRORLEVEL% equ 0 (",
    "    set `"GC_OPTS=-XX:+UseZGC -XX:+ZGenerational`"",
    ")",
    "",
    "rem Port 8080 Conflict Guard",
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { exit 10 }`" >nul 2>&1",
    "if %ERRORLEVEL% equ 10 (",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Write-Host '[!] Warning: Port 8080 is already occupied by another process. Burp proxy may encounter a bind collision.' -ForegroundColor Yellow`"",
    "    start `"`" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Warning: Port 8080 is already occupied by another process. Burp proxy may encounter a bind collision.', 'Burp Suite Port Warning', 0, 48)`"",
    ")",
    "",
    "rem HiDPI & Antialiasing Flags",
    "set `"UI_OPTS=-Dsun.java2d.uiScale=auto -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true`"",
    "",
    "rem Module Access Options",
    "set `"MODULE_OPTS=--add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED`"",
    "",
    "rem Execute Burp Suite Professional and trap exit code",
    "`"%JAVA_BIN%`" %GC_OPTS% %MEM_OPTS% %UI_OPTS% %MODULE_OPTS% -javaagent:`"%~dp0loader.jar`" -jar `"%~dp0$JarName`" %*",
    "set `"BURP_EXIT_CODE=%ERRORLEVEL%`"",
    "if %BURP_EXIT_CODE% neq 0 (",
    "    echo [!] Burp Suite Pro exited with error code %BURP_EXIT_CODE%.",
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Burp Suite Professional exited with error code ' + `$env:BURP_EXIT_CODE + '. Please check Java runtime and configuration.', 'Burp Suite Error', 0, 16)`"",
    ")",
    "endlocal",
    "exit /b %BURP_EXIT_CODE%",
    ""
)
$CliCmdContent = $CliCmdLines -join "`r`n"
[System.IO.File]::WriteAllText($CliCmdPath, $CliCmdContent, [System.Text.Encoding]::ASCII)
Write-Host "      [OK] Generated $CliCmdPath" -ForegroundColor Green

$currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($currentUserPath -notlike "*$InstallDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$InstallDir", "User")
    Write-Host "      [OK] Added $InstallDir to User PATH (run 'burpsuitepro' in any terminal)." -ForegroundColor Green
}

# 7E. Register Windows File Associations (.burp and .burpstate) in HKCU:\Software\Classes
Write-Host "      Registering Windows file associations (.burp and .burpstate)..." -ForegroundColor DarkCyan
try {
    $progId = "BurpSuite.Project"
    $fileDesc = "Burp Suite Professional Project"
    $openCmd = "`"$BatPath`" `"%1`""

    # Register ProgID root
    $progIdKey = "HKCU:\Software\Classes\$progId"
    if (-not (Test-Path $progIdKey)) {
        New-Item -Path $progIdKey -Force | Out-Null
    }
    Set-Item -Path $progIdKey -Value $fileDesc -Force
    Set-ItemProperty -Path $progIdKey -Name "FriendlyTypeName" -Value $fileDesc -Force

    # DefaultIcon: $TargetIcon,0
    $iconKey = Join-Path $progIdKey "DefaultIcon"
    if (-not (Test-Path $iconKey)) {
        New-Item -Path $iconKey -Force | Out-Null
    }
    Set-Item -Path $iconKey -Value "$TargetIcon,0" -Force

    # Shell open verb: launch via Burp.bat passing "%1"
    $shellOpenKey = Join-Path $progIdKey "shell\open"
    if (-not (Test-Path $shellOpenKey)) {
        New-Item -Path $shellOpenKey -Force | Out-Null
    }
    Set-ItemProperty -Path $shellOpenKey -Name "MUIVerb" -Value "Open with Burp Suite Professional" -Force
    if (Test-Path $TargetIcon) {
        Set-ItemProperty -Path $shellOpenKey -Name "Icon" -Value "$TargetIcon,0" -Force
    }

    $shellOpenCmdKey = Join-Path $shellOpenKey "command"
    if (-not (Test-Path $shellOpenCmdKey)) {
        New-Item -Path $shellOpenCmdKey -Force | Out-Null
    }
    Set-Item -Path $shellOpenCmdKey -Value $openCmd -Force

    # Custom context menu verb "Open with Burp Suite Professional"
    $customVerbCmdKey = Join-Path $progIdKey "shell\OpenWithBurp\command"
    if (-not (Test-Path $customVerbCmdKey)) {
        New-Item -Path $customVerbCmdKey -Force | Out-Null
    }
    Set-Item -Path (Split-Path -Parent $customVerbCmdKey) -Value "Open with Burp Suite Professional" -Force
    Set-ItemProperty -Path (Split-Path -Parent $customVerbCmdKey) -Name "Icon" -Value "$TargetIcon,0" -Force
    Set-Item -Path $customVerbCmdKey -Value $openCmd -Force

    # Associate file extensions: .burp and .burpstate
    $extensions = @(".burp", ".burpstate")
    foreach ($ext in $extensions) {
        $extKey = "HKCU:\Software\Classes\$ext"
        if (-not (Test-Path $extKey)) {
            New-Item -Path $extKey -Force | Out-Null
        }
        Set-Item -Path $extKey -Value $progId -Force

        $owpKey = Join-Path $extKey "OpenWithProgids"
        if (-not (Test-Path $owpKey)) {
            New-Item -Path $owpKey -Force | Out-Null
        }
        Set-ItemProperty -Path $owpKey -Name $progId -Value ([byte[]]@()) -Force
    }

    Write-Host "      [OK] Registered file associations (.burp, .burpstate) -> $progId" -ForegroundColor Green
} catch {
    Write-Warning "Could not register file associations: $($_.Exception.Message)"
}

# 7F. Windows Desktop and Start Menu Shortcuts with official .ico & dedicated Keygen shortcut
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

    # Main Burp Suite Launcher target
    # Uses wscript.exe targeting Burp-Suite-Pro.vbs to ensure completely silent GUI launch
    # while running Burp.bat with dynamic ZGC, memory sizing, port 8080 guard, and crash handling
    $wscriptExe = Join-Path $env:SystemRoot "System32\wscript.exe"
    $burpShortcutTarget = if (Test-Path $wscriptExe) { $wscriptExe } else { "wscript.exe" }
    $burpShortcutArgs = "`"$VbsPath`""

    # Dedicated Keygen Shortcut target
    $keygenTarget = if ($javawPath) { $javawPath }
                    elseif ($validJava -and (Test-Path $validJava.Path)) { $validJava.Path }
                    else { "java.exe" }
    $keygenArgs = "-jar `"$TargetLoader`""
    $keygenDesc = "Burp Suite Professional - Keygen and Loader Utility"

    function Create-AppShortcut {
        param (
            [string]$Directory,
            [string]$Name,
            [string]$Description,
            [string]$CustomTarget = $null,
            [string]$CustomArgs = $null,
            [string]$CustomIcon = $null
        )
        if (-not (Test-Path $Directory)) { return }
        $lnkPath = Join-Path $Directory "$Name.lnk"
        $sc = $WshShell.CreateShortcut($lnkPath)
        $sc.TargetPath = if ($CustomTarget) { $CustomTarget } else { $burpShortcutTarget }
        $sc.Arguments = if ($null -ne $CustomArgs) { $CustomArgs } else { $burpShortcutArgs }
        $sc.WorkingDirectory = $InstallDir
        $sc.Description = $Description
        $sc.WindowStyle = 1
        $iconToUse = if ($CustomIcon) { $CustomIcon } else { $TargetIcon }
        if (Test-Path $iconToUse) {
            $sc.IconLocation = "$iconToUse,0"
        }
        $sc.Save()
        Write-Host "      [OK] Shortcut ready: $lnkPath" -ForegroundColor Green
    }

    $DesktopFolder = [Environment]::GetFolderPath("Desktop")
    $ProgramsFolder = [Environment]::GetFolderPath("Programs")
    $CommonPrograms = [Environment]::GetFolderPath("CommonPrograms")

    # Main Application Shortcuts
    Create-AppShortcut -Directory $DesktopFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
    Create-AppShortcut -Directory $ProgramsFolder -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"

    if (Test-Path $CommonPrograms) {
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Professional" -Description "Burp Suite Professional - Web Application Security Testing"
        Create-AppShortcut -Directory $CommonPrograms -Name "Burp Suite Pro" -Description "Burp Suite Professional - Web Application Security Testing"
    }

    # Refresh Windows Shell & Icon Cache so Search and File Associations update immediately
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
Write-Host "Active JAR:  $JarName"
Write-Host "Jython 2.7:  $TargetJython"
Write-Host "JRuby 9.4:   $TargetJruby"
Write-Host "Shortcut:    Desktop & Start Menu ('Burp Suite Professional')"
Write-Host "File Assoc:  .burp & .burpstate (BurpSuite.Project)"
Write-Host "CLI Command: burpsuitepro (supports --keygen, --trust-ca, --version, --path, --help)"
Write-Host "===============================================================" -ForegroundColor Green
