# Post-Installation Automation Scripts

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Kali](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kali-linux&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-000000?style=for-the-badge&logo=terminal&logoColor=white)

Modular shell scripts to automate post-installation configuration for Linux distributions (Arch, Debian, Fedora, Kali) and Termux.

## Quick Start

```bash
git clone https://github.com/Aadishx07/post_install.git
cd post_install
./install.sh
```

## Overview by Distribution

| Distribution | Main Entry | Key Features & Modular Components |
|---|---|---|
| **Arch Linux** | `arch/arch.sh` | • Interactive desktop setup (KDE / Tiling WMs)<br>• ASUS laptop tools (`hardware/asus.sh`) & AMD GPU optimization<br>• KVM/QEMU (`virt/kvm-qemu.sh`) & VMware Workstation (`virt/vmware-workstation.sh`) & Docker (`apps/docker.sh`)<br>• Burp Suite Professional installer (`apps/burp/install.sh`) |
| **Kali Linux** | `kali/kali.sh` | • Automated `~/cybersec` workspace & dotfile linking<br>• Metapackage installer (everything / large / labs)<br>• Multi-user setup (`system/user.sh`) & Realtek WiFi driver (`hardware/wifi.sh`)<br>• Burp Suite Professional installer (`apps/burp/install.sh`) |
| **Debian / Ubuntu**| `debian/debian.sh` | • `nala` package manager setup & core dev stack<br>• Neovim source build script (`apps/neovim.sh`)<br>• Official Docker CE setup (`apps/docker.sh`) |
| **Fedora** | `fedora/fedora.sh` | • Tuned `config/dnf.conf` (parallel downloads & fast mirrors)<br>• RPM Fusion & COPR repo enablement<br>• Docker CE setup (`apps/docker.sh`) |
| **Termux** | `termux/termux.sh` | • Terminal environment setup & dotfiles linking<br>• JetBrainsMono Nerd Font setup (`system/font.sh`) |

## Key Standalone Tools

- **Burp Suite Professional (`apps/burp/install.sh`)**: High-speed multi-threaded downloader (`aria2c`), OpenJDK 21 dependency manager, desktop entry creation, and launcher binary (`burpsuitepro`). Available for Arch & Kali.
- **VMware Guest Tools (`vmtools.sh`)**: Auto-detects distribution and configures `open-vm-tools`.
- **System Fonts (`theme_and_font.sh`)**: System-wide installation of Fira Mono Nerd Font.

## Project Structure

```
post_install/
├── install.sh              # Main entry point selector
├── theme_and_font.sh       # System-wide Nerd Font installer
├── vmtools.sh              # VMware guest tools installer
├── arch/
│   ├── arch.sh             # Arch Linux main setup
│   ├── apps/               # App-specific installers (burp, docker)
│   ├── desktop/            # Desktop environments & UI settings (kde, tiling, touchpad, samsung-second-screen)
│   ├── hardware/           # Hardware drivers (asus)
│   └── virt/               # Virtualization (kvm-qemu, vmware-workstation)
├── debian/
│   ├── debian.sh           # Debian/Ubuntu main setup
│   └── apps/               # App-specific installers (docker, neovim)
├── fedora/
│   ├── fedora.sh           # Fedora main setup
│   ├── apps/               # App-specific installers (docker)
│   └── config/             # Config files (dnf.conf)
├── kali/
│   ├── kali.sh             # Kali Linux main setup
│   ├── apps/               # App-specific installers (burp, docker)
│   ├── hardware/           # Hardware drivers (wifi)
│   └── system/             # System tools (user permissions)
└── termux/
    ├── termux.sh           # Termux main setup
    └── system/             # System scripts (font installer)
```

## License

Licensed under the [MIT License](LICENSE).
