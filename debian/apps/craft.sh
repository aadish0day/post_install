#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARTCRAFT SUITE & APPMAN
# Installs AppMan and ArtCraft productivity apps:
#   wordcraft, gridcraft, deckcraft, photocraft, filmcraft
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

if is_simulate; then
    log "[simulate] would install AppMan and ArtCraft apps (wordcraft, gridcraft, deckcraft, photocraft, filmcraft)"
    exit 0
fi

# Install dependencies
log "Installing dependencies for AppMan and ArtCraft apps..."
apt_install curl wget sed grep coreutils
apt_install libfuse2 2>/dev/null || apt_install libfuse2t64 2>/dev/null || true

# Ensure ~/.local/bin exists and is on PATH
mkdir -p "$HOME/.local/bin"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    # shellcheck disable=SC2016
    append_line_once "$rc" 'export PATH="$HOME/.local/bin:$PATH"'
done
case ":$PATH:" in
*":$HOME/.local/bin:"*) ;;
*) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Install AppMan if not already installed
if [ ! -x "$HOME/.local/bin/appman" ]; then
    log "Installing AppMan to $HOME/.local/bin/appman..."
    curl -fsSL https://raw.githubusercontent.com/ivan-hc/AM/main/APP-MANAGER -o "$HOME/.local/bin/appman" && chmod +x "$HOME/.local/bin/appman"
else
    log "AppMan is already installed at $HOME/.local/bin/appman."
fi

# Pre-configure AppMan non-interactively
if [ ! -f "$HOME/.config/appman/appman-config" ]; then
    log "Configuring AppMan installation directory..."
    mkdir -p "$HOME/.config/appman"
    echo "$HOME/Applications" >"$HOME/.config/appman/appman-config"
    mkdir -p "$HOME/Applications"
fi

# Install ArtCraft apps
craft_apps=("wordcraft" "gridcraft" "deckcraft" "photocraft" "filmcraft")
for app in "${craft_apps[@]}"; do
    if [ -x "$HOME/.local/bin/$app" ]; then
        log "$app is already installed at $HOME/.local/bin/$app, skipping."
        continue
    fi
    log "Installing $app..."
    appman_location="$HOME/Applications" "$HOME/.local/bin/appman" -y -i "$app"
done

log "ArtCraft suite installation complete."
