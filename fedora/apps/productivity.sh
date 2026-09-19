#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA PRODUCTIVITY APPS (Arch AUR list equivalents)
#   ani-cli        GitHub script (+ mpv, fzf, aria2, yt-dlp, ffmpeg deps)
#   anydesk        rpm.anydesk.com repo
#   gallery-dl     pipx      markitdown  pipx
#   localsend      Flathub   zen-browser Flathub   obsidian  Flathub
#   thorium        newest GitHub release that ships an .rpm (AVX2/SSE4/SSE3 build)
#   vesktop        GitHub .rpm
#   advcpmv        skipped (patched coreutils, no Fedora build)
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# ani-cli (Arch: ani-cli)
dnf_install mpv fzf aria2 yt-dlp curl grep sed patch
swap_ffmpeg
if command -v ani-cli &>/dev/null; then
    log "ani-cli already installed"
elif is_simulate; then
    url_check https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli
else
    tmp="$(mktemp)"
    curl -fsSL -o "$tmp" https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli
    $SUDO install -m 0755 "$tmp" /usr/local/bin/ani-cli
    rm -f "$tmp"
    log "Installed /usr/local/bin/ani-cli"
fi

# AnyDesk (Arch: anydesk-bin)
write_repo anydesk "[anydesk]
name=AnyDesk Fedora - stable
baseurl=http://rpm.anydesk.com/rhel/x86_64/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY"
dnf_install anydesk

# Python CLIs (Arch: gallery-dl-bin, markitdown-bin)
uv_tool_install gallery-dl markitdown

# Vesktop Discord client (Arch: vesktop-bin)
if rpm -q vesktop &>/dev/null; then
    log "Vesktop already installed"
else
    url="$(github_asset_url Vencord/Vesktop 'x86_64\.rpm$')"
    [ -n "$url" ] || die "No Vesktop rpm found on GitHub"
    install_rpm_url "$url"
fi

# Thorium browser (Arch: thorium-browser-bin). Recent releases dropped the
# Linux rpms, so pick the newest release that still has one for this CPU.
if rpm -q thorium-browser &>/dev/null; then
    log "Thorium already installed"
else
    variant=SSE3
    grep -qw sse4_2 /proc/cpuinfo && variant=SSE4
    grep -qw avx2 /proc/cpuinfo && variant=AVX2
    auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    url="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/Alex313031/thorium/releases?per_page=50" |
        grep -oE "https://github.com/[^\"]+_${variant}\.rpm" | head -n1 || true)"
    if [ -n "$url" ]; then
        log "Thorium $variant build: $url"
        install_rpm_url "$url"
    else
        warn "No Thorium rpm found on GitHub; skipping."
    fi
fi

# Flathub apps (Arch: localsend-bin, zen-browser-bin, obsidian)
flatpak_install org.localsend.localsend_app app.zen_browser.zen md.obsidian.Obsidian

warn "advcpmv: no Fedora package (patched coreutils); skipped."

log "Productivity apps setup complete."
