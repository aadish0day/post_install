#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

echo "START KVM/QEMU/VIRT MANAGER INSTALLATION..."
read -p "Do you want to start the installation? (yes/no) " response
if [[ ! $response =~ ^[yY][eE][sS]$ ]]; then
    echo "Installation aborted by the user."
    exit 0
fi

# Install KVM and related packages
kvm_packages=(
    virt-manager
    virt-viewer
    qemu
    vde2
    ebtables
    dnsmasq
    bridge-utils
    ovmf
    swtpm
    iptables-nft
    nftables
    openbsd-netcat
    libguestfs
)
echo "Installing KVM-related packages..."
pacman -S --needed "${kvm_packages[@]}" --noconfirm || {
    echo "Failed to install KVM-related packages."
    exit 1
}

# Install QEMU packages
qemu_packages=(
    qemu-user-static
    samba
    qemu-block-gluster
    qemu-block-iscsi
    qemu-chardev-baum
    qemu-docs
    qemu-emulators-full
    qemu-full
    qemu-hw-s390x-virtio-gpu-ccw
    qemu-pr-helper
    qemu-system-aarch64
    qemu-system-alpha
    qemu-system-arm
    qemu-system-avr
    qemu-system-hppa
    qemu-system-m68k
    qemu-system-microblaze
    qemu-system-mips
    qemu-system-or1k
    qemu-system-ppc
    qemu-system-riscv
    qemu-system-rx
    qemu-system-s390x
    qemu-system-sh4
    qemu-system-sparc
    qemu-system-tricore
    qemu-system-xtensa
    qemu-tests
    qemu-tools
    qemu-user
    qemu-vmsr-helper
    qemu-audio-alsa
    qemu-audio-dbus
    qemu-audio-jack
    qemu-audio-oss
    qemu-audio-pa
    qemu-audio-pipewire
    qemu-audio-sdl
    qemu-audio-spice
    qemu-block-curl
    qemu-block-dmg
    qemu-block-nfs
    qemu-block-ssh
    qemu-chardev-spice
    qemu-desktop
    qemu-hw-display-qxl
    qemu-hw-display-virtio-vga
    qemu-hw-display-virtio-vga-gl
    qemu-hw-display-virtio-gpu
    qemu-hw-display-virtio-gpu-gl
    qemu-hw-display-virtio-gpu-pci
    qemu-hw-display-virtio-gpu-pci-gl
    qemu-hw-usb-host
    qemu-hw-usb-redirect
    qemu-hw-usb-smartcard
    qemu-ui-curses
    qemu-ui-dbus
    qemu-ui-egl-headless
    qemu-ui-gtk
    qemu-ui-opengl
    qemu-ui-sdl
    qemu-ui-spice-app
    qemu-ui-spice-core
    qemu-vhost-user-gpu
    python-pt
    python-unicorn
)
echo "Installing QEMU-related packages..."
pacman -S --needed "${qemu_packages[@]}" --noconfirm || {
    echo "Failed to install QEMU-related packages."
    exit 1
}

# Edit libvirtd.conf
echo "Configuring /etc/libvirt/libvirtd.conf..."
sed -i 's/#unix_sock_group = "libvirt"/unix_sock_group = "libvirt"/' /etc/libvirt/libvirtd.conf
sed -i 's/#unix_sock_rw_perms = "0770"/unix_sock_rw_perms = "0770"/' /etc/libvirt/libvirtd.conf
echo 'log_filters="3:qemu 1:libvirt"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null
echo 'log_outputs="1:file:/var/log/libvirt/libvirtd.log"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null

# Get the current username (not the root user in case of sudo execution)
USER_NAME=$(logname)

echo "Adding $USER_NAME to the kvm and libvirt groups..."
usermod -a -G kvm,libvirt "$USER_NAME" || {
    echo "Failed to add $USER_NAME to the kvm or libvirt groups."
    exit 1
}

echo "User $USER_NAME has been added to kvm and libvirt groups."

# Enable and start services
echo "Enabling and starting libvirtd service..."
systemctl enable --now libvirtd || {
    echo "Failed to enable or start libvirtd."
    exit 1
}

# Restart libvirtd service after all configurations
echo "Restarting libvirtd service..."
systemctl restart libvirtd || {
    echo "Failed to restart libvirtd."
    exit 1
}

# Set default network to autostart
echo "Setting up default network to autostart..."
virsh net-autostart default || {
    echo "Failed to set default network to autostart."
    exit 1
}

echo "Installation and configuration complete! Please restart your system with 'sudo reboot'."
