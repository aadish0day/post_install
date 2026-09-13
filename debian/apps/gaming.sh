#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEBIAN GAMING STACK (WINE, STEAM, LUTRIS, GAMEMODE, MANGOHUD, UMU)
# Needs contrib/non-free and the i386 architecture (debian/system/repos.sh).
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

log "Starting gaming stack installation..."

if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Enabling i386 architecture for 32-bit game libraries..."
    $SUDO dpkg --add-architecture i386
    apt_force_update
fi

gaming_packages=(
    wine wine64 wine32:i386 winetricks innoextract cabextract
    gamemode libgamemode0:i386 mangohud mangohud:i386 goverlay
    mesa-vulkan-drivers mesa-vulkan-drivers:i386 libvulkan1 libvulkan1:i386 vulkan-tools
    libgl1-mesa-dri:i386 libglx-mesa0:i386 ocl-icd-libopencl1 ocl-icd-libopencl1:i386
    libasound2-plugins:i386 libpulse0:i386 libgnutls30t64:i386 libsdl2-2.0-0 libsdl2-2.0-0:i386
    libva2 libva2:i386 libxcomposite1:i386 libsqlite3-0:i386 gstreamer1.0-plugins-base:i386
    v4l-utils python3-protobuf python3-pefile libayatana-appindicator3-1
)

log "Installing Wine, GameMode, MangoHud and 32-bit runtimes..."
apt_install "${gaming_packages[@]}"

# Steam: Debian's steam-installer (contrib), falling back to Pacstall steam-deb
log "Installing Steam..."
if ! is_simulate; then
    echo "steam steam/question select I AGREE" | $SUDO debconf-set-selections
    echo "steam steam/license note ''" | $SUDO debconf-set-selections
fi
if apt_available steam-installer | grep -qx steam-installer; then
    apt_install steam-installer
else
    pacstall_install steam-deb || warn "Steam could not be installed."
fi

# Lutris: Pacstall lutris-deb, falling back to the upstream .deb release
log "Installing Lutris..."
if ! command -v lutris >/dev/null 2>&1; then
    if ! pacstall_install lutris-deb; then
        url="$(github_asset_url lutris/lutris 'lutris_[0-9.]+_all\.deb$')" || true
        [ -n "${url:-}" ] && install_deb_url "$url" lutris || warn "Lutris could not be installed."
    fi
fi

# umu-launcher (Proton outside Steam, used by Lutris): upstream .deb per release
log "Installing umu-launcher..."
if ! command -v umu-run >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    version_id="$(. /etc/os-release && echo "${VERSION_ID:-}")"
    if is_ubuntu; then
        umu_target="ubuntu-$(os_codename)"
    else
        umu_target="debian-${version_id%%.*}"
    fi
    url="$(github_asset_url Open-Wine-Components/umu-launcher "python3-umu-launcher_.*_amd64_${umu_target}\.deb$")" || true
    if [ -n "${url:-}" ]; then
        install_deb_url "$url" umu-launcher
    else
        warn "No umu-launcher .deb for ${umu_target}; install it later with: pipx install umu-launcher"
    fi
fi

# GameMode user daemon & group
if ! in_container && ! is_simulate && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user enable --now gamemoded.service 2>/dev/null || true
fi
add_user_group gamemode

log "Gaming stack installation complete."
