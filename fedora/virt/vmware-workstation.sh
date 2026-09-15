#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA VMWARE WORKSTATION
# VMware isn't in any repo and Broadcom requires a login to download it.
# Usage: vmware-workstation.sh [path/to/VMware-Workstation-*.bundle]
# Without a path, ~/Downloads is searched; if no bundle is found the script
# prints download instructions and exits successfully.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Installing VMware Workstation build prerequisites..."
dnf_install gcc make kernel-devel kernel-headers dkms elfutils-libelf-devel \
    libxcrypt-compat pcsc-lite libcanberra-gtk3 fuse-libs

BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
    BUNDLE="$(find "$HOME/Downloads" -maxdepth 1 -name 'VMware-Workstation-*.bundle' 2>/dev/null | sort -V | tail -n1 || true)"
fi

if [ -z "$BUNDLE" ] || [ ! -f "$BUNDLE" ]; then
    cat <<'MSG'

VMware Workstation bundle not found.
  1. Sign in at https://support.broadcom.com and download
     "VMware Workstation Pro for Linux" (VMware-Workstation-Full-*.bundle).
  2. Save it to ~/Downloads (or pass its path to this script).
  3. Re-run: bash fedora/virt/vmware-workstation.sh

MSG
    exit 0
fi

if is_simulate; then
    log "[simulate] would run: sudo sh $BUNDLE --console --eulas-agreed --required"
    exit 0
fi

log "Running installer $BUNDLE..."
chmod +x "$BUNDLE"
$SUDO sh "$BUNDLE" --console --eulas-agreed --required

log "Compiling VMware kernel modules..."
$SUDO vmware-modconfig --console --install-all ||
    warn "Module build failed; newer kernels may need patches from https://github.com/bytium/vm-host-modules"

enable_service vmware.service --now
enable_service vmware-USBArbitrator.service --now

log "VMware Workstation installation complete."
