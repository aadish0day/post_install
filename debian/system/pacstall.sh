#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PACSTALL (AUR-like package manager for Debian/Ubuntu)
# https://pacstall.dev
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

if command -v pacstall >/dev/null 2>&1; then
    log "Pacstall is already installed ($(pacstall -V 2>/dev/null | head -n1 | sed 's/\x1b\[[0-9;]*m//g'))."
    exit 0
fi

if is_simulate; then
    url_ok https://pacstall.dev/q/install >/dev/null || die "Pacstall installer not reachable"
    log "[simulate] would install Pacstall"
    exit 0
fi

log "Installing Pacstall..."
# Answer "y" to the installer's only prompt (install axel for faster downloads)
printf 'y\n' | sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)"

command -v pacstall >/dev/null 2>&1 || die "Pacstall installation failed."
log "Pacstall installed. Use 'pacstall -I <package>' to install packages."
