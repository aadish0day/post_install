#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SHELL & SESSION SERVICES
# Makes zsh the default shell and starts xdg-desktop-portal user services.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

command -v zsh &>/dev/null || dnf_install zsh
ZSH_PATH="$(command -v zsh || true)"
CURRENT_SHELL="$(getent passwd "$(id -un)" | cut -d: -f7)"

if [ -z "$ZSH_PATH" ]; then
    warn "zsh is not installed, keeping default shell."
elif ! grep -Fxq "$ZSH_PATH" /etc/shells 2>/dev/null; then
    warn "$ZSH_PATH is not listed in /etc/shells; skipping chsh."
elif [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
    log "zsh is already the default shell."
elif in_container; then
    warn "Container detected, not changing the login shell."
elif is_simulate; then
    log "[simulate] would change default shell to $ZSH_PATH"
elif [ ! -t 0 ]; then
    warn "No terminal for the password prompt; run: chsh -s $ZSH_PATH"
else
    log "Changing default shell to zsh..."
    chsh -s "$ZSH_PATH"
    log "Log out and back in for the shell change to take effect."
fi

if command -v starship &>/dev/null; then
    for rc in "$HOME/.zshrc:zsh" "$HOME/.bashrc:bash"; do
        file="${rc%%:*}"
        touch "$file"
        grep -q 'starship init' "$file" || printf '\neval "$(starship init %s)"\n' "${rc##*:}" >>"$file"
    done
fi

if ! in_container; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service; do
        if systemctl --user list-unit-files "$s" &>/dev/null; then
            systemctl --user start "$s" 2>/dev/null || true
        fi
    done
fi

log "Shell configuration complete."
