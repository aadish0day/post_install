# Post-Installation Automation Suite

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Pure Bash](https://img.shields.io/badge/Pure_Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Kali](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kali-linux&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-000000?style=for-the-badge&logo=terminal&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)

Modular, production-grade post-installation orchestration suite built in **100% pure Bash**. Features an **`archinstall`-style interactive TUI**, hardware auto-detection, data-driven menu catalogs, sourceable configuration profiles, guaranteed zero-modification dry-runs, and modular recipes for **Arch Linux**, **Debian / Ubuntu**, **Fedora**, **Kali Linux**, and **Termux**.

**Zero external language runtimes required** — no Python, Node.js, or Ruby dependencies. Only pure Bash with optional `dialog` or `whiptail` for rich terminal dialogs, falling back cleanly to an interactive CLI menu when no TUI utility is present.

---

## Table of Contents

- [Features & Highlights](#features--highlights)
- [Quick Start](#quick-start)
  - [1. Interactive Guided TUI](#1-interactive-guided-tui)
  - [2. Non-Destructive Simulation (Dry-Run)](#2-non-destructive-simulation-dry-run)
  - [3. Headless / CLI Execution](#3-headless--cli-execution)
  - [4. Strict Abort Mode](#4-strict-abort-mode)
  - [5. Distro & Desktop Flags](#5-distro--desktop-flags)
  - [6. Windows (PowerShell)](#6-windows-powershell)
- [Repository Architecture](#repository-architecture)
- [The `--dry-run` Safety Guarantee](#the---dry-run-safety-guarantee)
- [Strict Execution Mode (`--strict`)](#strict-execution-mode---strict)
- [Configuration Profiles](#configuration-profiles)
- [Supported Distributions & Capabilities](#supported-distributions--capabilities)
- [Session Logging](#session-logging)
- [Verification & Testing](#verification--testing)
- [License](#license)

---

## Features & Highlights

- **Pure Bash TUI-First Engine**:
  - Implements an `archinstall`-style data-driven configuration menu (`lib/menu.sh`) using standard `dialog` or `whiptail`.
  - Full Vim keybinding navigation (`j`/`k` movement, `g`/`G` home/end, `h`/`l` select/cancel) via `lib/ui.sh`.
  - Dynamic status badges: `[✓]`, `[KDE]`, `[paru]`, `[85%]`, `[4 selected]`.
  - Built-in numbered CLI menu fallback when running in minimal headless environments without `dialog`/`whiptail`.
- **Guaranteed Dry-Run Simulation**:
  - Full simulation mode (`--dry-run` or `-d`) prints the complete execution plan without altering system state.
  - Verified by an automated test harness (`tests/dryrun.sh`) that intercepts and aborts if any system modification command (`sudo`, `pacman`, `apt`, `dnf`, `git`, `curl`, `wget`, `rm`, `systemctl`) is attempted.
- **Robust Execution Pipeline**:
  - Direct function-based plan engine (`steps/common.sh`) with zero `eval` string interpolation.
  - Tracks individual step results and outputs an honest summary screen highlighting any failed step and log locations.
  - Sudo keepalive loop protected by signal traps (`EXIT`, `INT`, `TERM`) ensuring no orphan background processes.
- **Hardware & Laptop Auto-Detection**:
  - Detects CPU vendor and flags AMD P-State EPP tuning.
  - Detects GPU vendors (AMD, NVIDIA, Intel) and configures drivers accordingly.
  - Distinguishes NVIDIA Turing+ architectures (`TU1xx`, `GA1xx`, `AD1xx`, `RTX 20/30/40/50`) to install open DKMS modules (`nvidia-open-kernel-dkms` / `nvidia-open-dkms`), cleanly falling back to proprietary DKMS for legacy cards.
  - Auto-identifies ASUS ROG / TUF laptops to configure `asusctl`, fan curve profiles, and battery charging thresholds (50-100% clamping).
  - Configures precision touchpad tap-to-click, natural scrolling, and libinput options.
- **Modular Sub-Scripts**:
  - Every modular script under `arch/`, `debian/`, `fedora/`, `kali/`, and `termux/` remains directly executable standalone while seamlessly integrating into the automated plan runner.

---

## Quick Start

### 1. Interactive Guided TUI

Launch the full interactive TUI installer:

```bash
./install.sh
```

If neither `dialog` nor `whiptail` is installed, the installer automatically runs the interactive CLI menu:

```bash
./install.sh --cli
```

### 2. Non-Destructive Simulation (Dry-Run)

Inspect exactly what steps and functions will execute without making any changes to your system:

```bash
./install.sh --dry-run
```

You can target specific distributions during simulation:

```bash
./install.sh --dry-run --distro arch
./install.sh --dry-run --distro debian
./install.sh --dry-run --distro fedora
./install.sh --dry-run --distro kali
./install.sh --dry-run --distro termux
```

### 3. Headless / CLI Execution

Run non-interactively using defaults or profile settings:

```bash
./install.sh --cli --distro arch
```

### 4. Strict Abort Mode

By default, the plan runner logs errors, records failed steps, and continues remaining independent steps. To halt immediately on the first failure:

```bash
./install.sh --strict
```

### 5. Distro & Desktop Flags

Override distribution detection or preselect desktop environments:

```bash
./install.sh --distro fedora --desktop kde
./install.sh --distro debian --desktop i3
./install.sh --distro arch --desktop bspwm
./install.sh --distro arch --desktop both
./install.sh --desktop none
```

Supported flags:
- `-d`, `--dry-run`: Simulation mode (never alters the system).
- `--strict`: Abort immediately on the first step error.
- `--tui`: Force TUI dialog mode (errors if no dialog tool is found).
- `--cli`, `--headless`: Run with standard terminal CLI prompts.
- `--distro <d>`: Target distribution (`arch`, `debian`, `fedora`, `kali`, `termux`).
- `--desktop <de>`: Target desktop (`kde`, `i3`, `bspwm`, `both`, `none`).
- `-h`, `--help`: Display usage information.

### 6. Windows (PowerShell & Batch)

For Windows installation (such as Burp Suite Professional, JDK 21 detection, and Windows shortcuts):

**Method A: One-Click / Batch**
Simply run or double-click `install.bat` inside `window\burp\`:

```cmd
.\window\burp\install.bat
```

**Method B: PowerShell**
Open `PowerShell` as administrator and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\window\burp\install.ps1
```

---

## Repository Architecture

The codebase follows a modular directory layout:

```text
post_install/
├── install.sh                  # Main entry point & TUI orchestrator
│
├── lib/                        # Core shared libraries
│   ├── common.sh               # Logging, container checks, uv/flatpak/service utilities
│   ├── ui.sh                   # Whiptail/dialog abstraction layer & vim keybindings
│   ├── menu.sh                 # Data-driven menu definitions & catalog tables
│   ├── pkg-apt.sh              # Thin package manager wrapper for Debian/Ubuntu
│   ├── pkg-dnf.sh              # Thin package manager wrapper for Fedora
│   └── pkg-pacman.sh           # Thin package manager wrapper for Arch
│
├── steps/                      # Modular plan builders & step execution functions
│   ├── common.sh               # Execution plan primitives, thorium_pkg(), aur_cmd()
│   ├── arch.sh                 # Arch Linux step implementations & plan builder
│   ├── debian.sh               # Debian / Ubuntu step implementations & plan builder
│   ├── fedora.sh               # Fedora step implementations & plan builder
│   ├── kali.sh                 # Kali Linux step implementations & plan builder
│   └── termux.sh               # Android Termux step implementations & plan builder
│
├── profiles/                   # Declarative configuration defaults
│   ├── _base.conf              # Universal baseline configuration variables
│   ├── arch.conf               # Arch Linux profile defaults
│   ├── debian.conf             # Debian / Ubuntu profile defaults
│   ├── fedora.conf             # Fedora profile defaults
│   ├── kali.conf               # Kali Linux profile defaults
│   └── termux.conf             # Android Termux profile defaults
│
├── tests/                      # Automated validation suite
│   └── dryrun.sh               # Dry-run safety net test with stubbed destructive binaries
│
├── arch/                       # Arch Linux modular sub-scripts (apps, hardware, desktop, virt, packages.txt)
├── debian/                     # Debian modular sub-scripts & debian/lib/common.sh
├── fedora/                     # Fedora modular sub-scripts, config, & fedora/lib/common.sh
├── kali/                       # Kali Linux modular sub-scripts (apps, hardware)
├── termux/                     # Termux scripts & font installer
├── window/                     # Windows PowerShell scripts & assets (burp/install.ps1, .ico, config)
└── theme_and_font.sh           # Standalone font and theme installer
```

---

## The `--dry-run` Safety Guarantee

`--dry-run` (or `-d`) is guaranteed to be **non-destructive**. It resolves profiles, runs hardware auto-detection, formats the step plan, and prints the exact execution sequence without modifying files, installing packages, or invoking root privileges.

### Automated Safety Verification

The safety net is enforced by `tests/dryrun.sh`. For every supported distribution (`arch`, `debian`, `fedora`, `kali`, `termux`), the test runs `install.sh --dry-run` inside an isolated environment where all modifying and network binaries:

- `sudo`, `doas`
- `pacman`, `apt`, `apt-get`, `nala`, `dnf`
- `git`, `curl`, `wget`
- `rm`, `systemctl`

are replaced with interceptor stubs that immediately print `FORBIDDEN: <cmd>` and exit with code 99. The test passes only if the exit code is 0 and zero forbidden calls are made.

Run the test suite anytime:

```bash
./tests/dryrun.sh
```

---

## Strict Execution Mode (`--strict`)

By default, the plan runner operates in standard resilient mode: if an individual step fails, the failure is logged and recorded in an internal ledger, and the runner proceeds with subsequent steps. At completion, an overview screen displays exactly which steps failed along with their log paths.

When `--strict` is passed:
- The runner halts immediately upon the first step returning a non-zero exit code.
- Sudo keepalive background processes are cleanly terminated.
- The terminal cursor and settings are restored.

---

## Configuration Profiles

Configuration is managed via declarative Bash `.conf` files in `profiles/`:

- `profiles/_base.conf`: Sets core defaults common to all targets (`CFG_DESKTOP`, `CFG_DOCKER`, `CFG_GAMING`, `CFG_CODING_TOOLS`, `CFG_PROD_APPS`, `CFG_NVIM_REPO`, etc.).
- `profiles/<distro>.conf`: Overrides specific defaults for the selected distribution (e.g., `CFG_AUR="paru"` and `CFG_MIRRORS=true` for Arch; `CFG_KALI_META="large"` for Kali).

Hardware auto-detection overrides profile defaults dynamically (e.g. `CFG_AMD_GPU=true` when an AMD graphics card is detected).

---

## Supported Distributions & Capabilities

### 1. Arch Linux
- **Mirrors**: Automated ranking via `reflector` with rate sorting and 30s timeout protection.
- **Kernel Headers**: Dynamically selects `linux-headers`, `linux-lts-headers`, `linux-zen-headers`, or `linux-hardened-headers` based on `uname -r`.
- **Base Packages**: Clean package manifest in `arch/packages.txt` verified against official Arch Linux repositories.
- **AUR Helper**: Installs `paru` (or `yay`) with automated compilation fallback and inter-helper failover (`paru` falls back to `yay`, and vice versa).
- **Desktop**: KDE Plasma 6 (Wayland session, standard apps) and X11 tiling window managers (i3, bspwm, or both).
- **GPU & Hardware**: AMD (with optional `--pro` components), NVIDIA (Turing+ open DKMS detection), Intel, ASUS ROG power management (`asusctl` battery limit clamping), Precision Touchpad.
- **Apps & Stack**: Docker Engine & Buildx, KVM/QEMU, VMware Workstation, Gaming suite (Steam, Lutris, Wine, Gamemode), Developer suite (Neovim, VSCode, Cursor, Flutter, Android Studio, Claude Code), Burp Suite Pro.

### 2. Debian & Ubuntu
- **Repository Setup**: deb822 sources management using an AWK parser that preserves comments, blank lines, and guarantees `non-free-firmware` is never appended to `debian-security` stanzas.
- **Package Manager**: Seamless `nala` frontend integration with `apt-get` fallback.
- **GPU Drivers**: Architecture detection for NVIDIA Turing+ (`nvidia-open-kernel-dkms`) with proprietary driver fallback (`nvidia-driver`), AMD ROCm, Intel graphics.
- **Productivity & Flatpak**: Pacstall integration, Flatpak / Flathub setup, Obsidian, Zen Browser, Thorium, LocalSend, AnyDesk, LibreOffice.
- **Virtualization & Developer Tools**: KVM/QEMU, VMware Workstation, Docker CE, uv/pipx tooling, Starship prompt (temp-file download with SHA-256 validation).

### 3. Fedora
- **DNF Optimization**: Detects DNF4 vs DNF5 (`is_dnf5`), preserves all optimizations (`fastestmirror=True`, `max_parallel_downloads=10`, `skip_if_unavailable=True`), and creates a one-time `.bak` backup.
- **Repositories**: Configures RPM Fusion (free and non-free) and targeted COPR repositories.
- **Multimedia Codecs**: Automatic FFmpeg swap (`ffmpeg-free` -> `ffmpeg`) with `--allowerasing`.
- **Desktops & Hardware**: KDE Plasma, tiling window managers (i3, bspwm), ASUS ROG tools, NVIDIA/AMD/Intel drivers, KVM/QEMU.

### 4. Kali Linux
- **Core Setup**: Preserves `~/cybersec` directory hierarchy and automated dotfiles clone/link from `aadish0day/dotfile`.
- **Metapackages**: Flexible installation of `kali-linux-large`, `kali-linux-everything`, or `kali-linux-labs`.
- **Exploit Database**: Automated `searchsploit` database updating.
- **Docker CE**: Configured from official Docker Debian repositories with rolling codename mapping (`kali-rolling` -> `bookworm`), buildx and compose plugins.
- **WiFi Drivers**: Realtek RTL8821AU/RTL8812AU setup via morrownr's GitHub repository with automated fallback to Kali's official `realtek-rtl88xxau-dkms` package.

### 5. Android Termux
- **Core Environment**: Package updates and terminal productivity suite (`git`, `tmux`, `zsh`, `neovim`, `starship`, `zoxide`, `lsd`).
- **Nerd Fonts**: Installs JetBrains Mono Nerd Font directly from GitHub release archives, updates Termux font settings, and reloads styles.

### 6. Windows (PowerShell)
- **PowerShell Automation**: Standalone PowerShell installers (`window/burp/install.ps1`) optimized with silent progress preferences for fast downloads.
- **Burp Suite Professional**: Automatic PortSwigger latest release API query, JDK 21 detection & auto-installation, `.ico` desktop & start menu shortcuts, and silent background launcher integration (`Burp-Suite-Pro.vbs`).

---

## Session Logging

Every execution (both live and dry-run) is mirrored to `/tmp` via `script`:

- Full timestamped log: `/tmp/post-install-YYYYmmdd_HHMMSS.log`
- Current/latest run symlink: `/tmp/post-install-latest.log`

---

## Verification & Testing

Verify syntax and execution safety before deploying:

```bash
# 1. Syntax check every shell script
find . -name "*.sh" -not -path "*/.git/*" -exec bash -n {} +

# 2. Static analysis with shellcheck
shellcheck -x install.sh lib/*.sh steps/*.sh tests/*.sh

# 3. Dry-run safety test across all distributions
./tests/dryrun.sh
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
