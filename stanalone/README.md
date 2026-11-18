# Standalone Debian Minimal Headless VM Automation

This directory contains standalone automation scripts for spinning up ultra-lightweight, headless Debian virtual machines in **libvirt / virt-manager** in under 90 seconds.

## Features

- **100% Unattended / Automated**: Zero user prompts or manual clicks required.
- **Ultra-Lightweight Footprint**:
  - Memory usage: ~**200 MiB RAM**.
  - Disk footprint: ~**650 MiB**.
  - **Zero desktop environment**: No GNOME, KDE, or X11 packages installed.
- **Fast Offline Base Install**: Bypasses network mirror hangs (`apt-setup/no_mirror boolean true`) by installing the standard base system and OpenSSH server directly from the local ISO image.
- **SSH Ready Out-of-the-Box**:
  - Automatically injects your host's SSH key (`~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`) into `/home/debian/.ssh/authorized_keys` and `/root/.ssh/authorized_keys`.
  - Enables root SSH login (`PermitRootLogin yes`).
  - Grants the `debian` user passwordless `sudo` rights (`NOPASSWD:ALL`).
- **Standardized Credentials**:
  - User: `debian` (Password: `debian`)
  - Root: `root` (Password: `debian`)

---

## Usage

### 1. Run with Defaults

```bash
cd /home/aadish/Documents/Github/post_install/stanalone
./create-debian-vm.sh
```

This will automatically locate your Debian netinst ISO in `~/Documents/ISO/` and create a VM named `debian-minimal`.

### 2. Custom VM Name or Specs

You can pass a custom name as the first argument, and override environment variables for RAM, CPUs, or disk size:

```bash
VM_RAM=4096 VM_CPUS=4 VM_DISK_SIZE=20 ./create-debian-vm.sh my-debian-node
```

### 3. Specify Custom ISO Path

```bash
ISO_PATH=/path/to/custom-debian.iso ./create-debian-vm.sh custom-vm
```

---

## How It Works Under the Hood

1. **Debian Preseed (`preseed.cfg`)**:
   Generates a debconf preseed configuration file that answers all debian-installer questions ahead of time (language, keymap, disk partition table, user accounts, and package selections).
2. **Package Selection (`tasksel`)**:
   `tasksel/first multiselect ssh-server, standard` selects only the standard CLI utilities and OpenSSH server, ignoring all graphical desktop environments.
3. **Initrd Injection (`virt-install --initrd-inject`)**:
   `virt-install` unpacks the installer kernel and initramfs from the ISO, injects `preseed.cfg` directly into the initrd root, and passes `auto=true priority=critical` to the kernel cmdline.
4. **Post-Installation Hook (`preseed/late_command`)**:
   Executes before the installer reboots to copy your host's SSH public key, enable passwordless sudo, and restore standard APT repositories for future updates.
