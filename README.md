# System Setup Automation

This repository automates common system setup tasks like installing applications, drivers, and configuring environments for gaming and virtual machines.

## Setup

### 1. Clone the Repository

Clone the repo to your system:

```bash
git clone https://github.com/Aadishx07/post_install.git
cd post_install
```

### 2. Run the Setup Script

Run the installation script to automate the setup:

```bash
chmod +x install_pkg.sh
./install_pkg.sh
```

The script will ask you to choose your Linux distribution (Debian/Ubuntu, Arch Linux, or Fedora) and automatically set up the necessary tools.

### 3. Gaming Libraries

The script installs required libraries for Wine gaming:

```bash
winetricks vcrun2019 d3dx9 d3dx10 d3dx11_42 d3dx11_43 dxvk corefonts xact d3dcompiler_47 quartz physx vcrun2015 vcrun2017 dotnet20 dotnet35 dotnet40 dotnet45 dotnet46 dotnet48
```

### 4. Virtual Machine Tools

It installs communication tools for virtual machines:

```bash
spice-vdagent qemu-guest-agent
```

### 5. Neovim Configuration

The script clones a personal Neovim configuration if not already present.

### 6. Fonts and Themes

It installs necessary fonts and themes through `theme_and_font.sh`.

