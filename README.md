# Post-Installation Automation Scripts

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

A collection of scripts to automate the setup and configuration of various Linux distributions and Termux, streamlining the installation of essential applications, development tools, drivers, and personal configurations.

## Table of Contents

- [Key Features](#key-features)
- [Supported Distributions](#supported-distributions)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Scripts Overview](#scripts-overview)
  - [Core Scripts](#core-scripts)
  - [Distribution-Specific Scripts](#distribution-specific-scripts)
    - [Arch Linux](#arch-linux)
    - [Debian / Ubuntu](#debian--ubuntu)
    - [Fedora](#fedora)
    - [Kali Linux](#kali-linux)
    - [Termux](#termux)
- [Contributing](#contributing)
- [License](#license)

## Key Features

- **Distribution-Specific Setups**: Tailored installation scripts for Debian/Ubuntu, Arch Linux, Fedora, Kali Linux, and Termux.
- **Automated Application Installation**: Installs a wide range of software, including development tools, system utilities, and multimedia applications.
- **Driver Installation**: Includes scripts for installing graphics drivers and other necessary hardware drivers.
- **Desktop Environment Configuration**: Sets up desktop environments like KDE Plasma and X11 tiling window managers.
- **Gaming Ready**: Installs necessary libraries and tools for gaming on Linux, including Wine and Winetricks.
- **Virtualization Support**: Installs and configures virtualization tools like QEMU/KVM and VMware.
- **Neovim Configuration**: Automatically clones and sets up a pre-configured Neovim environment from [Aadishx07/neovim_config](https://github.com/Aadishx07/neovim_config).
- **Theming and Fonts**: Installs custom fonts and themes to enhance the user interface.

## Supported Distributions

- Debian / Ubuntu
- Arch Linux
- Fedora
- Kali Linux
- Termux

## Prerequisites

Before running the scripts, you need to have `git` installed to clone the repository.

- **Debian/Ubuntu**: `sudo apt install git`
- **Arch Linux**: `sudo pacman -S git`
- **Fedora**: `sudo dnf install git`
- **Kali Linux**: `sudo apt install git`
- **Termux**: `pkg install git`

## Usage

1.  **Clone the Repository**

    Open your terminal and run the following command to clone the repository to your local machine:

    ```bash
    git clone https://github.com/Aadishx07/post_install.git
    cd post_install
    ```

2.  **Run the Main Installer**

    Make the main installation script executable and run it with `sudo` if required by the sub-scripts:

    ```bash
    chmod +x install.sh
    ./install.sh
    ```

    The script will prompt you to select your distribution. Based on your selection, it will execute the appropriate setup script from the corresponding directory.

## Scripts Overview

### Core Scripts

-   `install.sh`: The main entry point for the installation process. It prompts the user to select their distribution, clones the Neovim configuration, and then executes the corresponding distribution-specific script.
-   `theme_and_font.sh`: Installs the Fira Mono Nerd Font for a consistent and pleasant terminal experience.
-   `vmtools.sh`: Installs VMware guest tools (`open-vm-tools`) for Arch, Debian, and Fedora-based systems, enabling features like clipboard sharing and screen resizing when running in a VMware virtual machine.

### Distribution-Specific Scripts

#### Arch Linux (`arch/`)

-   `arch.sh`: The main script for Arch Linux. It handles system updates, installs a wide range of packages from official repositories and the AUR, and allows the user to optionally install:
    -   A desktop environment (KDE Plasma or X11 Tiling WMs).
    -   Gaming packages.
    -   ASUS-specific drivers.
    -   Virtualization packages.
-   `asus_package.sh`: Installs and configures `asusctl` and other utilities for ASUS laptops running Arch Linux.
-   `driver.sh`: Installs AMD GPU drivers (`xf86-video-amdgpu`) and configures touchpad settings.
-   `vm.sh`: Installs and configures a KVM/QEMU/Virt-Manager virtualization environment.

#### Debian / Ubuntu (`debian/`)

-   `debian.sh`: The primary script for Debian/Ubuntu systems. It updates the system and installs a comprehensive set of packages using `nala` for a faster and more user-friendly experience.
-   `compile_neovim.sh`: Downloads the Neovim source code, compiles it, and installs the latest version, ensuring you have the most up-to-date features.

#### Fedora (`fedora/`)

-   `fedora.sh`: The main installation script for Fedora. It configures `dnf` for faster downloads, enables the RPM Fusion and Flathub repositories for a wider range of software, and installs a curated list of packages.

#### Kali Linux (`kali/`)

-   `kali.sh`: The main script for Kali Linux. It installs essential packages, sets up dotfiles, and provides an option to install various Kali metapackages for different pentesting toolsets.
-   `setup_kali_user.sh`: A utility script to create a new user with appropriate pentesting permissions and optionally remove the default `kali` user for better security.
-   `wifi-driver.sh`: Installs drivers for the Realtek 8821au wireless chipset, a common requirement for external Wi-Fi adapters.

#### Termux (`termux/`)

-   `termux.sh`: A setup script for the Termux environment on Android. It installs essential packages, configures storage access, and sets up the Zsh shell with plugins for an enhanced mobile terminal experience.

## Contributing

Contributions are welcome! If you would like to add support for a new distribution, improve an existing script, or add new features, please feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.