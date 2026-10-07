# Post-Installation Automation Suite

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Kali](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kali-linux&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-000000?style=for-the-badge&logo=terminal&logoColor=white)

Modular, production-grade post-installation automation suite featuring an **`archinstall`-style interactive TUI**, hardware auto-detection, PTY command streaming, JSON profile management, and modular scripts for **Arch Linux**, **Debian / Ubuntu**, **Fedora**, **Kali Linux**, and **Termux**.

---

## 📑 Table of Contents

- [✨ Features & Highlights](#-features--highlights)
- [🚀 Quick Start](#-quick-start)
  - [1. Universal Bootstrap Launcher](#1-universal-bootstrap-launcher)
  - [2. Interactive Guided TUI](#2-interactive-guided-tui)
  - [3. Simulation / Dry-Run Mode](#3-simulation--dry-run-mode)
  - [4. Unattended Profile Automation](#4-unattended-profile-automation)
  - [5. Native Shell Fallback](#5-native-shell-fallback)
- [🖥️ System Architecture & Directory Layout](#️-system-architecture--directory-layout)
- [🎮 Interactive TUI & Keyboard Shortcuts](#-interactive-tui--keyboard-shortcuts)
- [⚙️ CLI Options & Environment Reference](#️-cli-options--environment-reference)
- [📋 Complete Component & Distribution Guide](#-complete-component--distribution-guide)
  - [1. Desktop Environments (KDE Plasma & Tiling WM)](#1-desktop-environments-kde-plasma--tiling-wm)
  - [2. Hardware Drivers & Laptop Optimization](#2-hardware-drivers--laptop-optimization)
  - [3. Virtualization & Containers (KVM, VMware, Docker)](#3-virtualization--containers-kvm-vmware-docker)
  - [4. Developer Toolchain & Coding Stack](#4-developer-toolchain--coding-stack)
  - [5. Cybersecurity Suite (Kali Linux & Burp Pro)](#5-cybersecurity-suite-kali-linux--burp-pro)
  - [6. Gaming & Multimedia Stack](#6-gaming--multimedia-stack)
  - [7. AI / ML ROCm Acceleration](#7-ai--ml-rocm-acceleration)
  - [8. Productivity, Browsers & Tools](#8-productivity-browsers--tools)
  - [9. Android Termux Mobile Setup](#9-android-termux-mobile-setup)
  - [10. Standalone Root Utilities](#10-standalone-root-utilities)
- [🛠️ Deep Dive: Flutter SDK on Arch Linux](#️-deep-dive-flutter-sdk-on-arch-linux)
- [📄 JSON Configuration Schema Reference](#-json-configuration-schema-reference)
- [⚠️ Important Notes & Operational Quirks](#️-important-notes--operational-quirks)
- [📜 License](#-license)

---

## ✨ Features & Highlights

- **`archinstall`-Style Interactive TUI**: Built with [Textual](https://textual.textualize.io/) featuring a blue title bar, split menu with a live configuration preview pane, quick-toggle checkboxes, modal dialogs, `/` live fuzzy search, and real-time execution step checklist. Includes an autonomous, zero-dependency **curses fallback** when Textual is unavailable.
- **Hardware & Laptop Auto-Detection**:
  - Auto-identifies **ASUS ROG & TUF** laptops (`asusctl`, fan curves for Quiet/Balanced/Performance, custom battery charge thresholds).
  - CPU microcode & P-State management: **AMD** (`amd64-microcode` / `amd-ucode`, `amd_pstate=active amd_prefcore=enable` kernel arguments), **Intel** (`intel-ucode`, media drivers).
  - GPU graphics acceleration: **AMD** (Mesa 32/64-bit, Vulkan-Radeon, Freeworld VA-API codecs, optional AMD Pro proprietary AUR stack), **Intel** (Mesa, Vulkan-Intel, VA-API `intel-media-driver`), and **NVIDIA** (`nvidia-open-dkms` / `akmod-nvidia`, D3 dynamic power management `NVreg_DynamicPowerManagement=0x02`, systemd power/suspend services).
  - Precision touchpad configuration (tapping, natural scrolling toggle, horizontal edge scroll, flat acceleration profile).
- **Package Manager & Repository Optimization**:
  - **Arch Linux**: Strict India mirror ranking via `reflector` with timeouts, parallel connections, and AUR helper management (**Paru**, **Yay**, or **Both** side-by-side).
  - **Fedora**: Automatic `dnf.conf` / `dnf5.conf` tuning (`max_parallel_downloads=10`, `fastestmirror=True`, `defaultyes=True`), RPM Fusion (free/nonfree), COPR repositories, and full `ffmpeg` codec swapping.
  - **Debian / Ubuntu**: Nala frontend integration, `contrib`, `non-free`, `non-free-firmware`, 32-bit multiarch (`i386`), and Pacstall package manager.
- **PTY Real-Time Execution Engine**:
  - Child processes run under a pseudo-terminal (`pty.openpty()`), streaming progress output without buffer deadlocks.
  - Automatic filtering of transient progress bars (pacman, apt, nala, curl, pip) and terminal escape sequences.
  - Session execution logging to `/tmp/post-install-YYYYmmdd_HHMMSS.log` (symlinked to `/tmp/post-install-latest.log`).
- **Comprehensive Software Ecosystem**:
  - **Virtualization**: KVM / QEMU (`libvirt`, `virt-manager`, UEFI OVMF, swtpm, bridge networking) and VMware Workstation Host (DKMS / kernel module compilation).
  - **Containerization**: Official Docker Engine CE, Compose plugin, Buildx, user group permissions, and Lazydocker TUI (`lzd` alias).
  - **Developer Tools**: Neovim (source build on Debian, package on Arch/Fedora), VS Code, Cursor AI, Claude Code, Android Studio, Flutter SDK, Google Antigravity tooling, and MarkItDown CLI (with OCR and OpenAI plugins via `uv tool`).
  - **Security Suite**: Burp Suite Professional automated patcher/installer with Java 21, Kali metapackages (`everything`, `large`, `labs`), SearchSploit DB, and RTL8821AU USB WiFi DKMS driver.
  - **Gaming Suite**: Wine-Staging, Winetricks, Lutris, GameMode (`gamemoded.service`), MangoHud, GOverlay, DXVK async / umu-launcher, and Steam.
  - **AI / ML Stack**: AMD ROCm SDK, ROCm SMI, HIP compiler, PyTorch ROCm, and ONNX Runtime ROCm.
- **Reproducible JSON Profiles**: Export, import, and share automated installation configurations (`--save-config` / `--config`).
- **Safe Dry-Run Simulation**: Inspect planned steps, script invocations, and shell commands without altering the system (`--dry-run`).

---

## 🚀 Quick Start

### 1. Universal Bootstrap Launcher

Clone the repository and run the universal launcher:

```bash
git clone https://github.com/Aadishx07/post_install.git
cd post_install
chmod +x install.sh install.py
./install.sh
```

`install.sh` automatically checks prerequisites, initializes PTY session logging in `/tmp/`, installs `textual` if missing, and launches the interface.

---

### 2. Interactive Guided TUI

Launch the full interactive interface:

```bash
# Auto-detects Textual or falls back to curses
./install.sh

# Or invoke the Python orchestrator directly
python3 install.py

# Force a specific interface
python3 install.py --tui textual
python3 install.py --tui curses
```

---

### 3. Simulation / Dry-Run Mode

Preview all actions and planned shell execution commands without modifying your system:

```bash
# Dry-run via launcher
./install.sh --dry-run

# Dry-run in headless CLI mode
python3 install.py --dry-run --headless
```

---

### 4. Unattended Profile Automation

Export your system's detected profile, customize it, and run unattended:

```bash
# 1. Export detected system settings to a JSON profile
python3 install.py --save-config my_profile.json

# 2. (Optional) Inspect or edit my_profile.json to enable/disable components

# 3. Execute unattended post-installation
python3 install.py --config my_profile.json --headless
```

---

### 5. Native Shell Fallback

If Python 3 is not installed or you prefer executing direct shell scripts:

```bash
# Arch Linux
cd arch && ./arch.sh

# Debian / Ubuntu
cd debian && ./debian.sh

# Fedora
cd fedora && ./fedora.sh

# Kali Linux
cd kali && ./kali.sh

# Android Termux
cd termux && ./termux.sh
```

---

## 🖥️ System Architecture & Directory Layout

```text
post_install/
├── install.sh                     # Universal bootstrap launcher with PTY session logging
├── install.py                     # Python orchestrator, CLI parser & TUI entrypoint
├── README.md                      # Comprehensive documentation and usage guide
├── LICENSE                        # MIT License
├── vmtools.sh                     # Multi-distro VMware Guest Tools installer
├── extract-ssh.sh                 # Secure SSH archive extraction & permission hardening
├── theme_and_font.sh              # Standalone Nerd Font (FiraMono) installer
├── core/                          # Orchestration and TUI Engine
│   ├── __init__.py
│   ├── config.py                  # Dataclass configuration model & JSON serialization
│   ├── detector.py                # Hardware, GPU, CPU, chassis & distro detection
│   ├── runner.py                  # PTY real-time execution engine, parser & plan builder
│   └── tui/                       # Dual TUI Engine (Textual + Curses Fallback)
│       ├── __init__.py
│       ├── model.py               # Shared menu items, previews, toggles & prompter protocol
│       ├── textual_app.py         # Modern Archinstall-style Textual TUI (Textual >= 2.0)
│       ├── app.py                 # TUI entry point & curses lifecycle wrapper
│       ├── screens.py             # Curses screens (Menu, Checklist, Radio, Input, Progress)
│       ├── widgets.py             # Curses box-drawing, headers, footers & layout widgets
│       └── colors.py              # Curses terminal color palette definitions
├── arch/                          # Arch Linux Modular Suite
│   ├── arch.sh                    # Interactive master installer
│   ├── apps/                      # Modular application installers
│   │   ├── burp/                  # Burp Suite Pro loader, assets & desktop launcher
│   │   │   ├── install.sh
│   │   │   └── images.png
│   │   ├── docker.sh              # Docker CE, compose, buildx & group configuration
│   │   ├── flutter.sh             # Flutter SDK user group & unionfs cache cleaner
│   │   ├── gaming.sh              # Wine-staging, Lutris, GameMode, Proton & DXVK async
│   │   ├── paru.sh                # Paru AUR Helper (paru-bin fallback)
│   │   ├── yay.sh                 # Yay AUR Helper (yay-bin fallback)
│   │   └── xdm.sh                 # Xtreme Download Manager GitHub installer
│   ├── desktop/                   # Desktop environments
│   │   ├── kde.sh                 # KDE Plasma 6 desktop & Wayland/X11 suite
│   │   └── tiling.sh              # X11 Tiling WM (Polybar, Picom, Rofi, Kitty, i3lock-color)
│   ├── hardware/                  # Hardware enablement
│   │   ├── asus.sh                # ASUS ROG/TUF tools, fan curves & charge limits
│   │   ├── touchpad.sh            # Libinput precision touchpad configuration
│   │   └── gpu/                   # GPU driver stacks
│   │       ├── amd.sh             # AMD microcode, Mesa, Vulkan, amd_pstate, optional AMD Pro
│   │       ├── intel.sh           # Intel microcode, Mesa, Vulkan-Intel, VA-API
│   │       └── nvidia.sh          # nvidia-open-dkms, power management & laptop suspend
│   └── virt/                      # Virtualization stacks
│       ├── kvm-qemu.sh            # KVM/QEMU, libvirt, virt-manager, OVMF UEFI & swtpm
│       └── vmware-workstation.sh  # VMware Workstation Host installer & kernel modules
├── debian/                        # Debian & Ubuntu Modular Suite
│   ├── debian.sh                  # Interactive master installer
│   ├── lib/
│   │   └── common.sh              # Shared helpers (apt_install, pacstall, uv_tool, simulation)
│   ├── system/                    # Core system components
│   │   ├── repos.sh               # Apt repos (contrib, non-free, i386, Nala frontend)
│   │   ├── base.sh                # Base utilities, PipeWire, fonts, build headers, Starship
│   │   ├── pacstall.sh            # Pacstall AUR-like package manager installer
│   │   ├── flatpak.sh             # Flatpak runtime & Flathub remote
│   │   └── shell.sh               # Zsh shell, Starship configuration & portal services
│   ├── hardware/                  # Hardware enablement
│   │   ├── asus.sh                # ASUS ROG asusctl source build & fan curves
│   │   ├── touchpad.sh            # X11 precision touchpad configuration
│   │   └── gpu/
│   │       ├── amd.sh             # AMD microcode, amd_pstate, 32/64-bit Mesa & Vulkan
│   │       ├── intel.sh           # Intel microcode, 32/64-bit Mesa, Vulkan & VA-API
│   │       └── nvidia.sh          # NVIDIA open kernel DKMS / ubuntu-drivers & power config
│   ├── desktop/
│   │   ├── kde.sh                 # KDE Plasma suite, SDDM & Obsidian
│   │   └── tiling.sh              # X11 Tiling WM, Dracula GTK & JetBrains Mono Nerd Font
│   ├── virt/
│   │   ├── kvm-qemu.sh            # KVM/QEMU, libvirt daemon, bridge network & virt-manager
│   │   └── vmware-workstation.sh  # VMware Workstation Pro bundle installer & host modules
│   └── apps/                      # Application suite
│       ├── aiml.sh                # AMD ROCm SDK, SMI, HIP & PyTorch ROCm venv
│       ├── coding.sh              # Neovim, VS Code, Cursor, Claude Code, Flutter, Antigravity
│       ├── docker.sh              # Docker CE official repo, compose, buildx & group
│       ├── gaming.sh              # Wine, Lutris, GameMode, umu-launcher, Steam
│       ├── lazydocker.sh          # Lazydocker release binary installer & lzd alias
│       ├── markitdown.sh          # Microsoft MarkItDown via uv tool with OCR/OpenAI
│       ├── neovim.sh              # Neovim stable source compilation & installation
│       ├── productivity.sh        # Thorium Browser, Zen Browser, Obsidian, LocalSend, Vesktop
│       └── xdm.sh                 # Xtreme Download Manager GitHub installer
├── fedora/                        # Fedora Modular Suite
│   ├── fedora.sh                  # Interactive master installer
│   ├── lib/
│   │   └── common.sh              # Shared helpers (dnf_install, copr, swap_ffmpeg, grubby)
│   ├── config/
│   │   └── dnf.conf               # Tuned DNF configuration (parallel downloads, fast mirrors)
│   ├── system/
│   │   ├── dnf.sh                 # DNF / DNF5 configuration injection
│   │   ├── repos.sh               # RPM Fusion free/nonfree, COPRs & swap_ffmpeg
│   │   ├── base.sh                # Base utilities, PipeWire, build tools, Starship, Yazi
│   │   ├── flatpak.sh             # Flatpak runtime & Flathub remote
│   │   └── shell.sh               # Zsh shell, Starship configuration & portal services
│   ├── hardware/
│   │   ├── asus.sh                # ASUS ROG via Terra COPR, fan curves & charge limits
│   │   ├── touchpad.sh            # X11 precision touchpad configuration
│   │   └── gpu/
│   │       ├── amd.sh             # AMD microcode, grubby amd_pstate, Freeworld codecs
│   │       ├── intel.sh           # Intel microcode, 32/64-bit Mesa, Vulkan & media drivers
│   │       └── nvidia.sh          # RPM Fusion akmod-nvidia, akmods build & dynamic power
│   ├── desktop/
│   │   ├── kde.sh                 # KDE Plasma suite, SDDM & graphical target
│   │   └── tiling.sh              # X11 Tiling WM, Dracula GTK & JetBrains Mono Nerd Font
│   ├── virt/
│   │   ├── kvm-qemu.sh            # KVM/QEMU, modular virtqemud/virtnetworkd sockets
│   │   └── vmware-workstation.sh  # VMware Workstation Pro bundle installer & host modules
│   └── apps/                      # Application suite
│       ├── aiml.sh                # Fedora native ROCm packages, SMI, HIP, rocblas & MIOpen
│       ├── coding.sh              # Neovim, VS Code, Cursor, Claude Code, Flutter, Antigravity
│       ├── docker.sh              # Docker CE official repo, compose, buildx & group
│       ├── gaming.sh              # Wine, Lutris, GameMode, umu-launcher, Steam
│       ├── lazydocker.sh          # Lazydocker release binary installer & lzd alias
│       ├── markitdown.sh          # Microsoft MarkItDown via uv tool with OCR/OpenAI
│       ├── productivity.sh        # Thorium (AVX2/SSE4 RPM), Zen, Obsidian, LocalSend, Vesktop
│       └── xdm.sh                 # Xtreme Download Manager GitHub installer
├── kali/                          # Kali Linux Cybersecurity Suite
│   ├── kali.sh                    # Interactive master installer
│   ├── hardware/
│   │   └── wifi.sh                # Realtek RTL8821AU USB WiFi DKMS driver installer
│   ├── system/
│   │   └── user.sh                # Hardened pentest user creation & kali user removal
│   └── apps/
│       ├── burp/                  # Burp Suite Pro loader, assets & desktop launcher
│       │   ├── install.sh
│       │   └── images.png
│       ├── docker.sh              # Docker CE from official Debian Bookworm repository
│       └── lazydocker.sh          # Lazydocker release binary installer & lzd alias
└── termux/                        # Android Termux Mobile Suite
    ├── termux.sh                  # Core packages, storage access, Zsh, Starship & dotfiles
    └── system/
        └── font.sh                # JetBrains Mono Nerd Font installer (~/.termux/font.ttf)
```

---

## 🎮 Interactive TUI & Keyboard Shortcuts

Both the modern **Textual** and autonomous **Curses** interfaces support full Vim navigation and keyboard ergonomics:

| Keybinding | Action | Context |
|---|---|---|
| `j` / `↓` | Move cursor down | Menus, Dialogs, Checklists |
| `k` / `↑` | Move cursor up | Menus, Dialogs, Checklists |
| `h` / `Esc` / `q` | Go back / Cancel / Focus Left | Navigation & Dialogs |
| `l` / `Enter` | Select / Open Submenu / Confirm | Menus & Dialogs |
| `g` / `Home` | Jump to first item | Menus & Checklists |
| `G` / `End` | Jump to last item | Menus & Checklists |
| `Ctrl+d` / `PageDown` | Scroll half-page down | Menus & Progress Log |
| `Ctrl+u` / `PageUp` | Scroll half-page up | Menus & Progress Log |
| `Space` / `x` | Quick-toggle checkbox `[✓]` | Checklists & Quick Toggles |
| `a` | Select all options | Multi-select dialogs |
| `c` | Clear / Deselect all options | Multi-select dialogs |
| `/` | Search & filter menu items in real-time | Textual Main Menu |
| `s` | Export current configuration to JSON profile | Main Menu |
| `o` | Import and load configuration from JSON profile | Main Menu |
| `y` / `n` | Confirm (`Yes`) / Cancel (`No`) | Confirmation Dialogs |
| `F1` | Show / Hide keyboard shortcuts & help panel | Textual Interface |
| `Ctrl+q` | Quit installer | Anywhere in TUI |

---

## ⚙️ CLI Options & Environment Reference

### `install.py` Command Line Arguments

```text
usage: install.py [-h] [--config CONFIG] [--dry-run]
                  [--distro {arch,debian,fedora,kali,termux}]
                  [--save-config SAVE_CONFIG] [--headless]
                  [--tui {auto,textual,curses}]

options:
  -h, --help            Show help message and exit
  --config, -c CONFIG   Path to JSON configuration profile to execute
  --dry-run, -d         Simulate planned commands without modifying the system
  --distro {arch,debian,fedora,kali,termux}
                        Override auto-detected distribution
  --save-config SAVE_CONFIG
                        Export default/detected configuration to JSON and exit
  --headless, --cli     Execute unattended non-interactive CLI mode
  --tui {auto,textual,curses}
                        Frontend interface: textual (>=2.0), curses (stdlib), or auto (default)
```

### Environment Variables & Session Logging

- `POST_INSTALL_LOG_FILE`: Points to the active session log in `/tmp/` generated by `install.sh`.
- `POST_INSTALL_LOGGED`: Guard variable preventing recursive PTY allocation loops.
- `POST_INSTALL_ORIG_TTY`: Preserves original interactive terminal status before `script` PTY allocation.
- `PYTHONUNBUFFERED=1`: Ensures unbuffered stdout/stderr output streaming in headless pipes.

---

## 📋 Complete Component & Distribution Guide

### 1. Desktop Environments (KDE Plasma & Tiling WM)

- **KDE Plasma 6 Suite**:
  - **Arch Linux** ([`arch/desktop/kde.sh`](file:///home/aadish/Documents/Github/post_install/arch/desktop/kde.sh)): Installs `plasma-meta`, Wayland/X11 sessions, Dolphin, Kate, Konsole, Ark, Kdenlive, Okular, LibreOffice Fresh, Obsidian, KDE Connect, and SDDM display manager.
  - **Debian / Ubuntu** ([`debian/desktop/kde.sh`](file:///home/aadish/Documents/Github/post_install/debian/desktop/kde.sh)): Installs `kde-plasma-desktop`, Plasma Discover Flatpak backend, SDDM Breeze theme, Gwenview, Kdenlive, and Obsidian.
  - **Fedora** ([`fedora/desktop/kde.sh`](file:///home/aadish/Documents/Github/post_install/fedora/desktop/kde.sh)): Installs `plasma-desktop`, `sddm-kcm`, PowerDevil, BlueDevil, Elisa player, and configures `systemctl set-default graphical.target`.
- **X11 Tiling Window Manager**:
  - Configures a streamlined, lightweight X11 workspace across Arch, Debian, and Fedora ([`arch/desktop/tiling.sh`](file:///home/aadish/Documents/Github/post_install/arch/desktop/tiling.sh), [`debian/desktop/tiling.sh`](file:///home/aadish/Documents/Github/post_install/debian/desktop/tiling.sh), [`fedora/desktop/tiling.sh`](file:///home/aadish/Documents/Github/post_install/fedora/desktop/tiling.sh)).
  - Includes `picom` (compositor), `polybar`, `rofi`, `dunst` (notifications), `kitty` (terminal), `feh`, `flameshot`, `gammastep` (blue light filter), `zathura` (PDF viewer), and `i3lock-color`.
  - Automatically deploys **Dracula GTK theme** and **JetBrains Mono Nerd Font**.

---

### 2. Hardware Drivers & Laptop Optimization

- **ASUS ROG / TUF Gaming Laptops**:
  - **Arch Linux** ([`arch/hardware/asus.sh`](file:///home/aadish/Documents/Github/post_install/arch/hardware/asus.sh)): Deploys `asusctl` and `rog-control-center` from the Arch `extra` repo.
  - **Fedora** ([`fedora/hardware/asus.sh`](file:///home/aadish/Documents/Github/post_install/fedora/hardware/asus.sh)): Configures Fyra Labs Terra repository, installs `asusctl` and `asusctl-rog-gui`, and safely masks `tuned-ppd` / `power-profiles-daemon` to prevent daemon collisions with `asusd`.
  - **Debian** ([`debian/hardware/asus.sh`](file:///home/aadish/Documents/Github/post_install/debian/hardware/asus.sh)): Compiles `asusctl` from source using Rust `cargo` and enables `asusd.service`.
  - **Battery & Fan Curves**: Applies custom battery charging thresholds (default `85%`) and fan curves (`Quiet`, `Performance`, `Balanced`) with safe IPC delays.
- **AMD CPU & GPU**:
  - Installs `amd-ucode` / `amd64-microcode`.
  - Injects `amd_pstate=active amd_prefcore=enable` into kernel parameters via GRUB (Debian/Arch) or `grubby` (Fedora).
  - Installs 32-bit and 64-bit Mesa drivers, Vulkan-Radeon, `radeontop`, and Freeworld VA-API codecs on Fedora.
  - Optional AMD Pro proprietary components on Arch (`--pro` flag in [`arch/hardware/gpu/amd.sh`](file:///home/aadish/Documents/Github/post_install/arch/hardware/gpu/amd.sh)).
- **Intel CPU & GPU**:
  - Installs Intel microcode, 32-bit and 64-bit Mesa, Vulkan-Intel, and VA-API hardware video drivers (`intel-media-driver`).
- **NVIDIA GPU**:
  - Deploys official drivers: `nvidia-open-dkms` (Arch), `nvidia-open-kernel-dkms` (Debian), `ubuntu-drivers` (Ubuntu), or `akmod-nvidia` (Fedora).
  - Configures dynamic power management (`options nvidia NVreg_DynamicPowerManagement=0x02` in `/etc/modprobe.d/`).
  - Enables systemd services: `nvidia-suspend`, `nvidia-hibernate`, `nvidia-resume`, and `nvidia-powerd`.
- **Precision Touchpad**:
  - Writes `/etc/X11/xorg.conf.d/90-touchpad.conf` with tap-to-click, horizontal edge scrolling, clickfinger, palm detection, and flat acceleration.

---

### 3. Virtualization & Containers (KVM, VMware, Docker)

- **KVM / QEMU / virt-manager** ([`arch/virt/kvm-qemu.sh`](file:///home/aadish/Documents/Github/post_install/arch/virt/kvm-qemu.sh), [`debian/virt/kvm-qemu.sh`](file:///home/aadish/Documents/Github/post_install/debian/virt/kvm-qemu.sh), [`fedora/virt/kvm-qemu.sh`](file:///home/aadish/Documents/Github/post_install/fedora/virt/kvm-qemu.sh)):
  - Full virtualization stack: `qemu`, `libvirt`, `virt-manager`, `virt-viewer`, `bridge-utils`, `swtpm` (TPM 2.0 emulation for Windows 11), and OVMF UEFI firmware.
  - Automatically adds the active user to `kvm` and `libvirt` groups.
  - Grants socket permissions (`0770` in `libvirtd.conf`), starts the daemon/sockets (`virtqemud.socket` on Fedora, `libvirtd.service` on Arch/Debian), and autostarts the default NAT virtual network.
- **VMware Workstation Pro Host** ([`arch/virt/vmware-workstation.sh`](file:///home/aadish/Documents/Github/post_install/arch/virt/vmware-workstation.sh), [`debian/virt/vmware-workstation.sh`](file:///home/aadish/Documents/Github/post_install/debian/virt/vmware-workstation.sh), [`fedora/virt/vmware-workstation.sh`](file:///home/aadish/Documents/Github/post_install/fedora/virt/vmware-workstation.sh)):
  - Automates installation of VMware Workstation bundles or AUR packages.
  - Compiles and loads kernel modules (`vmmon`, `vmnet`, `vmw_vmci`) via `vmware-modconfig` and enables `vmware` / `vmware-networks` / `vmware-usbarbitrator` systemd services.
- **Docker CE & Lazydocker** ([`arch/apps/docker.sh`](file:///home/aadish/Documents/Github/post_install/arch/apps/docker.sh), [`debian/apps/docker.sh`](file:///home/aadish/Documents/Github/post_install/debian/apps/docker.sh), [`fedora/apps/docker.sh`](file:///home/aadish/Documents/Github/post_install/fedora/apps/docker.sh)):
  - Removes conflicting legacy packages (`podman-docker`, `docker.io`, `moby-engine`).
  - Configures official Docker CE upstream repositories, installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`, and `docker-buildx-plugin`.
  - Enables `docker.service` and adds the user to the `docker` group for rootless CLI execution.
  - Installs **Lazydocker** terminal UI with the global alias `lzd`.

---

### 4. Developer Toolchain & Coding Stack

Configured via `apps/coding.sh` across distributions:

- **Neovim**:
  - **Debian**: Compiles stable Neovim from source (`neovim/neovim.git`, branch `stable`) to `/usr/local` to guarantee the latest release on older Debian bases.
  - **Arch / Fedora**: Installs official upstream packages (`neovim`, `python3-neovim`).
- **VS Code & Cursor AI**:
  - VS Code configured via official Microsoft APT/YUM repositories or Arch AUR (`visual-studio-code-bin`).
  - Cursor AI downloaded and installed directly from upstream golden `.deb` / `.rpm` builds or AUR (`cursor-bin`).
- **Claude Code**:
  - Installs Anthropic's Claude Code CLI via native installer script (`claude.ai/install.sh`) or npm global package (`@anthropic-ai/claude-code`).
- **Android Studio & Flutter SDK**:
  - Android Studio installed via Pacstall, Flathub, or AUR with 32-bit execution libraries.
  - Flutter SDK deployed to `~/development/flutter` via Google's stable release manifest (or AUR `flutter-bin` on Arch) with PATH configured in `~/.zshrc` and `~/.bashrc`.
- **Google Antigravity Tooling**:
  - Configured via official Google APT/YUM repositories (includes custom GPG verification handling on Fedora 40+ to bypass `rpm-sequoia` SHA-1 key rejections) or AUR (`antigravity`, `antigravity-cli`, `antigravity-ide`).
- **MarkItDown CLI**:
  - Deployed in an isolated environment via Astral's `uv tool` (`uv tool install --with markitdown-ocr --with openai "markitdown[all]"`).
  - Converts PDF, Word, Excel, PowerPoint, audio, images, HTML, and YouTube to Markdown with OCR and LLM plugins.

---

### 5. Cybersecurity Suite (Kali Linux & Burp Pro)

- **Kali Linux Post-Install Master** ([`kali/kali.sh`](file:///home/aadish/Documents/Github/post_install/kali/kali.sh)):
  - Creates the dedicated workspace `~/cybersec/`.
  - Bootstraps `nala` APT frontend for accelerated, structured downloads.
  - Installs Kali metapackages: `kali-linux-everything`, `kali-linux-large`, or `kali-linux-labs`.
  - Clones user dotfiles and sets default shell to Zsh with Starship prompt.
  - Updates the Exploit Database (`searchsploit -u`).
- **Burp Suite Professional Automated Installer** ([`arch/apps/burp/install.sh`](file:///home/aadish/Documents/Github/post_install/arch/apps/burp/install.sh), [`kali/apps/burp/install.sh`](file:///home/aadish/Documents/Github/post_install/kali/apps/burp/install.sh)):
  - Installs OpenJDK 21 and configures system Java alternatives.
  - Downloads the Burp Suite Pro JAR using multi-connection `aria2c`.
  - Generates launcher script `~/.local/bin/burpsuitepro` (symlinked to `/usr/local/bin/burpsuitepro`) with JVM reflection open flags and Java agent loader (`-javaagent:loader.jar -noverify`).
  - Creates a desktop application launcher (`burpsuitepro.desktop`) with custom icon integration.
- **Realtek RTL8821AU USB WiFi Driver** ([`kali/hardware/wifi.sh`](file:///home/aadish/Documents/Github/post_install/kali/hardware/wifi.sh)):
  - Installs kernel headers and builds DKMS drivers for Realtek RTL8821AU/RTL8811AU chipsets with monitor mode and packet injection support.
- **Hardened Pentest User Management** ([`kali/system/user.sh`](file:///home/aadish/Documents/Github/post_install/kali/system/user.sh)):
  - Creates a custom pentest user with `sudo`, `wireshark`, `docker`, and network groups.
  - Optionally deletes the default `kali:kali` user credentials and configures LightDM autologin for the new user.

---

### 6. Gaming & Multimedia Stack

Configured via `apps/gaming.sh`:

- **Compatibility Layer**: Installs `wine-staging`, `winetricks`, `lutris`, and Steam.
- **Performance Tuning**: Installs Feral Interactive's `gamemode`, adds user to the `gamemode` group, and enables the user systemd service `gamemoded.service`.
- **Proton & DXVK**: Installs `umu-launcher` (unified Proton launcher) from upstream release assets, MangoHud overlay, GOverlay GUI, and DXVK async runtimes.
- **Full Codecs**: Ensures complete GStreamer and FFmpeg codecs across all distributions (swaps `ffmpeg-free` to full RPM Fusion `ffmpeg` on Fedora).

---

### 7. AI / ML ROCm Acceleration

Configured via `apps/aiml.sh`:

- **AMD ROCm SDK**: Deploys `rocminfo`, `rocm-smi`, `hipcc`, `rocblas`, `miopen`, and OpenCL development headers.
- **GPU Permissions**: Automatically adds the user to `render` and `video` groups for direct DRI GPU compute access without root privileges.
- **PyTorch & ONNX**:
  - **Arch Linux**: Installs native `python-pytorch-rocm` and `python-onnxruntime-rocm`.
  - **Debian**: Creates an isolated virtual environment at `~/.venvs/rocm` and installs official PyTorch ROCm wheels (`torch`, `torchvision`, `torchaudio`).
  - **Fedora**: Installs native Fedora ROCm packages with DNF `--allowerasing` to prevent Mesa OpenCL conflicts.

---

### 8. Productivity, Browsers & Tools

Configured via `apps/productivity.sh`:

- **Browsers**:
  - **Thorium Browser**: Fast Chromium fork. Debian uses the official APT repo; Fedora dynamically checks `/proc/cpuinfo` for AVX2/SSE4 flags and downloads the optimized RPM; Arch dynamically checks `/proc/cpuinfo` for AVX2/AVX/SSE4 to install the optimal AUR variant (`thorium-browser-avx2-bin`, etc.).
  - **Zen Browser**: Modern Firefox-based browser installed via Flathub, Pacstall, or AUR.
- **Productivity & Communication**:
  - **Obsidian**: Markdown knowledge base installed via Flathub, Pacstall, or AUR.
  - **LocalSend**: Cross-platform local network file sharing.
  - **Vesktop**: Enhanced Discord desktop client.
  - **AnyDesk**: Remote desktop client via official vendor repositories.
  - **ani-cli**: Anime CLI streaming player with MPV and yt-dlp integration.
  - **gallery-dl**: Image gallery and media downloader via `uv tool`.
- **Xtreme Download Manager (XDM)** ([`arch/apps/xdm.sh`](file:///home/aadish/Documents/Github/post_install/arch/apps/xdm.sh), [`debian/apps/xdm.sh`](file:///home/aadish/Documents/Github/post_install/debian/apps/xdm.sh), [`fedora/apps/xdm.sh`](file:///home/aadish/Documents/Github/post_install/fedora/apps/xdm.sh)):
  - Automatically queries the GitHub API (`subhra74/xdm`), downloads the latest release archive, installs to `/opt/xdman`, and integrates with the desktop menu.

---

### 9. Android Termux Mobile Setup

- **`termux/termux.sh`**:
  - Upgrades Termux packages and installs modern CLI utilities: `zsh`, `tmux`, `fzf`, `zoxide`, `starship`, `neovim`, `lsd`, `bat`, `ani-cli`.
  - Requests Android shared storage permissions via `termux-setup-storage`.
  - Clones user dotfiles and sets Zsh as the default shell.
- **`termux/system/font.sh`**:
  - Downloads **JetBrains Mono Nerd Font** from GitHub releases, copies it to `~/.termux/font.ttf`, and calls `termux-reload-settings` to apply powerline glyphs immediately.

---

### 10. Standalone Root Utilities

- **`vmtools.sh`**:
  - Multi-distribution VMware Guest Tools installer supporting Arch, Debian/Ubuntu, and Fedora/RHEL. Installs `open-vm-tools`, `open-vm-tools-desktop`, and enables `vmtoolsd.service`.
- **`extract-ssh.sh`**:
  - Extracts a zip archive containing SSH keys with strict POSIX file permissions: sets `.ssh` directory to `700`, private key (`id_ed25519`) to `600`, and public key (`id_ed25519.pub`) to `644`.
  - Usage: `./extract-ssh.sh <archive.zip> [destination_dir]`
- **`theme_and_font.sh`**:
  - Standalone Nerd Font updater. Queries GitHub releases for Fira Mono Nerd Font, extracts to `~/.local/share/fonts`, and rebuilds font cache via `fc-cache -f`.

---

## 🛠️ Deep Dive: Flutter SDK on Arch Linux

Arch Linux installs the Flutter SDK to `/opt/flutter` via the `flutter-bin` AUR package. The package launcher (`/opt/flutter/bin/aur_init.sh`) enforces two modes of operation:

1. **Direct Access via `flutter` Group (Recommended & Automated)**:
   - When your user belongs to the `flutter` group, Flutter operates directly inside `/opt/flutter` with native permissions.
   - `arch/apps/flutter.sh` automatically adds your user to this group:
     ```bash
     sudo usermod -aG flutter $USER
     ```
   - *Benefits*: Zero FUSE/unionfs overhead, faster compilation, and zero locked cache conflicts during package upgrades.

2. **Unionfs Fallback & Cache Cleanup**:
   - If a user is not in the `flutter` group, writes are redirected to an active FUSE overlay at `~/.cache/flutter_sdk`.
   - After updating `flutter-bin`, any stale unionfs mount must be unmounted and purged:
     ```bash
     fusermount -u -z ~/.cache/flutter_sdk 2>/dev/null || true
     rm -rf ~/.cache/{flutter_sdk,flutter_local}
     ```

---

## 📄 JSON Configuration Schema Reference

When exporting configurations via `--save-config` or using profiles via `--config`, the following keys are supported:

| Key | Type | Default | Description |
|---|---|---|---|
| `distro` | `string` | `"arch"` | Distribution key: `"arch"`, `"debian"`, `"fedora"`, `"kali"`, or `"termux"`. |
| `distro_name` | `string` | `"Arch Linux"` | Display name for the target distribution. |
| `desktop_environment` | `string` | `"kde"` | Desktop to install: `"kde"`, `"tiling"`, or `"none"`. |
| `hardware_asus` | `boolean` | `false` | Enable ASUS ROG/TUF tools (`asusctl`, fan curves, charge limits). |
| `hardware_asus_battery_limit` | `integer` | `85` | Battery charge percentage threshold (50 to 100). |
| `hardware_amd_gpu` | `boolean` | `false` | Enable AMD microcode, 32/64-bit Mesa, Vulkan, and AMD P-State. |
| `hardware_amd_pro` | `boolean` | `false` | Enable AMD Pro proprietary AUR graphics stack (Arch only). |
| `hardware_intel_gpu` | `boolean` | `false` | Enable Intel microcode, Mesa, Vulkan-Intel, and VA-API media drivers. |
| `hardware_nvidia_gpu` | `boolean` | `false` | Enable NVIDIA proprietary drivers, DKMS, and power management. |
| `hardware_kali_wifi` | `boolean` | `false` | Enable Realtek RTL8821AU USB WiFi DKMS driver (Kali only). |
| `virt_kvm_qemu` | `boolean` | `false` | Enable KVM/QEMU, libvirt, virt-manager, OVMF, and swtpm. |
| `virt_vmware_workstation` | `boolean` | `false` | Enable VMware Workstation host services and kernel modules. |
| `docker_enabled` | `boolean` | `false` | Enable Docker CE, Buildx, Compose plugin, and user group. |
| `coding_enabled` | `boolean` | `false` | Enable developer tools and programming environments. |
| `coding_tools` | `array[string]` | `["neovim", "vscode", ...]` | Tools to install: `"neovim"`, `"vscode"`, `"cursor"`, `"claude_code"`, `"android_studio"`, `"flutter"`, `"antigravity"`. |
| `security_burp` | `boolean` | `false` | Enable Burp Suite Professional installer with Java 21 loader. |
| `security_kali_metapackages` | `array[string]` | `[]` | Kali metapackages to install: `"everything"`, `"large"`, `"labs"`. |
| `security_searchsploit_update`| `boolean` | `false` | Run `searchsploit -u` database update. |
| `gaming_enabled` | `boolean` | `false` | Enable Wine-staging, Lutris, GameMode, umu-launcher, and Steam. |
| `ai_ml_enabled` | `boolean` | `false` | Enable AMD ROCm SDK, PyTorch ROCm, and ONNX Runtime. |
| `productivity_enabled` | `boolean` | `false` | Enable Thorium, Zen Browser, Obsidian, LocalSend, and Vesktop. |
| `extra_scripts` | `array[string]` | `[]` | Stem names of auto-discovered scripts in `<distro>/apps/` to run. |
| `repos_mirror_ranking` | `boolean` | `true` | Rank fastest mirrors via Reflector (Arch Linux only). |
| `aur_helper` | `string` | `"paru"` | AUR helper: `"paru"`, `"yay"`, `"both"`, or `"none"`. |
| `repos_pacstall` | `boolean` | `false` | Enable Pacstall package manager (Debian only). |
| `repos_flatpak` | `boolean` | `false` | Enable Flatpak runtime and Flathub remote. |
| `theme_nerd_fonts` | `boolean` | `true` | Install JetBrains Mono Nerd Font. |

### Example JSON Profile (`profile.json`)

```json
{
  "distro": "arch",
  "distro_name": "Arch Linux",
  "desktop_environment": "kde",
  "hardware_asus": true,
  "hardware_asus_battery_limit": 80,
  "hardware_amd_gpu": true,
  "hardware_amd_pro": false,
  "hardware_intel_gpu": false,
  "hardware_nvidia_gpu": false,
  "hardware_kali_wifi": false,
  "virt_kvm_qemu": true,
  "virt_vmware_workstation": false,
  "docker_enabled": true,
  "coding_enabled": true,
  "coding_tools": [
    "neovim",
    "vscode",
    "cursor",
    "claude_code",
    "flutter"
  ],
  "security_burp": false,
  "gaming_enabled": true,
  "ai_ml_enabled": true,
  "productivity_enabled": true,
  "repos_mirror_ranking": true,
  "aur_helper": "paru",
  "repos_flatpak": true,
  "theme_nerd_fonts": true
}
```

---

## ⚠️ Important Notes & Operational Quirks

1. **Display Manager Restart in Touchpad Script**:
   Executing `arch/hardware/touchpad.sh` directly restarts the display manager (`systemctl restart display-manager`). If run from inside an active X11 GUI session, this will immediately terminate the session. It is best run from a TTY or via the full installation pipeline before starting a desktop session.
2. **User Groups & Session Refresh**:
   Adding users to groups such as `docker`, `libvirt`, `kvm`, `render`, `video`, `gamemode`, and `flutter` requires logging out and back in (or running `newgrp <group>`) before group permissions take effect.
3. **WiFi Driver Prerequisites on Kali**:
   Building the RTL8821AU DKMS driver in `kali/hardware/wifi.sh` requires kernel headers and git packages. Ensure temporary network access (Ethernet or USB tethering) is available during installation.
4. **VMware Workstation Pro Bundles**:
   On Debian and Fedora, VMware Workstation Pro requires downloading the official `.bundle` installer from the Broadcom Support Portal into `~/Downloads/`. The script detects the bundle file automatically.
5. **Reboot Recommended**:
   Kernel parameter updates (`amd_pstate`), GPU driver installations, microcode updates, and virtualization module changes require a full system reboot to become fully active.

---

## 📜 License

Distributed under the [MIT License](LICENSE).
