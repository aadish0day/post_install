# Burp Suite Professional — Windows Installer

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Java](https://img.shields.io/badge/Java-21%2B%20LTS-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Security](https://img.shields.io/badge/Tool-PortSwigger%20Burp%20Suite-FF6633?style=for-the-badge)

Automated, production-grade PowerShell installer for **Burp Suite Professional** on Windows 10 and Windows 11. Designed to match the reliability and automation of the Linux (`arch/apps/burp/install.sh`) orchestrator with native Windows desktop integration.

---

## ⚡ Quick Start

### Option 1: One-Click / CMD Launcher (No Policy Setup Needed)
Simply double-click `install.bat` or run in Command Prompt / PowerShell:

```cmd
.\install.bat
```

### Option 2: PowerShell Direct

- Open `PowerShell` as administrator and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

### Option 3: Direct Remote One-Liner
If you haven't cloned the repository, run directly from GitHub:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/aadish0day/post_install/main/window/burp/install.ps1" | iex
```

---

## 🎚️ Version Channel (Tested vs. Latest)

Double-clicking `install.bat` (or running `install.ps1` in a console) asks which channel to install:

```text
Burp Suite Professional - version channel
  1) Tested stable  v2026.10.1  (recommended)
  2) Latest         newest PortSwigger release (UNTESTED)
Select [1]:
```

Press <kbd>Enter</kbd> for the tested stable build. Choosing latest queries the PortSwigger release API, prints a yellow warning and falls back to the tested version if the API is unreachable. Invalid input re-prompts up to 3 times, then falls back to stable.

For unattended runs, pass a flag instead — no prompt is shown when `-Version`, `-Channel` or `$env:BURP_VERSION` is set, and non-interactive sessions default to tested stable:

```cmd
.\install.bat                              # asks: tested 2026.10.1 or latest (untested)
.\install.bat -Channel latest              # newest release, no prompt (UNTESTED)
.\install.bat -Channel stable              # tested 2026.10.1, no prompt
.\install.bat -Version 2026.10.1           # pin an exact version
```

---

## ✨ Features & Capabilities

- **Intelligent Java 21+ Engine**:
  - Automatically inspects session `$env:Path`, `JAVA_HOME` (User & Machine), Windows Registry (`HKLM:\SOFTWARE\Microsoft\JDK`, `HKLM:\SOFTWARE\JavaSoft`), and standard program directories.
  - If Java 21+ already exists, **skips downloading entirely**.
  - If missing or outdated, automatically downloads and silently installs the official **Microsoft OpenJDK 21 MSI** (with Adoptium and `winget` fallbacks).
- **Dynamic Latest Release Lookup**:
  - Queries PortSwigger's live release API (`https://portswigger.net/burp/releases/data?pageSize=10`) to automatically download the latest official Pro JAR.
- **High-Speed `curl.exe` Acceleration & Auto-Resume**:
  - Automatically leverages native Windows `curl.exe` (`C:\Windows\System32\curl.exe`) with HTTP/2 and auto-resume (`-C -`), delivering maximum download speeds for the ~750MB JAR. Falls back smoothly to an optimized 1MB buffered .NET stream reader if needed.
- **Failover Mirror Redundancy**:
  - Primary download from Codeberg with automatic failover to GitHub mirrors for `loader.jar`.
- **Silent Launchers (Zero Black Console Windows)**:
  - Generates `Burp.bat` using location-independent `%~dp0` variables, G1 garbage collector, and Java 21 `--add-opens` flags.
  - Generates `Burp-Suite-Pro.vbs` to execute Burp silently in the background without persistent console popups.
- **Native Windows Search & Start Menu Integration**:
  - Installs shortcuts to both the **Desktop** and **Start Menu**.
  - Direct `javaw.exe` linking ensures pressing the <kbd>Windows</kbd> key and searching `burp` or `burp suite pro` immediately surfaces the application under **Best match (App)**.
  - Automatically sets the official multi-resolution [burp_suite_pro.ico](burp_suite_pro.ico) icon and flushes the Windows icon cache (`SHChangeNotify`).
- **Terminal CLI Command**:
  - Appends the installation path to the User `PATH` environment variable, enabling direct CLI launch by typing `burpsuitepro` in any command prompt.

---

## 📂 Directory Layout

```text
window/burp/
├── README.md              # Documentation and usage guide
├── install.ps1            # Main automated PowerShell installation script
├── install.bat            # One-click batch launcher for install.ps1
├── remove.ps1             # Full uninstaller script
├── remove.bat             # One-click batch launcher for remove.ps1
├── burp_suite_pro.ico     # Multi-resolution official Burp Suite Pro icon (16px to 256px)
└── .config.ini            # Key loader configuration template
```

---

## 🛠️ What `install.ps1` Does (Step-by-Step)

| Step | Action | Description |
| :---: | :--- | :--- |
| **(1/8)** | **Directory Setup** | Creates `%USERPROFILE%\Documents\Crack\Burpsuite-Professional`. |
| **(2/8)** | **Java Detection & Setup** | Verifies Java 21+. If missing, silently installs OpenJDK 21 via direct MSI. |
| **(3/8)** | **Version Resolution** | Prompts for tested stable or latest (non-interactive: stable), or honors `-Version` / `-Channel` / `BURP_VERSION`. |
| **(4/8)** | **Loader Fetch** | Downloads `loader.jar` with integrity verification (> 10 KB). |
| **(5/8)** | **JAR Download** | Cleans old releases and downloads the latest ~700 MB JAR with a live visual progress bar and checksum validation. |
| **(6/8)** | **Asset Deployment** | Copies `.config.ini` and `burp_suite_pro.ico` into the target directory. |
| **(7/8)** | **Shortcuts & CLI** | Creates Desktop + Start Menu shortcuts and registers `burpsuitepro` in User `PATH`. |
| **(8/8)** | **Launch** | Launches the Key Loader and opens Burp Suite Professional. |

---

## 🖥️ Target Installation Path

After installation, your files reside in:

```text
C:\Users\<Username>\Documents\Crack\Burpsuite-Professional\
├── .config.ini
├── burp_suite_pro.ico
├── loader.jar
├── burpsuite_pro_v<version>.jar
├── Burp.bat
├── Burp-Suite-Pro.vbs
└── burpsuitepro.cmd
```

---

## ❓ Troubleshooting

### Execution Policy Error
If PowerShell blocks script execution (`running scripts is disabled on this system`):
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

### Manual Java 21 Download
If you prefer to pre-install Java manually before running the script:
- [Download Microsoft OpenJDK 21 MSI](https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi)

### Re-running Without Launching
To reinstall or update the JAR without launching the application at the end:
```powershell
.\install.ps1 -SkipLaunch
```

### Specifying an Exact Version
By default, the installer uses the tested stable release (`2026.10.1`). To install or pin a specific version:
```powershell
.\install.ps1 -Version "2026.10.1"
```

To opt into the newest PortSwigger release instead (see **Version Channel** above):
```powershell
.\install.ps1 -Channel latest
```

---

## 🗑️ Complete Uninstallation

To completely remove Burp Suite Professional, its launchers, shortcuts, CLI command, and user preferences:

### Method 1: One-Click Batch
```cmd
.\remove.bat
```

### Method 2: PowerShell
```powershell
.\remove.ps1
```

To run silently without confirmation prompts:
```powershell
.\remove.ps1 -Force
```

To remove the software and shortcuts while keeping your saved projects and BApp extensions:
```powershell
.\remove.ps1 -KeepData
```
