#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA LAZYDOCKER (terminal UI for Docker / Compose)
# Upstream GitHub release binary (COPR atim/lazydocker is several releases
# behind), with the COPR package as a fallback.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v lazydocker &>/dev/null; then
    log "lazydocker is already installed: $(lazydocker --version | head -n1)"
else
    if ! (install_github_binary jesseduffield/lazydocker 'Linux_x86_64\.tar\.gz$' lazydocker); then
        warn "GitHub download failed, trying COPR atim/lazydocker"
        copr_enable atim/lazydocker
        dnf_install lazydocker
    fi
fi

# Handy alias, like the Debian/Kali installers
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    touch "$rc"
    grep -q "alias lzd=" "$rc" || printf "\n# Lazydocker alias\nalias lzd='lazydocker'\n" >>"$rc"
done

command -v docker &>/dev/null || warn "Docker is not installed; run fedora/apps/docker.sh to use lazydocker."
log "lazydocker setup complete (run: lazydocker or lzd)."
