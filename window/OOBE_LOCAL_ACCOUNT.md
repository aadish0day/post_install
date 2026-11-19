# Windows 11 OOBE Local Account & Network Bypass Guide

![Windows 11](https://img.shields.io/badge/Windows-11-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Setup](https://img.shields.io/badge/Setup-OOBE%20Bypass-success?style=for-the-badge)
![Account](https://img.shields.io/badge/Account-Local%20Only-orange?style=for-the-badge)

A comprehensive reference for bypassing mandatory Microsoft Account (MSA) sign-in and network connection requirements during Windows 11 Out-Of-Box Experience (OOBE) setup to create an offline/local administrator account.

---

## ⌨️ Accessing Command Prompt in OOBE

At any point during the initial Windows 11 setup screens (Region, Keyboard, or Network connection screen):

* Press **`Shift + F10`**  
  *(On many modern laptops, press **`Shift + Fn + F10`**)*

This opens an elevated Command Prompt (`cmd.exe`) running under `NT AUTHORITY\SYSTEM`.

---

## 🛠️ Command Prompt Local Account Methods

### Method 1: Direct Local Account Prompt (Fastest)

On the network or sign-in screen, open Command Prompt (`Shift + F10`) and execute:

```cmd
start ms-cxh:localonly
```

*Alternative for specific builds:*
```cmd
start ms-accounts:connectonly
```

* **What it does**: Directs the Cloud Experience Host (CXH) flow to trigger the local user creation dialog directly, bypassing cloud sign-in prompts.
* **Community Notes (r/sysadmin)**:
  * Users report success using this method even while the machine is connected to the internet.
  * Some users report that on certain hardware or preview builds, the window may pop behind the main OOBE screen. If this occurs, press `Ctrl + Alt + Del` → **Task Manager** → **Run new task** → `powershell` or switch active windows.

---

### Method 2: Bypass Network Requirement (`BYPASSNRO` - Recommended)

The canonical and widely supported Microsoft method to unlock offline installation.

1. On the "Let's connect you to a network" screen, press **`Shift + F10`**.
2. Run the bypass command:
   ```cmd
   OOBE\BYPASSNRO
   ```
3. Windows will automatically reboot and restart the setup process.
4. When you reach the network screen again, click the newly unlocked option:
   > **"I don't have internet"** &rarr; **"Continue with limited setup"**
5. Enter your desired local username and password.

> [!TIP]
> **If already connected to the internet**:
> Disconnect Ethernet, toggle airplane mode/Wi-Fi switch, or release the network lease in Command Prompt before or during this step:
> ```cmd
> ipconfig /release
> ```

---

### Method 3: Manual Local User Creation via `net user` (Workaround for New Builds)

If Microsoft patches or restricts protocol handlers on newer builds (e.g., Windows 11 24H2 / Insider updates), you can manually provision the user account and restart the shell:

1. Open Command Prompt (`Shift + F10`).
2. Add your local user account and grant administrator privileges:
   ```cmd
   net user <username> <password> /add
   net localgroup administrators <username> /add
   ```
   *(Replace `<username>` and `<password>` with your chosen credentials; leave password blank if none is desired).*
3. Restart or re-trigger OOBE:
   ```cmd
   msoobe && shutdown -r -t 0
   ```
   *(Or navigate to directory: `cd oobe` then execute `msoobe`).*

---

## 🌐 Community Consensus & Reference Sources

* **Microsoft Answers**: The consensus standard remains `OOBE\BYPASSNRO` as the cleanest, native offline unlock path across standard installation media.
* **Reddit (`r/sysadmin`)**: `start ms-cxh:localonly` is popular for quick enterprise imaging without rebooting, with `Ctrl + Alt + Del` &rarr; Task Manager as a reliable fallback when UI windows misplace focus.
* **Tom's Hardware / Rufus**: For pre-installation automation, creating installation media with tools like **Rufus** can automatically inject answers to strip the TPM 2.0, Secure Boot, and Microsoft Account requirements before booting the USB installer.
