#!/usr/bin/env bash
# ==============================================================================
# Script: create-debian-vm.sh
# Location: post_install/stanalone/create-debian-vm.sh
# Purpose: Fully automated, headless, lightweight Debian VM deployment with
#          SSH enabled, injected host SSH keys, and zero desktop bloat.
# ==============================================================================

set -euo pipefail

# Color formatting
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${BOLD}${BLUE}=====================================================${RESET}"
echo -e "${BOLD}${BLUE}   Automated Debian Minimal Headless VM Installer    ${RESET}"
echo -e "${BOLD}${BLUE}=====================================================${RESET}\n"

# ------------------------------------------------------------------------------
# 1. Configuration & Default Variables
# ------------------------------------------------------------------------------
VM_NAME="${1:-debian-minimal}"
VM_RAM="${VM_RAM:-2048}"
VM_CPUS="${VM_CPUS:-2}"
VM_DISK_SIZE="${VM_DISK_SIZE:-10}" # in GB
VM_DIR="${VM_DIR:-$HOME/VMs}"
VM_DISK_PATH="${VM_DIR}/${VM_NAME}.qcow2"
PRESEED_FILE="${VM_DIR}/preseed-${VM_NAME}.cfg"
LIBVIRT_URI="qemu:///system"

# Locate Debian ISO
DEFAULT_ISO_DIR="$HOME/Documents/ISO"
ISO_PATH="${ISO_PATH:-}"

if [[ -z "$ISO_PATH" ]]; then
    # Look for debian netinst or installer iso
    FOUND_ISO=$(find "$DEFAULT_ISO_DIR" -maxdepth 2 -iname "*debian*netinst*.iso" 2>/dev/null | head -n 1 || true)
    if [[ -z "$FOUND_ISO" ]]; then
        FOUND_ISO=$(find "$DEFAULT_ISO_DIR" -maxdepth 2 -iname "*debian*.iso" 2>/dev/null | head -n 1 || true)
    fi
    ISO_PATH="$FOUND_ISO"
fi

# Locate host SSH public key
HOST_PUBKEY=""
for key_candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -f "$key_candidate" ]]; then
        HOST_PUBKEY=$(cat "$key_candidate")
        break
    fi
done

# ------------------------------------------------------------------------------
# 2. Dependency Checks
# ------------------------------------------------------------------------------
echo -e "${BOLD}Checking required tools...${RESET}"
for tool in virt-install virsh qemu-img; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${RED}Error: Required command '$tool' is not installed.${RESET}"
        exit 1
    fi
done
echo -e "  ✓ virt-install, virsh, and qemu-img found.\n"

if [[ -z "$ISO_PATH" || ! -f "$ISO_PATH" ]]; then
    echo -e "${RED}Error: Debian ISO not found.${RESET}"
    echo "Please specify the ISO path using ISO_PATH environment variable:"
    echo "  ISO_PATH=/path/to/debian.iso $0"
    exit 1
fi
echo -e "  ✓ Using ISO: ${GREEN}${ISO_PATH}${RESET}"

# Verify or create VMs directory
mkdir -p "$VM_DIR"
if command -v setfacl &>/dev/null; then
    setfacl -m u:libvirt-qemu:rwx "$VM_DIR" 2>/dev/null || true
    setfacl -d -m u:libvirt-qemu:rwx "$VM_DIR" 2>/dev/null || true
fi

# Check for existing VM with same name
if virsh -c "$LIBVIRT_URI" dominfo "$VM_NAME" &>/dev/null; then
    echo -e "${YELLOW}Warning: A VM named '${VM_NAME}' already exists in libvirt.${RESET}"
    read -rp "Destroy and overwrite existing VM '${VM_NAME}'? [y/N]: " confirm_overwrite
    if [[ "$confirm_overwrite" =~ ^[Yy]$ ]]; then
        echo "Removing existing VM..."
        virsh -c "$LIBVIRT_URI" destroy "$VM_NAME" 2>/dev/null || true
        virsh -c "$LIBVIRT_URI" undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        rm -f "$VM_DISK_PATH"
    else
        echo "Aborting."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# 3. Generate Automated Preseed Configuration
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Generating headless preseed configuration...${RESET}"

cat <<EOF >"$PRESEED_FILE"
### Localization
d-i debian-installer/locale string en_US.UTF-8
d-i localechooser/supported-locales multiselect en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us
d-i keymap select us

### Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${VM_NAME}
d-i netcfg/get_domain string local
d-i netcfg/wireless_wep string
d-i hw-detect/load_media boolean false

### Mirror settings (Fast offline install; skips mirror timeouts)
d-i mirror/protocol select http
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/no_mirror boolean true
d-i apt-setup/use_mirror boolean false
d-i apt-setup/services-select multiselect
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/cdrom/set-next boolean false
d-i apt-setup/cdrom/set-failed boolean false
d-i apt-setup/disable-cdrom-entries boolean true

### Clock and time zone
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean false

### Partitioning
d-i partman-auto/disk string /dev/vda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-basicfilesystems/no_swap boolean false
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i partman-md/confirm boolean true
d-i partman-partitioning/confirm_resize boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true

### User accounts
d-i passwd/root-login boolean true
d-i passwd/root-password password debian
d-i passwd/root-password-again password debian
d-i passwd/user-fullname string debian
d-i passwd/username string debian
d-i passwd/user-password password debian
d-i passwd/user-password-again password debian
d-i passwd/user-default-groups string sudo
d-i user-setup/allow-password-weak boolean true

### Package selection: Headless, NO Desktop, SSH Enabled
tasksel tasksel/first multiselect ssh-server, standard
d-i tasksel/first multiselect ssh-server, standard
d-i pkgsel/include string sudo openssh-server
d-i pkgsel/upgrade select none
d-i popularity-contest/participate boolean false
popularity-contest popularity-contest/participate boolean false

### Boot loader installation
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string /dev/vda

### Post-installation Hooks (late_command)
d-i preseed/late_command string \\
    mkdir -p /target/etc/sudoers.d ; \\
    echo 'debian ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/debian ; \\
    chmod 0440 /target/etc/sudoers.d/debian ; \\
    mkdir -p /target/etc/ssh/sshd_config.d ; \\
    echo 'PermitRootLogin yes' > /target/etc/ssh/sshd_config.d/permitroot.conf ; \\
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /target/etc/ssh/sshd_config 2>/dev/null || true ; \\
    mkdir -p /target/root/.ssh ; \\
EOF

if [[ -n "$HOST_PUBKEY" ]]; then
    cat <<EOF >>"$PRESEED_FILE"
    echo '${HOST_PUBKEY}' > /target/root/.ssh/authorized_keys ; \\
    chmod 700 /target/root/.ssh ; \\
    chmod 600 /target/root/.ssh/authorized_keys ; \\
    mkdir -p /target/home/debian/.ssh ; \\
    echo '${HOST_PUBKEY}' > /target/home/debian/.ssh/authorized_keys ; \\
    chmod 700 /target/home/debian/.ssh ; \\
    chmod 600 /target/home/debian/.ssh/authorized_keys ; \\
    in-target chown -R debian:debian /home/debian/.ssh || chown -R 1000:1000 /target/home/debian/.ssh ; \\
EOF
fi

cat <<EOF >>"$PRESEED_FILE"
    echo 'Acquire::ForceIPv4 "true";' > /target/etc/apt/apt.conf.d/99force-ipv4 ; \\
    echo 'deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware' > /target/etc/apt/sources.list ; \\
    echo 'deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware' >> /target/etc/apt/sources.list ; \\
    echo 'deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware' >> /target/etc/apt/sources.list

### Finishing installation
d-i finish-install/reboot_in_progress note
d-i cdrom-detect/eject boolean true
EOF

echo -e "  ✓ Preseed written to: ${GREEN}${PRESEED_FILE}${RESET}"

# ------------------------------------------------------------------------------
# 4. Launch Automated virt-install
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Starting automated VM installation...${RESET}"
echo "Parameters:"
echo "  - VM Name:    ${VM_NAME}"
echo "  - Memory:     ${VM_RAM} MB"
echo "  - vCPUs:      ${VM_CPUS}"
echo "  - Disk Size:  ${VM_DISK_SIZE} GB (${VM_DISK_PATH})"
echo "  - Network:    default (VirtIO NAT)"
echo "  - SSH Key:    $([[ -n "$HOST_PUBKEY" ]] && echo "Injected" || echo "None")"
echo ""

virt-install \
    --connect "$LIBVIRT_URI" \
    --name "$VM_NAME" \
    --memory "$VM_RAM" \
    --vcpus "$VM_CPUS" \
    --disk path="$VM_DISK_PATH",size="$VM_DISK_SIZE",format=qcow2,bus=virtio \
    --location "$ISO_PATH" \
    --initrd-inject "$PRESEED_FILE" \
    --extra-args 'auto=true priority=critical' \
    --osinfo debian13 \
    --graphics spice \
    --noautoconsole \
    --wait -1

echo -e "\n${GREEN}✓ Base installation phase complete!${RESET}"

# If VM is shut down after installation finishes, power it on
VM_STATE=$(virsh -c "$LIBVIRT_URI" dominfo "$VM_NAME" | awk '/State:/ {print $2}')
if [[ "$VM_STATE" != "running" ]]; then
    echo "Starting VM '${VM_NAME}'..."
    virsh -c "$LIBVIRT_URI" start "$VM_NAME"
fi

# ------------------------------------------------------------------------------
# 5. Acquire IP Address and Verify SSH
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}Waiting for VM network configuration and IP lease...${RESET}"
VM_IP=""
for i in {1..20}; do
    VM_IP=$(virsh -c "$LIBVIRT_URI" domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n 1 || true)
    if [[ -z "$VM_IP" ]]; then
        # Try finding from dhcp leases table
        VM_IP=$(virsh -c "$LIBVIRT_URI" net-dhcp-leases default 2>/dev/null | grep -i "$VM_NAME" | awk '{print $5}' | cut -d/ -f1 | head -n 1 || true)
    fi

    if [[ -n "$VM_IP" ]]; then
        break
    fi
    sleep 2
done

echo -e "${BOLD}${GREEN}=====================================================${RESET}"
echo -e "${BOLD}${GREEN}        Installation Finished Successfully!          ${RESET}"
echo -e "${BOLD}${GREEN}=====================================================${RESET}\n"

echo -e "${BOLD}VM Details:${RESET}"
echo "  Name:     ${VM_NAME}"
echo "  State:    Running"
echo "  Memory:   ${VM_RAM} MB"
echo "  vCPUs:    ${VM_CPUS}"
echo "  Disk:     ${VM_DISK_PATH}"
echo "  IP Addr:  ${VM_IP:-'(Waiting for DHCP lease)'}"
echo ""

echo -e "${BOLD}Credentials:${RESET}"
echo "  User:     debian    (Password: debian)"
echo "  Root:     root      (Password: debian)"
echo "  Sudo:     Full passwordless sudo enabled"
echo ""

if [[ -n "$VM_IP" ]]; then
    echo -e "${BOLD}SSH Commands:${RESET}"
    echo "  ssh debian@${VM_IP}"
    echo "  ssh root@${VM_IP}"
    echo ""
fi

echo -e "${BOLD}Console Access:${RESET}"
echo "  virt-viewer -c ${LIBVIRT_URI} ${VM_NAME} &"
echo ""
