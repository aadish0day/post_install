#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA BASE PACKAGES
# Fedora equivalent of the Arch base package list (arch/arch.sh + runner).
# Repo packages via dnf (Fedora + RPM Fusion + COPR from system/repos.sh);
# tools without an rpm come from GitHub releases or pipx.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

packages=(
    # CLI essentials
    android-tools aria2 atool bat duf fastfetch fd-find fzf gcc gettext git git-lfs gh
    highlight htop inxi jq less libtool make man-db man-pages maven ncdu neovim nodejs npm
    parallel plocate pv ranger ripgrep tar tree tree-sitter-cli trash-cli tmux
    unzip xz zip zstd lz4 7zip zoxide zsh dosfstools usbutils curl wget ca-certificates
    lsd btop pipx python3-pip kernel-headers kernel-devel
    # Media & documents
    ImageMagick python3-img2pdf jpegoptim mediainfo mpv mpv-mpris ffmpegthumbnailer
    doxygen chromaprint-tools fluidsynth soundtouch spandsp yt-dlp obs-studio
    # Audio (PipeWire)
    pipewire pipewire-alsa pipewire-pulseaudio pipewire-jack-audio-connection-kit
    pipewire-plugin-libcamera wireplumber playerctl
    # Desktop utilities & fonts
    kitty qalculate-qt qbittorrent papirus-icon-theme abattis-cantarell-fonts
    jetbrains-mono-fonts-all google-noto-sans-fonts google-noto-serif-fonts
    google-noto-sans-mono-fonts google-noto-sans-cjk-fonts google-noto-color-emoji-fonts
    gvfs gvfs-afc gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb
)

log "Installing base packages..."
dnf_install "${packages[@]}"

# COPR tools (system/repos.sh), each with a GitHub release fallback
log "Installing starship and yazi (COPR, GitHub fallback)..."
install_pkg_or_github starship starship/starship 'starship-x86_64-unknown-linux-musl\.tar\.gz$' starship
install_pkg_or_github yazi sxyazi/yazi 'yazi-x86_64-unknown-linux-gnu\.zip$' yazi ya
# lazydocker's COPR build is outdated; apps/lazydocker.sh prefers the upstream binary
install_github_binary jesseduffield/lazydocker 'Linux_x86_64\.tar\.gz$' lazydocker

# Tools with no Fedora/COPR package: official GitHub release binaries
log "Installing GitHub release tools (sd, opencode, curl-impersonate)..."
install_github_binary chmln/sd 'x86_64-unknown-linux-musl\.tar\.gz$' sd
install_github_binary anomalyco/opencode 'opencode-linux-x64\.tar\.gz$' opencode
install_github_binary lexiforest/curl-impersonate 'curl-impersonate-v[0-9.]+\.x86_64-linux-gnu\.tar\.gz$' curl-impersonate

# Packages above can pull in ffmpeg-free; make sure the full codec build wins
swap_ffmpeg

# Python CLI tools (AUR gallery-dl-bin / markitdown-bin equivalents)
pipx_install gallery-dl markitdown

if command -v git &>/dev/null && command -v git-lfs &>/dev/null && ! is_simulate; then
    log "Initializing Git LFS..."
    git lfs install --skip-repo
fi

log "Base packages installed."
