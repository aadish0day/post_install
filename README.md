# Post-Installation Automation Scripts

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Fedora](https://img.shields.io/badge/Fedora-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Kali](https://img.shields.io/badge/Kali_Linux-557C94?style=for-the-badge&logo=kali-linux&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-000000?style=for-the-badge&logo=terminal&logoColor=white)

A collection of modular shell scripts to automate the setup and configuration of various Linux distributions and Termux after a fresh install. Streamlines installation of essential applications, development tools, drivers, desktop environments, gaming runtimes, and personal configurations.

## Supported Distributions

| Distribution | Status | Scripts |
|---|---|---|
| Arch Linux | Fully featured | `arch/` |
| Debian / Ubuntu | Comprehensive | `debian/` |
| Fedora | Comprehensive | `fedora/` |
| Kali Linux | Pentesting-focused | `kali/` |
| Termux (Android) | Mobile terminal setup | `termux/` |

## Quick Start

```bash
git clone https://github.com/Aadishx07/post_install.git
cd post_install
./install.sh
```

The main `install.sh` will:
1. Prompt you to select your distribution
2. Clone your [Neovim configuration](https://github.com/Aadishx07/neovim_config) (if not present)
3. Create `~/Pictures/Screenshots`
4. Execute the corresponding distribution-specific script

### Prerequisites

```bash
# Debian/Ubuntu/Kali
sudo apt install git

# Arch Linux
sudo pacman -S git

# Fedora
sudo dnf install git

# Termux
pkg install git
```

## Scripts Overview

### Core Scripts

| Script | Description |
|---|---|
| `install.sh` | Main entry point — distribution selector, Neovim config clone, orchestrator |
| `theme_and_font.sh` | Downloads and installs [Fira Mono Nerd Font](https://www.nerdfonts.com/) system-wide (also has commented-out Dracula GTK theme and Papirus icon theme installers) |
| `vmtools.sh` | Installs and enables `open-vm-tools` with auto-detection and manual selection for Arch, Debian, Fedora |

---

### Arch Linux (`arch/`)

**Main script** — `arch.sh`
- System update, optional reflector mirror configuration (India)
- Interactive prompts for optional components before any installs
- Summary screen before confirmation
- Smart package installation (skips already-installed packages)
- AUR support via `paru` (auto-installed if missing)

| Script | Description |
|---|---|
| `environment/kde.sh` | KDE Plasma desktop environment with apps (Elisa, Gwenview, Okular, LibreOffice, KDE Connect, etc.) |
| `environment/tiling.sh` | X11 tiling WM stack (Awesome/i3) with polybar, rofi, dunst, feh, picom, thunar, network-manager-applet, zathura, and more |
| `ausu_package.sh` | **ASUS laptop support** — adds the G14 repository, installs `asusctl`, `power-profiles-daemon`, `supergfxctl`, `rog-control-center`, configures battery charge limit (85%) and fan curves |
| `driver.sh` | Touchpad configuration (libinput, tap-to-click, natural scrolling, clickfinger method, disable-while-typing) — AMD GPU drivers are handled inline in `arch.sh` |
| `vm.sh` | Full KVM/QEMU/Virt-Manager stack with libvirt, all QEMU system emulators, audio backends, bridge networking, user groups, and service enablement |
| `docker.sh` | Docker & Docker Compose installation, service enablement, user group addition |

**Arch Linux installs:**
- **General packages** (90+): neovim, yazi, zsh, starship, pipewire, kitty, mpv, obs-studio, qbittorrent, zoxide, yt-dlp, android-tools, noto-fonts, papirus-icon-theme, and more
- **AUR packages**: thorium-browser, ani-cli, vesktop, visual-studio-code-bin, spotify, timeshift-autosnap, advcpmv
- **Gaming** (optional): wine-staging, winetricks, gamemode, lutris, vkd3d, dxvk-gplasync-bin, umu-launcher, 32-bit libraries
- **AMD GPUs** (optional): xf86-video-amdgpu, vulkan-radeon, rocm-opencl-runtime, mesa, GRUB cmdline optimization
- **ASUS** (optional): asusctl, rog-control-center, supergfxctl, amdgpu-pro drivers
- **Virtualization** (optional): VMware Workstation via AUR

---

### Debian / Ubuntu (`debian/`)

**Main script** — `debian.sh`
- Installs `nala` (apt wrapper with faster downloads and prettier output)
- System update via nala
- Installs 50+ packages including: ranger, neovim, mpv, flameshot, obs-studio, libreoffice, bluez, alacritty, android-tools, zathura (with PDF/PS/Djvu/CB plugins), bat, picom, nitrogen, yt-dlp, qalculate-gtk
- Optional: Docker installer prompt

| Script | Description |
|---|---|
| `compile_neovim.sh` | Builds Neovim from source (latest release) with ninja, cmake, doxygen; auto-cleans up after install |
| `docker.sh` | Official Docker CE installation via Docker's apt repository, service enablement, user group |

---

### Fedora (`fedora/`)

**Main script** — `fedora.sh`
- Custom `dnf.conf` with parallel downloads, fastest mirror, default yes
- RPM Fusion (free & non-free) repository enablement
- COPR repos for starship and i3lock-color
- 60+ packages including: neovim, zsh, starship, kitty, mpv, obs-studio, qbittorrent, android-tools, zathura, picom, wine, winetricks, gamemode, lutris, papirus-icon-theme, i3lock-color
- Bluetooth service enablement
- Default shell changed to zsh
- Optional: Docker installer prompt

| Script | Description |
|---|---|
| `docker.sh` | Official Docker CE for Fedora, service enablement, user group |
| `dnf.conf` | Pre-tuned DNF configuration (fastest mirror, parallel downloads, etc.) |

---

### Kali Linux (`kali/`)

**Main script** — `kali.sh`
- Creates `~/cybersec/` directory structure
- Installs nala and upgrades system
- Base packages: git, stow, zsh, tmux, neovim, fzf, zoxide, lsd, starship, open-vm-tools
- Clones and links [dotfiles](https://github.com/aadish0day/dotfile)
- Interactive Kali metapackage installer (everything/large/labs)
- Updates searchsploit database
- Default shell changed to zsh
- Optional: Docker installer prompt

| Script | Description |
|---|---|
| `setup_kali_user.sh` | Creates a new pentesting user with sudo/dialout/wireshark/bluetooth/netdev/kaboxer/vboxsf/docker groups; optionally removes default `kali` user; optional auto-login via LightDM |
| `wifi-driver.sh` | Installs Realtek 8821au WiFi driver from [morrownr/8821au-20210708](https://github.com/morrownr/8821au-20210708) using DKMS |
| `docker.sh` | Docker & Docker Compose via Kali repos (`docker.io` / `docker-compose`) |

---

### Termux (`termux/`)

**Main script** — `termux.sh`
- System update and package install: git, neovim, tmux, zsh, fzf, lsd, bat, zoxide, starship, ani-cli, git-lfs
- Sets up Termux storage access
- Clones and links [dotfiles](https://github.com/aadish0day/dotfile)
- Default shell changed to zsh

| Script | Description |
|---|---|
| `install_nerd_font.sh` | Downloads and applies JetBrainsMono Nerd Font to Termux via `termux-reload-settings` |

## Interactive Prompts

Many scripts prompt for your preferences before making changes:

- **Arch Linux**: Desktop environment (KDE / Tiling WM / None), gaming packages, ASUS drivers, virtualization, Docker, AMD GPU drivers, mirror configuration, default shell
- **Debian / Fedora / Kali**: Docker installation prompt
- **Kali**: Metapackage selection (everything/large/labs)
- **vmtools.sh**: Auto-detection or manual distribution selection

## File Structure

```
post_install/
├── install.sh              # Main entry point
├── theme_and_font.sh       # Nerd Font installer
├── vmtools.sh              # VMware guest tools
├── arch/
│   ├── arch.sh             # Arch main setup
│   ├── docker.sh           # Docker for Arch
│   ├── driver.sh           # Touchpad & AMD config
│   ├── ausu_package.sh     # ASUS laptop tools
│   ├── vm.sh               # KVM/QEMU setup
│   └── environment/
│       ├── kde.sh          # KDE Plasma packages
│       └── tiling.sh       # X11 tiling WM packages
├── debian/
│   ├── debian.sh           # Debian/Ubuntu main setup
│   ├── docker.sh           # Docker for Debian
│   └── compile_neovim.sh   # Build Neovim from source
├── fedora/
│   ├── fedora.sh           # Fedora main setup
│   ├── docker.sh           # Docker for Fedora
│   └── dnf.conf            # Pre-tuned DNF config
├── kali/
│   ├── kali.sh             # Kali main setup
│   ├── docker.sh           # Docker for Kali
│   ├── setup_kali_user.sh  # User creation & management
│   └── wifi-driver.sh      # Realtek 8821au driver
├── termux/
│   ├── termux.sh           # Termux main setup
│   └── install_nerd_font.sh# JetBrainsMono Nerd Font
└── LICENSE                 # MIT License
```

## Contributing

Contributions are welcome! If you'd like to add support for a new distribution, improve an existing script, or add new features, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

