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
    # Lutris Wine dependencies (32-bit libs Wine dlopen()s, so not pulled in by the wine package)
    samba-winbind-clients giflib.i686 libpng.i686 libjpeg-turbo.i686 openldap.i686 gnutls.i686
    mpg123-libs.i686 openal-soft.i686 libv4l.i686 pulseaudio-libs.i686 alsa-lib.i686
    libgpg-error.i686 libgcrypt.i686 sqlite-libs.i686 libXcomposite.i686 libXinerama.i686
    ncurses-libs.i686 ocl-icd.i686 libxslt.i686 libva.i686 gtk3.i686 gstreamer1.i686
    sdl2-compat.i686 cups-libs.i686
)

log "Installing gaming packages..."
# de-skew multilib gstreamer (i686/x86_64 must share files at the same version)
$SUDO dnf update -y --refresh gstreamer1-plugins-base &>/dev/null || true
dnf_install --allowerasing "${gaming_packages[@]}"

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
