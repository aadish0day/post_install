# WinGet (Windows Package Manager) — Installer & Maintenance TUI

![Windows](https://img.shields.io/badge/Windows-10%20(1809+)%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![WinGet](https://img.shields.io/badge/Package-WinGet%20CLI-0078D4?style=for-the-badge&logo=microsoft&logoColor=white)
![Interface](https://img.shields.io/badge/UI-Interactive%20TUI-brightgreen?style=for-the-badge)

Automated, production-grade PowerShell installer and interactive **Text-based User Interface (TUI)** utility for **Microsoft WinGet (Windows Package Manager)** on Windows 10 and Windows 11.

It automates downloading official runtime dependencies, installing the latest package bundles directly from GitHub releases, configuring user and system environments, and performing automated repairs for broken WinGet environments.

---

## ⚡ Quick Start

### Option 1: One-Click TUI Batch Launcher
Double-click `winget_install.bat` or run in Command Prompt / Terminal:

```cmd
winget_install.bat
```

### Option 2: PowerShell Direct (Launches TUI Menu)

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\winget_install.ps1
```

### Option 3: Remote Direct One-Liner (No Clone Required)

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/aadish0day/post_install/main/window/system/winget_install.ps1" | iex
```

---

## 🎮 Interactive TUI Navigation

When launched without command-line parameters, `winget_install.ps1` presents an interactive keyboard-driven TUI:

```text
  ┌───────────────────────────────────────────────────────────────┐
  │           WinGet Package Manager - Setup & Maintenance        │
  └───────────────────────────────────────────────────────────────┘
   Use [↑ / ↓] to Navigate | [Enter] Select | [1/2/3] Quick Select | [Q] Quit

  ► [1] Install / Update WinGet
       • Full clean installation or update to the latest release
       • Auto-fetches VCLibs, UI.Xaml 2.8+ and latest AppInstaller
       • Registers User PATH and synchronizes official sources

    [2] Repair WinGet Environment
       • Resets AppX package state and re-registers AppXManifest
       • Restores broken WindowsApps PATH and App Execution Aliases
       • Cleans corrupted SQLite cache and resets repository sources

    [3] Exit
       • Cancel and return to terminal
```

| Key | Action |
| :--- | :--- |
| <kbd>↑</kbd> / <kbd>W</kbd> / <kbd>K</kbd> | Move cursor up |
| <kbd>↓</kbd> / <kbd>S</kbd> / <kbd>J</kbd> | Move cursor down |
| <kbd>1</kbd>, <kbd>2</kbd>, <kbd>3</kbd> | Instant shortcut selection |
| <kbd>Enter</kbd> / <kbd>Space</kbd> | Confirm selection |
| <kbd>Esc</kbd> / <kbd>Q</kbd> | Exit without changes |

---

## ✨ Features & Capabilities

### 1. Automated Architecture & OS Verification
- Supports **Windows 10 Build 17763 (v1809+)** through **Windows 11**.
- Dynamically detects and pairs dependencies for **`x64`**, **`arm64`**, and **`x86`** architectures.

### 2. Full Dependency Resolution
WinGet requires specific Microsoft app runtimes to operate. The installer automatically downloads and registers:
- **Microsoft.VCLibs.140.00.UWPDesktop** (via `aka.ms`).
- **Microsoft.UI.Xaml 2.8+** (official GitHub package release).
- Latest **`Microsoft.DesktopAppInstaller`** bundle (`.msixbundle`) and license XML from GitHub (`microsoft/winget-cli`).

### 3. Resilient High-Speed Downloads
- Uses native `curl.exe` with automatic retries and failover for maximum download speeds.
- Built-in fallback to `System.Net.WebClient` and `Invoke-WebRequest` with forced TLS 1.2 and TLS 1.3.

### 4. Comprehensive Repair Suite (`Repair` Mode)
If WinGet stops responding, crashes, or cannot locate packages, the repair mode runs:
1. **AppX Package Reset**: Executes `Reset-AppxPackage` on modern Windows 10/11 to reset app state without data loss.
2. **Manifest Re-registration**: Re-registers `AppXManifest.xml` from WindowsApps.
3. **App Execution Aliases & PATH**: Restores `%LOCALAPPDATA%\Microsoft\WindowsApps` in the persistent User `PATH`.
4. **Cache Cleaner**: Clears locked or corrupted local SQLite source databases in `AppData\Local\Packages\Microsoft.DesktopAppInstaller_*\LocalState`.
5. **Source Reset**: Resets catalog sources to factory default (`winget source reset --force`) and triggers a fresh sync.
6. **Self-Healing Reinstall**: If the package files are completely missing or broken, automatically fetches and reinstalls a fresh build.

---

## 🛠️ CLI / Headless Automation

For unattended scripts, sysprep, or CI/CD pipelines, specify the `-Action` parameter to bypass the TUI:

```powershell
# Unattended Installation / Upgrade
.\winget_install.ps1 -Action Install

# Force reinstallation even if already detected
.\winget_install.ps1 -Action Install -Force

# Provision system-wide for all users (requires Administrator privileges)
.\winget_install.ps1 -Action Install -ProvisionAllUsers

# Unattended Repair
.\winget_install.ps1 -Action Repair

# Skip post-operation source synchronization
.\winget_install.ps1 -Action Install -NoSourceUpdate
```

---

## 📂 File Layout

```text
window/system/
├── README.md              # Documentation and guide
├── winget_install.ps1     # Core PowerShell TUI installer and repair tool
└── winget_install.bat     # One-click batch launcher
```
