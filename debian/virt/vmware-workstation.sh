#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# VMWARE WORKSTATION (Debian/Ubuntu)
# VMware isn't in any repo: Broadcom requires a login to download the bundle.
# Usage: vmware-workstation.sh [path/to/VMware-Workstation-*.bundle]
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Installing VMware Workstation build prerequisites..."
headers="linux-headers-$(dpkg --print-architecture)"
is_ubuntu && headers="linux-headers-generic"
# t64 names are trixie/noble+, the others bookworm/jammy; apt_install skips the missing ones
apt_install build-essential "$headers" dkms libaio1t64 libaio1 libpcsclite1 \
    libgtkmm-3.0-1t64 libgtkmm-3.0-1v5 libcanberra-gtk3-module bridge-utils

bundle="${1:-}"
if [ -z "$bundle" ]; then
    bundle="$(find "$HOME/Downloads" -maxdepth 1 -name 'VMware-Workstation-*.bundle' 2>/dev/null | sort -V | tail -n1 || true)"
fi

if command -v vmware >/dev/null 2>&1; then
    log "VMware Workstation is already installed."
elif [ -z "$bundle" ] || [ ! -f "$bundle" ]; then
    warn "No VMware Workstation bundle found."
    cat <<'EOF'
To install VMware Workstation Pro (free for personal use):
  1. Sign in at https://support.broadcom.com and open
     My Downloads > VMware Workstation Pro > Linux.
  2. Download VMware-Workstation-Full-<version>.x86_64.bundle to ~/Downloads
  3. Re-run: debian/virt/vmware-workstation.sh ~/Downloads/VMware-Workstation-*.bundle
EOF
    exit 0
elif is_simulate; then
    log "[simulate] would run $bundle"
    exit 0
else
    log "Running $bundle..."
    chmod +x "$bundle"
    $SUDO "$bundle" --console --required --eulas-agreed
fi

if ! in_container && ! is_simulate; then
    log "Building VMware kernel modules..."
    $SUDO vmware-modconfig --console --install-all || warn "vmware-modconfig failed; see https://github.com/mkubecek/vmware-host-modules"
fi

enable_service vmware.service --now
enable_service vmware-USBArbitrator.service --now

log "VMware Workstation setup complete."
