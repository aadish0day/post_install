#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# LAZYDOCKER (terminal UI for Docker)
# Pacstall lazydocker-bin, falling back to the GitHub release binary.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

install_from_github() {
    local raw_arch arch url tmp
    raw_arch="$(uname -m)"
    case "$raw_arch" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="arm64" ;;
    armv7*) arch="armv7" ;;
    *) die "Unsupported architecture: $raw_arch" ;;
    esac

    url="$(github_asset_url jesseduffield/lazydocker "_Linux_${arch}\.tar\.gz$")" || true
    [ -n "$url" ] || die "Could not resolve the latest lazydocker release."

    if is_simulate; then
        url_ok "$url" >/dev/null && log "[simulate] would install lazydocker from $url"
        return 0
    fi

    tmp="$(mktemp -d)"
    download "$url" "$tmp/lazydocker.tar.gz"
    tar -xzf "$tmp/lazydocker.tar.gz" -C "$tmp" lazydocker
    $SUDO install -m 0755 "$tmp/lazydocker" /usr/local/bin/lazydocker
    rm -rf "$tmp"
}

if command -v lazydocker >/dev/null 2>&1; then
    log "lazydocker is already installed: $(lazydocker --version 2>/dev/null | head -n1)"
else
    log "Installing lazydocker..."
    pacstall_install lazydocker-bin || {
        warn "Pacstall install failed, using the GitHub release instead."
        install_from_github
    }
fi

# Shell alias
if ! is_simulate; then
    for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [ -f "$rcfile" ] && append_line_once "$rcfile" "alias lzd='lazydocker'"
    done
fi

if ! command -v docker >/dev/null 2>&1; then
    warn "Docker is not installed. Run debian/apps/docker.sh to use lazydocker."
fi

log "lazydocker setup complete (run: lazydocker or lzd)."
