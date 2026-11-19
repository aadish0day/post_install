# Windows Automation Suite & Post-Install Tools

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Batch](https://img.shields.io/badge/Batch-Launchers-gray?style=for-the-badge)

A modular suite of automation tools, installers, and reference documentation for setting up Windows 10 and Windows 11 environments.

---

## 📂 Directory Structure

```text
window/
├── OOBE_LOCAL_ACCOUNT.md    # Windows 11 setup & local account bypass reference
│
├── system/
│   ├── winget_install.bat   # Batch launcher for WinGet installer/repair TUI
│   ├── winget_install.ps1   # PowerShell interactive WinGet client TUI
│   ├── choco_install.bat    # Batch launcher for Chocolatey installer
│   ├── choco_install.ps1    # PowerShell Chocolatey deployment script
│   └── README.md            # Detailed documentation for WinGet & package tools
│
└── burp/
    ├── install.bat          # Batch launcher for Burp Suite Pro installer
    ├── install.ps1          # PowerShell automated Burp Pro orchestrator
    ├── remove.bat           # Batch launcher for uninstaller
    ├── remove.ps1           # Complete uninstallation script
    ├── burp_suite_pro.ico   # High-resolution application icon
    └── README.md            # Documentation for Burp Suite Pro installer
```

---

## 🚀 Quick Highlights

### 1. Windows 11 OOBE Local Account & Network Bypass
* **Guide**: [OOBE_LOCAL_ACCOUNT.md](file:///home/aadish/Documents/Github/post_install/window/OOBE_LOCAL_ACCOUNT.md)
* Learn how to bypass mandatory Microsoft Account (MSA) sign-in and internet connectivity requirements during Windows 11 setup using `Shift + F10` shortcuts:
  * `start ms-cxh:localonly`
  * `OOBE\BYPASSNRO`
  * `net user <username> /add`

### 2. WinGet (Windows Package Manager) Installer & Repair Tool (TUI)
* **Location**: `window/system/`
* Interactive TUI utility implementing the official `Microsoft.WinGet.Client` engine for installing, repairing, and managing packages via WinGet.
* Run:
  ```cmd
  .\window\system\winget_install.bat
  ```

### 3. Burp Suite Professional Automation
* **Location**: `window/burp/`
* Production-grade PowerShell orchestrator with automatic PortSwigger release API querying, JDK 21 detection & auto-installation, `.ico` desktop shortcuts, and silent VBScript background launcher integration.
* Run:
  ```cmd
  .\window\burp\install.bat
  ```
