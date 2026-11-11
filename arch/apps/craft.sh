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

# Installs required Arch dependencies
log "Installing dependencies (curl, wget, sed, grep, coreutils, fuse2)..."
sudo pacman -S --needed --noconfirm curl wget sed grep coreutils fuse2

# Ensures $HOME/.local/bin exists and is added to PATH in ~/.bashrc and ~/.zshrc
mkdir -p "$HOME/.local/bin"
# shellcheck disable=SC2016
path_line='export PATH="$HOME/.local/bin:$PATH"'
touch "$HOME/.bashrc"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
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
    # Prefer a tagged release over the moving `main` branch; fall back to main with a warning.
    am_ref="$(curl -fsSL https://api.github.com/repos/ivan-hc/AM/releases/latest 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | head -n1 || true)"
    if [ -z "$am_ref" ]; then
        log "WARN: could not resolve an AppMan release tag; using unpinned main branch."
        am_ref="main"
    fi
    am_tmp="$(mktemp)"
    if curl -fsSL "https://raw.githubusercontent.com/ivan-hc/AM/${am_ref}/APP-MANAGER" -o "$am_tmp" && head -n1 "$am_tmp" | grep -q '^#!'; then
        install -m 755 "$am_tmp" "$HOME/.local/bin/appman"
        log "Installed AppMan ($am_ref)."
    else
        rm -f "$am_tmp"
        log "ERROR: failed to download AppMan ($am_ref)."
        exit 1
    fi
    rm -f "$am_tmp"
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
failed_apps=()
for app in "${craft_apps[@]}"; do
    if [ -x "$HOME/.local/bin/$app" ]; then
        log "$app is already installed at $HOME/.local/bin/$app, skipping."
    else
        log "Installing $app via AppMan..."
        appman_location="$HOME/Applications" "$HOME/.local/bin/appman" -y -i "$app" || {
            log "WARN: failed to install $app; continuing."
            failed_apps+=("$app")
        }
    fi
done

if [ ${#failed_apps[@]} -gt 0 ]; then
    log "ArtCraft finished with failures: ${failed_apps[*]}"
    exit 1
fi
log "ArtCraft Suite installation complete."
