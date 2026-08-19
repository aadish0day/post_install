# Post-Installation Automation Suite

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Kali](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kali-linux&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-000000?style=for-the-badge&logo=terminal&logoColor=white)

Modular post-installation automation suite featuring an **`archinstall`-style interactive TUI**, hardware auto-detection, and modular script execution for **Arch Linux**, **Debian/Ubuntu**, **Fedora**, **Kali Linux**, and **Termux**.

---

## ✨ Features & Highlights

- **`archinstall`-Style Interactive TUI**: Split-screen curses interface featuring dynamic hardware auto-detection, live contextual preview pane, colored `[Yes]` / `[No]` status indicators, and real-time execution monitoring.
- **Hardware & Laptop Optimization**:
  - Auto-detects **ASUS ROG/TUF** laptops (`asusctl`, fan curves, custom battery charge thresholds).
  - Auto-tunes **AMD GPU** drivers (Mesa, Vulkan-Radeon, VA-API, and `amd_pstate=active` GRUB parameters).
  - Precision touchpad configuration (tapping, natural scrolling, palm rejection).
- **AUR Helper Selection**: Choose between **Paru** (Rust, fast `paru-bin`), **Yay** (Go, fast `yay-bin`), or **Both** side-by-side.
- **Strict India Mirror Optimization**: Ranks the fastest HTTPS mirrors strictly in India via `reflector` with parallel connections and safe timeout fallbacks.
- **Modular Component Stack**:
  - **Desktop Environments**: KDE Plasma (`arch/desktop/kde.sh`), X11 Tiling Window Manager (`arch/desktop/tiling.sh`), or Headless.
  - **Virtualization**: KVM/QEMU (`arch/virt/kvm-qemu.sh`) and VMware Workstation Host (`arch/virt/vmware-workstation.sh`).
  - **Containerization**: Official Docker Engine CE, Compose plugin, Buildx, and automatic user group permissions (`arch/apps/docker.sh`).
  - **Developer Toolchain**: Neovim with automated config cloning, VS Code, Cursor AI, Android Studio, Flutter SDK, and Antigravity tooling.
  - **Security Suite**: Burp Suite Pro (`arch/apps/burp/install.sh`), Kali metapackages (`everything`/`large`/`labs`), SearchSploit DB.
  - **Gaming Stack**: Wine-Staging, Winetricks, Lutris, GameMode, and DXVK async (`arch/apps/gaming.sh`).
  - **AI / ML Stack**: AMD ROCm SDK, PyTorch ROCm, and ONNX Runtime ROCm.
  - **Themes & Shell**: Default Zsh shell, Starship prompt, JetBrains Mono Nerd Font, and Dracula GTK theme.
- **JSON Configuration Profiles**: Export, import, and reuse customized installation plans (`--save-config` / `--config`).
- **Dry-Run & Simulation**: Full simulation of planned steps and shell commands with zero system modifications (`--dry-run`).
- **Zero External Python Dependencies**: Built entirely on Python 3 standard library (`curses`, `dataclasses`, `pty`).

---

## 🚀 Quick Start

### 1. Interactive Guided TUI (Default)

```bash
git clone https://github.com/Aadishx07/post_install.git
cd post_install
./install.sh
```

### 2. Simulation / Dry-Run (Inspect Planned Steps)

```bash
./install.sh --dry-run
# or
python3 install.py --dry-run --headless
```

### 3. Unattended Automated Run with JSON Profile

```bash
# Export detected configuration to a JSON profile
python3 install.py --save-config my_profile.json

# Run unattended installation from the profile
python3 install.py --config my_profile.json --headless
```

---

## 🎮 TUI Controls & Vim Keybindings

| Keybinding | Action |
|---|---|
| `j` / `↓` | Move Cursor Down |
| `k` / `↑` | Move Cursor Up |
| `h` / `Esc` / `q` | Go Back / Cancel / Switch Button Left |
| `l` / `Enter` | Open Submenu / Select / Switch Button Right |
| `g` / `Home` | Jump to Top (First item) |
| `G` / `End` | Jump to Bottom (Last item) |
| `Ctrl+d` / `PageDown` | Half-Page Scroll Down |
| `Ctrl+u` / `PageUp` | Half-Page Scroll Up |
| `Space` / `x` | Toggle Checkbox `[✓]` / Toggle `[Yes]`/`[No]` |
| `a` / `c` | Select All / Clear All (in checklists) |
| `s` | Save Configuration Profile to JSON |
| `o` | Load Configuration Profile from JSON |
| `y` / `n` | Confirm (Yes) / Cancel (No) in confirmation dialogs |

---

## 🖥️ Modular Architecture & Directory Structure

```text
post_install/
├── install.sh                     # Universal bootstrap launcher
├── install.py                     # CLI & Archinstall TUI entrypoint
├── README.md                      # Documentation
├── core/
│   ├── detector.py                # Hardware & distribution auto-detection
│   ├── config.py                  # Dataclass configuration model & JSON manager
│   ├── runner.py                  # PTY real-time execution engine & step streamer
│   └── tui/
│       ├── colors.py              # Curses color palette (Yes/No, Highlight, Accents)
│       ├── widgets.py             # Unicode box drawing, headers, footers
│       ├── screens.py             # GlobalMenu, OptionList, SelectList, Input, Confirm
│       └── app.py                 # TUI lifecycle & state management
├── arch/                          # Arch Linux Modular Suite
│   ├── arch.sh                    # Arch master setup script
│   ├── apps/
│   │   ├── paru.sh                # Paru AUR Helper installer (paru-bin fallback)
│   │   ├── yay.sh                 # Yay AUR Helper installer (yay-bin fallback)
│   │   ├── gaming.sh              # Wine-Staging, Lutris, GameMode, DXVK async
│   │   ├── docker.sh              # Docker CE engine, Compose & Buildx
│   │   └── burp/                  # Burp Suite Pro automated installer
│   ├── desktop/
│   │   ├── kde.sh                 # KDE Plasma 6 desktop & Wayland session
│   │   └── tiling.sh              # X11 Tiling WM (Polybar, Picom, Rofi, i3lock-color)
│   ├── hardware/
│   │   ├── asus.sh                # ASUS ROG/TUF tools & fan curves
│   │   └── touchpad.sh            # Libinput precision touchpad configuration
│   └── virt/
│       ├── kvm-qemu.sh            # KVM/QEMU, libvirtd & virt-manager
│       └── vmware-workstation.sh  # VMware Workstation Host installer
├── debian/                        # Debian & Ubuntu modular installers
├── fedora/                        # Fedora modular installers
├── kali/                          # Kali Linux security suite & workspace
└── termux/                        # Android Termux modular installers
```

---

## 📋 Distribution Support Matrix

| Distribution | Supported Flavors | Highlights |
|---|---|---|
| **Arch Linux** | Vanilla Arch, EndeavourOS, CachyOS, Manjaro | Paru/Yay selection, India Reflector, KDE/X11 Tiling, ASUS ROG, AMD ROCm, KVM/VMware, Gaming |
| **Kali Linux** | Kali Rolling | `~/cybersec` workspace, Metapackages (`everything`/`large`/`labs`), RTL8821AU WiFi, Burp Pro |
| **Debian / Ubuntu** | Debian 12+, Ubuntu 22.04+, Pop!_OS, Mint | Neovim source build, Docker CE, Pacstall, Starship prompt |
| **Fedora** | Fedora 39+, RHEL, Rocky Linux | Optimized `dnf.conf` (parallel downloads & fast mirrors), RPM Fusion, Docker CE |
| **Termux** | Termux on Android | Storage access, Zsh, Starship, JetBrains Mono Nerd Font |

---

## ⚙️ CLI Reference

```text
usage: install.py [-h] [--config CONFIG] [--dry-run]
                  [--distro {arch,debian,fedora,kali,termux}]
                  [--save-config SAVE_CONFIG] [--headless]

options:
  -h, --help            show this help message and exit
  --config, -c CONFIG   Path to JSON configuration profile
  --dry-run, -d         Simulate execution without modifying the system
  --distro {arch,debian,fedora,kali,termux}
                        Override target distribution
  --save-config SAVE_CONFIG
                        Export default/detected configuration to JSON file and exit
  --headless, --cli     Run in non-interactive CLI mode
```

---

## 📄 License

Distributed under the [MIT License](LICENSE).
