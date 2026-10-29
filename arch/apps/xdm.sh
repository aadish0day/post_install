#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX XDM (XTREME DOWNLOAD MANAGER) INSTALLER
# Fetches latest XDM release from GitHub (.pkg.tar.zst) and installs
# via pacman -U, with fallback to AUR (xdman-bin).
# ============================================================================

XDM_REPO="subhra74/xdm"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

if command -v xdman &>/dev/null || command -v xdm-app &>/dev/null || pacman -Qq xdm-app &>/dev/null 2>&1 || pacman -Qq xdman-bin &>/dev/null 2>&1 || [[ -d /opt/xdm-app ]] || [[ -d /opt/xdman ]]; then
    log "XDM is already installed."
    exit 0
fi

# Ensure required dependencies are available
log "Installing dependencies..."
sudo pacman -S --needed --noconfirm curl zstd

aur_cmd=""
if command -v paru &>/dev/null; then
    aur_cmd="paru"
elif command -v yay &>/dev/null; then
    aur_cmd="yay"
fi

BUILD_DIR="$(mktemp -d /tmp/xdm_install_XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

log "Fetching latest XDM release asset from GitHub..."
XDM_URL=$(curl -fsSL "https://api.github.com/repos/${XDM_REPO}/releases/latest" 2>/dev/null | grep -oP '"browser_download_url":\s*"\K[^"]*xdm.*x86_64\.pkg\.tar\.zst' | head -n1 || true)

installed=false

if [[ -n "$XDM_URL" ]]; then
    log "Downloading XDM package from $XDM_URL..."
    PKG_FILE="$BUILD_DIR/$(basename "$XDM_URL")"
    if curl -fSL -o "$PKG_FILE" "$XDM_URL"; then
        log "Installing XDM via pacman -U..."
        if sudo pacman -U --needed --noconfirm "$PKG_FILE"; then
            installed=true
        else
            log "pacman -U failed, will attempt fallback..."
        fi
    fi
fi

if [ "$installed" = false ]; then
    if [ -n "$aur_cmd" ]; then
        log "Attempting installation of xdman-bin from AUR using $aur_cmd..."
        if "$aur_cmd" -S --needed --noconfirm xdman-bin; then
            installed=true
        fi
    fi
fi

if [ "$installed" = false ]; then
    log "ERROR: Failed to install XDM via GitHub release package and AUR fallback."
    exit 1
fi

# Ensure symlink for backward compatibility if binary is xdm-app
if [ -f /opt/xdm-app/bin/xdm-app ] && ! command -v xdman &>/dev/null; then
    sudo ln -sf /opt/xdm-app/bin/xdm-app /usr/local/bin/xdman 2>/dev/null || true
fi

# Ensure autostart desktop entry does not have executable bit set (systemd compliance)
for desk in "$HOME/.config/autostart/xdman.desktop" "$HOME/.config/autostart/xdm-app.desktop"; do
    if [[ -f "$desk" ]]; then
        chmod -x "$desk"
    fi
done

log "XDM installation complete!"
log "You can launch it from your application menu or by running 'xdm-app' / 'xdman'."
