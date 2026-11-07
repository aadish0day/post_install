#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX APPMAN & ARTCRAFT SUITE INSTALLER
# Installs AppMan and the 5 ArtCraft productivity apps:
#   wordcraft, gridcraft, deckcraft, photocraft, filmcraft
# ============================================================================

log() {
    echo "$*"
}

is_simulate() {
    [ "${SIMULATE:-0}" = "1" ] || [ "${DRY_RUN_MODE:-false}" = true ]
}

if is_simulate; then
    log "[simulate] would install AppMan and ArtCraft apps (wordcraft, gridcraft, deckcraft, photocraft, filmcraft)"
    if (return 0 2>/dev/null); then
        return 0
    else
        exit 0
    fi
fi

# Installs required Arch dependencies
log "Installing dependencies (curl, wget, sed, grep, coreutils, fuse2)..."
sudo pacman -S --needed --noconfirm curl wget sed grep coreutils fuse2

# Ensures $HOME/.local/bin exists and is added to PATH in ~/.bashrc and ~/.zshrc
mkdir -p "$HOME/.local/bin"
# shellcheck disable=SC2016
path_line='export PATH="$HOME/.local/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$rc"
    if ! grep -q 'PATH=.*\.local/bin' "$rc"; then
        printf '\n%s\n' "$path_line" >>"$rc"
    fi
done
case ":$PATH:" in
*":$HOME/.local/bin:"*) ;;
*) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Installs AppMan to $HOME/.local/bin/appman if not already installed
if [ ! -x "$HOME/.local/bin/appman" ]; then
    log "Installing AppMan..."
    curl -fsSL https://raw.githubusercontent.com/ivan-hc/AM/main/APP-MANAGER -o "$HOME/.local/bin/appman" && chmod +x "$HOME/.local/bin/appman"
else
    log "AppMan is already installed at $HOME/.local/bin/appman"
fi

# Pre-configures AppMan non-interactively if $HOME/.config/appman/appman-config does not exist
if [ ! -f "$HOME/.config/appman/appman-config" ]; then
    log "Pre-configuring AppMan installation directory..."
    mkdir -p "$HOME/.config/appman"
    echo "$HOME/Applications" >"$HOME/.config/appman/appman-config"
    mkdir -p "$HOME/Applications"
fi

# Loops over the 5 craft apps
craft_apps=(wordcraft gridcraft deckcraft photocraft filmcraft)
for app in "${craft_apps[@]}"; do
    if [ -x "$HOME/.local/bin/$app" ]; then
        log "$app is already installed at $HOME/.local/bin/$app, skipping."
    else
        log "Installing $app via AppMan..."
        appman_location="$HOME/Applications" "$HOME/.local/bin/appman" -y -i "$app"
    fi
done

log "ArtCraft Suite installation complete."
