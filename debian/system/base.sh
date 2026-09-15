#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEBIAN / UBUNTU BASE PACKAGES
# Debian equivalent of the Arch base package list (arch/arch.sh), plus CLI
# tools that aren't in apt installed from Pacstall, GitHub releases or pipx.
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# Arch base list mapped to Debian package names
packages=(
    # Android / archives / downloads
    adb fastboot aria2 atool 7zip unzip zip tar xz-utils zstd lz4 dosfstools usbutils
    # Core CLI
    bat duf fastfetch fd-find fzf htop inxi jq less lsd ncdu parallel plocate pv ripgrep sd
    tree trash-cli tmux zoxide zsh man-db manpages manpages-dev neovim git git-lfs gh curl wget
    # Build & dev
    build-essential gcc make gettext libtool doxygen maven nodejs npm python3-pip pipx linux-headers-amd64
    # Media & documents
    mpv mpv-mpris mediainfo ffmpegthumbnailer imagemagick img2pdf jpegoptim highlight yt-dlp obs-studio
    fluidsynth libdca0 libgme0 liblrdf0 libltc11 soundstretch libspandsp2t64 libspandsp2 libchromaprint1 libavtp0
    gstreamer1.0-libav gstreamer1.0-plugins-ugly
    # Audio (PipeWire stack)
    pipewire pipewire-audio pipewire-alsa pipewire-jack pipewire-pulse pipewire-libcamera wireplumber
    # Desktop helpers
    kitty gvfs gvfs-backends gvfs-fuse tumbler playerctl qalculate-gtk qbittorrent papirus-icon-theme
    fonts-cantarell fonts-jetbrains-mono fonts-noto fonts-noto-cjk fonts-noto-color-emoji fonts-noto-extra
    # Extras from the previous Debian setup
    ranger flameshot xclip ueberzug zathura zathura-pdf-poppler zathura-ps zathura-djvu zathura-cb
    alacritty bluez libreoffice
)

# Only needed on Ubuntu kernels
if is_ubuntu; then
    packages=("${packages[@]/linux-headers-amd64/linux-headers-generic}")
fi

log "Installing base packages..."
apt_install "${packages[@]}"

# Debian ships fd as "fdfind" and bat as "batcat": expose the usual names
if ! is_simulate; then
    mkdir -p "$HOME/.local/bin"
    command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1 && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1 && ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi

# Git LFS for the current user
if ! is_simulate && command -v git-lfs >/dev/null 2>&1; then
    log "Initializing Git LFS..."
    git lfs install --skip-repo
fi

# ----------------------------------------------------------------------------
# Tools not packaged in apt
# ----------------------------------------------------------------------------

# Starship prompt: apt (Debian 13+), otherwise Pacstall, otherwise upstream installer
if ! command -v starship >/dev/null 2>&1; then
    if apt_available starship | grep -qx starship; then
        apt_install starship
    elif ! pacstall_install starship-bin; then
        if is_simulate; then
            url_ok https://starship.rs/install.sh >/dev/null
        else
            curl -sS https://starship.rs/install.sh | sh -s -- -y
        fi
    fi
fi

# fastfetch: apt on trixie/plucky+, upstream .deb on bookworm/noble
if ! command -v fastfetch >/dev/null 2>&1 && ! apt_available fastfetch | grep -qx fastfetch; then
    url="$(github_asset_url fastfetch-cli/fastfetch "fastfetch-linux-$(dpkg --print-architecture | sed 's/arm64/aarch64/')\.deb$")" || true
    if [ -n "${url:-}" ]; then
        install_deb_url "$url" fastfetch || warn "fastfetch installation failed"
    else
        warn "Could not resolve the latest fastfetch release."
    fi
fi

# Yazi file manager: Pacstall only has a slow -git build, so use the release binary
install_yazi() {
    local url tmp
    url="$(github_asset_url sxyazi/yazi 'yazi-x86_64-unknown-linux-gnu\.zip$')" || true
    [ -n "$url" ] || {
        warn "Could not resolve latest yazi release."
        return 1
    }
    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would install yazi from $url"
        return 0
    fi
    tmp="$(mktemp -d)"
    download "$url" "$tmp/yazi.zip"
    unzip -q "$tmp/yazi.zip" -d "$tmp"
    $SUDO install -m 0755 "$tmp"/yazi-*/yazi "$tmp"/yazi-*/ya /usr/local/bin/
    rm -rf "$tmp"
    log "Installed yazi $(/usr/local/bin/yazi --version 2>/dev/null | head -n1)"
}

if ! command -v yazi >/dev/null 2>&1; then
    log "Installing yazi..."
    install_yazi || warn "yazi installation failed"
fi

# Python CLI tools (Arch: gallery-dl-bin, markitdown-bin)
log "Installing Python CLI tools with pipx..."
pipx_install gallery-dl "markitdown[all]"

log "Base package installation complete."
