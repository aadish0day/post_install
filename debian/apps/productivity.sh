#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# PRODUCTIVITY APPS (Debian equivalents of the Arch AUR list in arch/arch.sh)
# Pacstall first, then the upstream .deb, Flathub or pipx.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

failed=()

# try_install NAME CHECK_CMD PACSTALL_PKG FALLBACK_FUNCTION
try_install() {
    local name="$1" check="$2" pkg="$3" fallback="$4"
    log "==> $name"
    if [ -n "$check" ] && command -v "$check" >/dev/null 2>&1; then
        log "$name is already installed."
        return 0
    fi
    if [ -n "$pkg" ] && pacstall_install "$pkg"; then
        return 0
    fi
    if [ -n "$fallback" ]; then
        warn "Falling back for $name..."
        "$fallback" && return 0
    fi
    failed+=("$name")
}

fallback_anicli() {
    apt_install mpv fzf aria2 yt-dlp ffmpeg curl grep sed patch
    if is_simulate; then
        url_ok https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli >/dev/null
        return
    fi
    $SUDO curl -fsSL -o /usr/local/bin/ani-cli https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli
    $SUDO chmod 0755 /usr/local/bin/ani-cli
}

fallback_anydesk() {
    add_apt_repo anydesk https://keys.anydesk.com/repos/DEB-GPG-KEY \
        "deb [signed-by={keyring}] https://deb.anydesk.com all main"
    apt_install anydesk
}

fallback_thorium() {
    # Upstream apt repo (unsigned upstream, hence trusted=yes)
    echo "deb [trusted=yes arch=amd64] https://dl.thorium.rocks/debian/ stable main" |
        $SUDO tee /etc/apt/sources.list.d/thorium.list >/dev/null
    apt_force_update
    apt_install thorium-browser
}

fallback_zen() { flatpak_install app.zen_browser.zen; }

fallback_vesktop() {
    local url
    url="$(github_asset_url Vencord/Vesktop '_amd64\.deb$')" || return 1
    [ -n "$url" ] && install_deb_url "$url" vesktop
}

fallback_obsidian() {
    local url
    url="$(github_asset_url obsidianmd/obsidian-releases '_amd64\.deb$')" || true
    if [ -n "${url:-}" ]; then
        install_deb_url "$url" obsidian
    else
        flatpak_install md.obsidian.Obsidian
    fi
}

install_localsend() {
    local url
    url="$(github_asset_url localsend/localsend 'linux-x86-64\.deb$')" || true
    if [ -n "${url:-}" ]; then
        install_deb_url "$url" localsend
    else
        flatpak_install org.localsend.localsend_app
    fi
}

try_install "ani-cli" ani-cli ani-cli-bin fallback_anicli
try_install "AnyDesk" anydesk anydesk-deb fallback_anydesk
try_install "Thorium Browser" thorium-browser thorium-deb fallback_thorium
try_install "Zen Browser" zen-browser zen-browser-bin fallback_zen
try_install "Vesktop (Discord)" vesktop vesktop-deb fallback_vesktop
try_install "Obsidian" obsidian obsidian-deb fallback_obsidian
try_install "LocalSend" localsend_app "" install_localsend

log "==> gallery-dl & markitdown (pipx)"
pipx_install gallery-dl "markitdown[all]" || failed+=("pipx tools")

log "Note: advcpmv (patched cp/mv with progress bars) has no Debian package; skipped."

if [ "${#failed[@]}" -gt 0 ]; then
    err "Failed to install: ${failed[*]}"
    exit 1
fi
log "Productivity apps installation complete."
