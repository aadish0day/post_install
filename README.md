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
| **Arch Linux** | `arch/arch.sh` | • Interactive desktop setup (KDE / Tiling WMs)<br>• ASUS laptop tools (`ausu_package.sh`) & AMD GPU optimization<br>• KVM/QEMU virtualization stack (`vm.sh`) & Docker<br>• Burp Suite Professional installer (`Burp/install.sh`) |
| **Kali Linux** | `kali/kali.sh` | • Automated `~/cybersec` workspace & dotfile linking<br>• Metapackage installer (everything / large / labs)<br>• Multi-user setup (`setup_kali_user.sh`) & Realtek WiFi driver<br>• Burp Suite Professional installer (`Burp/install.sh`) |
| **Debian / Ubuntu**| `debian/debian.sh` | • `nala` package manager setup & core dev stack<br>• Neovim source build script (`compile_neovim.sh`)<br>• Official Docker CE setup (`docker.sh`) |
| **Fedora** | `fedora/fedora.sh` | • Tuned `dnf.conf` (parallel downloads & fast mirrors)<br>• RPM Fusion & COPR repo enablement<br>• Docker CE setup (`docker.sh`) |
| **Termux** | `termux/termux.sh` | • Terminal environment setup & dotfiles linking<br>• JetBrainsMono Nerd Font setup (`install_nerd_font.sh`) |

## Key Standalone Tools

- **Burp Suite Professional (`Burp/install.sh`)**: High-speed multi-threaded downloader (`aria2c`), OpenJDK 21 dependency manager, desktop entry creation, and launcher binary (`burpsuitepro`). Available for Arch & Kali.
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
│   ├── Burp/install.sh     # Burp Suite Pro installer (Arch)
│   ├── ausu_package.sh     # ASUS laptop tools & G14 repo
│   ├── driver.sh           # Touchpad & AMD GPU config
│   ├── docker.sh           # Docker & Compose setup
│   ├── vm.sh               # KVM/QEMU virtualization stack
│   └── environment/        # Desktop environments (KDE / Tiling WMs)
├── debian/
│   ├── debian.sh           # Debian/Ubuntu main setup
│   ├── compile_neovim.sh   # Neovim source builder
│   └── docker.sh           # Docker CE setup
├── fedora/
│   ├── fedora.sh           # Fedora main setup
│   ├── dnf.conf            # Optimized DNF configuration
│   └── docker.sh           # Docker CE setup
├── kali/
│   ├── kali.sh             # Kali Linux main setup
│   ├── Burp/install.sh     # Burp Suite Pro installer (Kali)
│   ├── setup_kali_user.sh  # User creation & permission manager
│   ├── wifi-driver.sh      # Realtek 8821au WiFi driver
│   └── docker.sh           # Docker setup
└── termux/
    ├── termux.sh           # Termux main setup
    └── install_nerd_font.sh# Termux Nerd Font installer
```

## License

Licensed under the [MIT License](LICENSE).
