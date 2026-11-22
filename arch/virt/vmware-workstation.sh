#!/usr/bin/env bash
set -euo pipefail

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log "Starting VMware Workstation setup on Arch Linux..."

# 1. Install prerequisite base & header packages via pacman
log "Installing linux headers and essential build dependencies..."
kheaders="linux-headers"
case "$(uname -r 2>/dev/null)" in
*-lts*) kheaders="linux-lts-headers" ;;
*-zen*) kheaders="linux-zen-headers" ;;
*-hardened*) kheaders="linux-hardened-headers" ;;
esac
sudo pacman -S --needed --noconfirm "$kheaders" base-devel git dkms fuse2 gtkmm3 pcsclite libcanberra

# 2. Check/Install AUR helper (paru or yay)
aur_helper=""
if command -v paru &>/dev/null; then
    aur_helper="paru"
elif command -v yay &>/dev/null; then
    aur_helper="yay"
else
    log "Neither paru nor yay found. Installing paru-bin via arch/apps/paru.sh..."
    apps_dir="$(dirname "${BASH_SOURCE[0]}")/../apps"
    if bash "$apps_dir/paru.sh" && command -v paru &>/dev/null; then
        aur_helper="paru"
    else
        log "paru-bin install failed, trying yay-bin..."
        if bash "$apps_dir/yay.sh" && command -v yay &>/dev/null; then
            aur_helper="yay"
        fi
    fi
fi

if [ -z "$aur_helper" ]; then
    log "ERROR: No AUR helper available to install VMware packages."
    exit 1
fi

# 3. Install VMware Workstation and related packages from AUR
virt_packages=(
    "vmware-keymaps"
    "ncurses5-compat-libs"
    "vmware-workstation"
    "bridge-utils"
)

log "Installing VMware Workstation AUR packages via $aur_helper..."
"$aur_helper" -S --needed --noconfirm "${virt_packages[@]}"

# 4. Enable and start VMware systemd services
log "Enabling and starting VMware services..."

# Enable networking service for NAT / Host-Only / Bridged network interfaces
if systemctl list-unit-files | grep -q "vmware-networks.service"; then
    log "Enabling vmware-networks service..."
    sudo systemctl enable --now vmware-networks.service
fi

# Enable USB arbitrator service for passing USB devices into VMs
if systemctl list-unit-files | grep -q "vmware-usbarbitrator.service"; then
    log "Enabling vmware-usbarbitrator service..."
    sudo systemctl enable --now vmware-usbarbitrator.service
fi

# Load VMware kernel modules
log "Loading VMware kernel modules..."
modules_ok=true
sudo modprobe -a vmw_vmci vmmon vmnet 2>/dev/null || modules_ok=false
if [ "$modules_ok" = false ]; then
    log "WARN: VMware kernel modules did not load (DKMS build may have failed, or headers don't match the running kernel). Check 'dkms status' and reboot."
fi

# 5. Wayland Compatibility
log "Configuring Wayland compatibility..."
if [ -f /etc/conf.d/vmware ]; then
    if ! grep -q "GDK_BACKEND=x11" /etc/conf.d/vmware; then
        echo "export GDK_BACKEND=x11" | sudo tee -a /etc/conf.d/vmware >/dev/null
    fi
fi

# Ensure user-level wrappers and desktop files force X11
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cat <<EOF >"$HOME/.local/bin/vmware"
#!/usr/bin/env bash
export GDK_BACKEND=x11
exec /usr/bin/vmware "\$@"
EOF
chmod +x "$HOME/.local/bin/vmware"

if [ -f /usr/share/applications/vmware-workstation.desktop ]; then
    sed 's|^Exec=/usr/bin/vmware|Exec=env GDK_BACKEND=x11 /usr/bin/vmware|' \
        /usr/share/applications/vmware-workstation.desktop >"$HOME/.local/share/applications/vmware-workstation.desktop"
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

log "VMware Workstation installation and configuration complete!"
