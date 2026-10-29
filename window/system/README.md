# WinGet (Windows Package Manager) — Installer & Maintenance TUI

![Windows](https://img.shields.io/badge/Windows-10%20(1809+)%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![WinGet](https://img.shields.io/badge/Package-WinGet%20CLI-0078D4?style=for-the-badge&logo=microsoft&logoColor=white)
![Interface](https://img.shields.io/badge/UI-Interactive%20TUI-brightgreen?style=for-the-badge)

Automated, production-grade PowerShell installer and interactive **Text-based User Interface (TUI)** utility for **Microsoft WinGet (Windows Package Manager)** on Windows 10 and Windows 11.

It implements the official **WinUtil / `Microsoft.WinGet.Client`** engine: automatically bootstrapping the NuGet package provider, installing the official Microsoft client module from PowerShell Gallery, deploying/repairing WinGet via `Repair-WinGetPackageManager`, configuring execution aliases and PATH, and performing comprehensive health maintenance.

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
       • Full clean installation or update to latest official release
       • Official Microsoft.WinGet.Client engine (WinUtil logic)
       • Registers User PATH and synchronizes official sources

    [2] Repair WinGet Environment
       • Resets AppX package state and re-registers AppXManifest
       • Runs Repair-WinGetPackageManager for deep system repair
       • Restores broken WindowsApps PATH, aliases & purges SQLite cache

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

### 2. Official `Microsoft.WinGet.Client` Engine (WinUtil Logic)
- **NuGet Provider Bootstrap**: Automatically detects and installs the NuGet package provider.
- **PowerShell Gallery Trust**: Ensures `PSGallery` is trusted to eliminate interactive confirmation prompts.
- **Scope Awareness**: Installs `Microsoft.WinGet.Client` with `AllUsers` scope when running with Administrator privileges, or `CurrentUser` scope on standard accounts.
- **Deep Package Deployment**: Calls `Repair-WinGetPackageManager` (`-AllUsers -Latest -Force` when elevated, or user scope) to automatically acquire signed official dependencies and register the App Installer package.

### 3. Comprehensive Repair Suite (`Repair` Mode)
If WinGet stops responding, crashes, or cannot locate packages, the repair mode runs:
1. **AppX Package Reset**: Executes `Reset-AppxPackage` on modern Windows 10/11 to reset app state without data loss.
2. **Manifest Re-registration**: Re-registers `AppXManifest.xml` from WindowsApps.
3. **Deep Repair**: Runs `Repair-WinGetPackageManager` to restore any damaged or missing core binaries.
4. **App Execution Aliases & PATH**: Restores `%LOCALAPPDATA%\Microsoft\WindowsApps` in the persistent User `PATH`.
5. **Cache Cleaner**: Clears locked or corrupted local SQLite source databases in `AppData\Local\Packages\Microsoft.DesktopAppInstaller_*\LocalState`.
6. **Source Reset**: Resets catalog sources to factory default (`winget source reset --force`) and triggers a fresh sync.

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

## 🍫 Chocolatey Package Manager Installer & Maintenance

Alongside WinGet, this directory provides a dedicated, automated, keyboard-driven installer for **Chocolatey (`choco`)**:

### Quick Start
```cmd
choco_install.bat
```
*(Or via PowerShell: `.\choco_install.ps1`)*

### Remote One-Liner (No Clone Required)
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/aadish0day/post_install/main/window/system/choco_install.ps1" | iex
```

### CLI / Headless Automation
```powershell
# Unattended Installation
.\choco_install.ps1 -Action Install

# Force reinstall
.\choco_install.ps1 -Action Install -Force

# Upgrade all installed packages
.\choco_install.ps1 -Action Upgrade

# Repair PATH and environment
.\choco_install.ps1 -Action Repair
```

---

## 📂 File Layout

```text
window/system/
├── README.md              # Documentation and guide
├── winget_install.ps1     # WinGet TUI installer and repair tool
├── winget_install.bat     # One-click WinGet batch launcher
├── choco_install.ps1      # Chocolatey TUI installer, updater & repair tool
└── choco_install.bat      # One-click Chocolatey batch launcher
```
