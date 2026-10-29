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

## ✨ Features & Capabilities

- **Intelligent Java 21+ Engine**:
  - Automatically inspects session `$env:Path`, `JAVA_HOME` (User & Machine), Windows Registry (`HKLM:\SOFTWARE\Microsoft\JDK`, `HKLM:\SOFTWARE\JavaSoft`), and standard program directories.
  - If Java 21+ already exists, **skips downloading entirely**.
  - If missing or outdated, automatically downloads and silently installs the official **Microsoft OpenJDK 21 MSI** (with Adoptium and `winget` fallbacks).
- **Dynamic Latest Release Lookup**:
  - Queries PortSwigger's live release API (`https://portswigger.net/burp/releases/data?pageSize=10`) to automatically download the latest official Pro JAR.
- **High-Speed Visual Progress**:
  - Built-in throttled stream reader displaying real-time download percentage, transferred size (MB), and transfer speed (MB/s) without throttling network throughput.
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
├── burp_suite_pro.ico     # Multi-resolution official Burp Suite Pro icon (16px to 256px)
└── .config.ini            # Key loader configuration template
```

---

## 🛠️ What `install.ps1` Does (Step-by-Step)

| Step | Action | Description |
| :---: | :--- | :--- |
| **(1/8)** | **Directory Setup** | Creates `%USERPROFILE%\Documents\Crack\Burpsuite-Professional`. |
| **(2/8)** | **Java Detection & Setup** | Verifies Java 21+. If missing, silently installs OpenJDK 21 via direct MSI. |
| **(3/8)** | **Version Resolution** | Queries PortSwigger API for the latest version tag. |
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
