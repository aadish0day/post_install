#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEFAULT SHELL & SESSION SERVICES
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

command -v zsh >/dev/null 2>&1 || apt_install zsh

zsh_path="$(command -v zsh || true)"
current_shell="$(getent passwd "$(current_user)" | cut -d: -f7)"

if [ -z "$zsh_path" ]; then
    warn "zsh is not installed, keeping $current_shell"
elif [ "$current_shell" = "$zsh_path" ]; then
    log "zsh is already the default shell."
elif in_container; then
    warn "Container detected, not changing the default shell."
elif is_simulate; then
    log "[simulate] would change default shell to $zsh_path"
elif [ -t 0 ]; then
    log "Changing default shell to zsh..."
    chsh -s "$zsh_path" || warn "chsh failed; run: chsh -s $zsh_path"
else
    log "Changing default shell to zsh (non-interactive)..."
    $SUDO usermod -s "$zsh_path" "$(current_user)" || warn "Could not change shell; run: chsh -s $zsh_path"
fi

# Starship prompt init
if command -v starship >/dev/null 2>&1 && ! is_simulate; then
    append_line_once "$HOME/.zshrc" 'eval "$(starship init zsh)"'
    append_line_once "$HOME/.bashrc" 'eval "$(starship init bash)"'
fi

# Nala as the default apt frontend
if command -v nala >/dev/null 2>&1 && ! is_simulate; then
    append_line_once "$HOME/.zshrc" 'alias apt='\''sudo nala'\'''
    append_line_once "$HOME/.bashrc" 'alias apt='\''sudo nala'\'''
fi

# Start XDG desktop portal user services (socket-activated, so start only)
if ! in_container && ! is_simulate && systemctl --user show-environment >/dev/null 2>&1; then
    for s in xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-kde.service; do
        if systemctl --user list-unit-files "$s" 2>/dev/null | grep -q "$s"; then
            systemctl --user start "$s" 2>/dev/null && log "Started $s" || true
        fi
    done
fi

log "Shell configuration complete."
