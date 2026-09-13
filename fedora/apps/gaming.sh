#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA GAMING STACK
# Wine + Winetricks, Lutris, GameMode, MangoHud, Vulkan (64 + 32-bit),
# Steam (RPM Fusion nonfree) and umu-launcher (GitHub .rpm).
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

rpmfusion_enable

gaming_packages=(
    wine winetricks lutris gamemode gamemode.i686 mangohud mangohud.i686 goverlay
    vulkan-tools vulkan-loader vulkan-loader.i686 mesa-vulkan-drivers mesa-vulkan-drivers.i686
    mesa-dri-drivers.i686 gstreamer1-plugins-base gstreamer1-plugins-base.i686
    alsa-plugins-pulseaudio.i686 pipewire-alsa.i686 innoextract python3-protobuf python3-pefile
    steam
)

log "Installing gaming packages..."
dnf_install "${gaming_packages[@]}"

# umu-launcher: unified Proton launcher (Arch: umu-launcher)
if rpm -q umu-launcher &>/dev/null; then
    log "umu-launcher already installed"
else
    rel="$(fedora_release)"
    url="$(github_asset_url Open-Wine-Components/umu-launcher "fc${rel}\.x86_64\.rpm$")"
    [ -n "$url" ] || url="$(github_asset_url Open-Wine-Components/umu-launcher 'fc[0-9]+\.x86_64\.rpm$')"
    [ -n "$url" ] || die "No umu-launcher rpm found on GitHub"
    install_rpm_url "$url"
fi

add_user_group gamemode
enable_user_service gamemoded.service

log "Gaming stack installed. DXVK/VKD3D are managed per-prefix by Lutris and umu/Proton."
