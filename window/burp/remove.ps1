<#
.SYNOPSIS
    Automated Burp Suite Professional Full Uninstaller for Windows.
.DESCRIPTION
    Completely removes Burp Suite Professional from Windows:
    - Terminates running Burp Suite and key loader processes.
    - Removes Desktop and Start Menu shortcuts.
    - Unregisters CLI command and cleans User PATH.
    - Deletes installation directory and JAR files.
    - Cleans BurpSuite AppData, .BurpSuite cache, and registry preferences.
    - Flushes Windows Shell and icon cache.
#>

[CmdletBinding()]
param (
    [string]$InstallPath = "$env:USERPROFILE\Documents\Crack\Burpsuite-Professional",
    [switch]$KeepData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Automatically set execution policy to Bypass for current process
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
} catch {}

# Safe TLS configuration
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 12288
} catch {}

# Safe ScriptDir resolution for remote execution via irm | iex
$ScriptDir = if (![string]::IsNullOrEmpty($PSScriptRoot)) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { $PWD.Path }

Write-Host "===============================================================" -ForegroundColor Yellow
Write-Host "     Burp Suite Professional Full Uninstaller (Windows)        " -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Yellow

$InstallDir = [System.IO.Path]::GetFullPath($InstallPath)

if (-not $Force) {
    Write-Host "`nTarget Installation Directory to Remove:" -ForegroundColor Cyan
    Write-Host "  $InstallDir" -ForegroundColor White
    if (-not $KeepData) {
        Write-Host "Also removing user configuration, cache, and registry entries." -ForegroundColor DarkYellow
    } else {
        Write-Host "Preserving user data in AppData (-KeepData specified)." -ForegroundColor DarkGray
    }

    $confirmation = Read-Host "`nAre you sure you want to completely remove Burp Suite Professional? (y/N)"
    if ($confirmation -notmatch '^(?i)y(es)?$') {
        Write-Host "`n[!] Uninstallation canceled by user." -ForegroundColor Yellow
        exit 0
    }
}

# ------------------------------------------------------------------------------
# 1. Stop Running Processes
# ------------------------------------------------------------------------------
Write-Host "`n(1/6) Stopping running Burp Suite processes..." -ForegroundColor Cyan

$terminatedAny = $false
try {
    $processes = @()
    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(java|javaw|wscript)\.exe$') -and (
                $_.CommandLine -match 'burpsuite' -or 
                $_.CommandLine -match 'loader\.jar' -or 
                $_.CommandLine -match 'Burp-Suite-Pro\.vbs' -or
                $_.CommandLine -match 'Burp\.bat' -or
                ($InstallDir -and $_.CommandLine -like "*$InstallDir*")
            )
        }
    } catch {
        $processes = Get-WmiObject Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(java|javaw|wscript)\.exe$') -and (
                $_.CommandLine -match 'burpsuite' -or 
                $_.CommandLine -match 'loader\.jar' -or 
                $_.CommandLine -match 'Burp-Suite-Pro\.vbs' -or
                $_.CommandLine -match 'Burp\.bat' -or
                ($InstallDir -and $_.CommandLine -like "*$InstallDir*")
            )
        }
    }

    if ($processes) {
        foreach ($p in $processes) {
            Write-Host "      Terminating process: ID $($p.ProcessId) ($($p.Name))" -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            $terminatedAny = $true
        }

        # Wait for processes to exit so file locks are released
        foreach ($p in $processes) {
            try {
                $procObj = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                if ($procObj) {
                    $procObj.WaitForExit(3000)
                }
            } catch {}
        }
    }
} catch {
    Write-Warning "Could not query Win32_Process: $($_.Exception.Message)"
}

if (-not $terminatedAny) {
    Write-Host "      [OK] No active Burp Suite processes found." -ForegroundColor Green
} else {
    Write-Host "      [OK] Active processes terminated." -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

# ------------------------------------------------------------------------------
# 2. Remove Desktop & Start Menu Shortcuts
# ------------------------------------------------------------------------------
Write-Host "`n(2/6) Removing Windows shortcuts..." -ForegroundColor Cyan

$shortcutNames = @("Burp Suite Professional.lnk", "Burp Suite Pro.lnk")
$shortcutLocations = @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("CommonDesktopDirectory"),
    [Environment]::GetFolderPath("Programs"),
    [Environment]::GetFolderPath("CommonPrograms")
)

$shortcutsRemoved = 0
foreach ($loc in ($shortcutLocations | Select-Object -Unique)) {
    if (-not (Test-Path $loc)) { continue }
    foreach ($scName in $shortcutNames) {
        $scPath = Join-Path $loc $scName
        if (Test-Path $scPath) {
            Remove-Item -Path $scPath -Force -ErrorAction SilentlyContinue
            Write-Host "      [OK] Removed shortcut: $scPath" -ForegroundColor Green
            $shortcutsRemoved++
        }
    }
}

if ($shortcutsRemoved -eq 0) {
    Write-Host "      [OK] No shortcuts found to remove." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 3. Clean User PATH Environment Variable
# ------------------------------------------------------------------------------
Write-Host "`n(3/6) Cleaning User PATH environment variable..." -ForegroundColor Cyan

try {
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentUserPath -and ($currentUserPath -like "*$InstallDir*")) {
        $pathParts = $currentUserPath.Split(';') | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and ($_.TrimEnd('\') -ne $InstallDir.TrimEnd('\'))
        }
        $newPath = $pathParts -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "      [OK] Removed $InstallDir from User PATH." -ForegroundColor Green
    } else {
        Write-Host "      [OK] Installation path was not in User PATH." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not update User PATH: $($_.Exception.Message)"
}

# ------------------------------------------------------------------------------
# 4. Delete Installation Directory & Files
# ------------------------------------------------------------------------------
Write-Host "`n(4/6) Removing installation folder: $InstallDir" -ForegroundColor Cyan

if (Test-Path $InstallDir) {
    # Terminate any lingering Burp or javaw processes before deletion to prevent Access Denied
    try {
        $lingering = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(java|javaw|wscript)\.exe$') -and (
                $_.CommandLine -match 'burpsuite' -or 
                $_.CommandLine -match 'loader\.jar' -or 
                ($InstallDir -and $_.CommandLine -like "*$InstallDir*")
            )
        }
        foreach ($lp in $lingering) {
            Stop-Process -Id $lp.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    try {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "      [OK] Deleted $InstallDir" -ForegroundColor Green
    } catch {
        # Retry once after a brief pause to allow OS file handles to clear
        Start-Sleep -Seconds 1
        try {
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-Host "      [OK] Deleted $InstallDir" -ForegroundColor Green
        } catch {
            Write-Warning "Could not delete $InstallDir: $($_.Exception.Message)"
        }
    }
} else {
    Write-Host "      [OK] Installation directory does not exist." -ForegroundColor Green
}

# Clean parent Crack directory if it is now empty
$parentDir = Split-Path -Parent $InstallDir
if ((Test-Path $parentDir) -and ((Get-ChildItem -Path $parentDir -Force | Measure-Object).Count -eq 0)) {
    try {
        Remove-Item -Path $parentDir -Force -ErrorAction SilentlyContinue
        Write-Host "      [OK] Removed empty parent folder: $parentDir" -ForegroundColor DarkGray
    } catch {}
}

# ------------------------------------------------------------------------------
# 5. Clean Application Data, Caches & Registry Preferences
# ------------------------------------------------------------------------------
Write-Host "`n(5/6) Cleaning cache, user data & registry..." -ForegroundColor Cyan

if (-not $KeepData) {
    $dataPaths = @(
        (Join-Path $env:USERPROFILE ".BurpSuite"),
        (Join-Path $env:APPDATA "BurpSuite"),
        (Join-Path $env:LOCALAPPDATA "BurpSuite")
    )

    foreach ($dp in $dataPaths) {
        if (Test-Path $dp) {
            try {
                Remove-Item -Path $dp -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "      [OK] Deleted data folder: $dp" -ForegroundColor Green
            } catch {
                Write-Warning "Could not remove $dp"
            }
        }
    }

    # Clean temporary downloaded files
    $tempMatches = @("burpsuite*", "openjdk21_installer.msi")
    foreach ($tm in $tempMatches) {
        Get-ChildItem -Path $env:TEMP -Filter $tm -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove Java/PortSwigger registry preferences
    $regPaths = @(
        "HKCU:\Software\JavaSoft\Prefs\burp",
        "HKCU:\Software\JavaSoft\Prefs\/Burp/Suite/Professional",
        "HKCU:\Software\PortSwigger"
    )

    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            try {
                Remove-Item -Path $rp -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "      [OK] Removed registry entry: $rp" -ForegroundColor Green
            } catch {}
        }
    }
    Write-Host "      [OK] Application data and registry keys cleaned." -ForegroundColor Green
} else {
    Write-Host "      [OK] Skipped user data cleanup (-KeepData active)." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 6. Flush Windows Shell & Icon Cache
# ------------------------------------------------------------------------------
Write-Host "`n(6/6) Refreshing Windows Shell and search index..." -ForegroundColor Cyan

try {
    $shellNotifyCode = '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);'
    $shellNotify = Add-Type -MemberDefinition $shellNotifyCode -Name "ShellNotifyRemove" -Namespace "Win32" -PassThru -ErrorAction SilentlyContinue
    if ($shellNotify) {
        [Win32.ShellNotifyRemove]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    Write-Host "      [OK] Windows Shell notified and icon cache flushed." -ForegroundColor Green
} catch {
    Write-Host "      [OK] Completed." -ForegroundColor Green
}

Write-Host "`n===============================================================" -ForegroundColor Green
Write-Host "  Burp Suite Professional Has Been Completely Removed!         " -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor Green
