#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA DEVELOPER TOOLS
# Usage: coding.sh [TOOL...]   TOOL: neovim vscode cursor android_studio flutter antigravity
# (no arguments installs all of them)
#   neovim          dnf
#   vscode          Microsoft yum repo (packages.microsoft.com)
#   cursor          official .rpm from cursor.sh
#   android_studio  Flathub (com.google.AndroidStudio)
#   flutter         official stable tarball -> ~/development/flutter
#   antigravity     Google rpm repo (us-central1-yum.pkg.dev)
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

ALL_TOOLS=(neovim vscode cursor claude_code android_studio flutter antigravity)
TOOLS=("$@")
[ ${#TOOLS[@]} -eq 0 ] && TOOLS=("${ALL_TOOLS[@]}")

install_neovim() {
    dnf_install neovim python3-neovim
}

install_vscode() {
    $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
    write_repo vscode "[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc"
    dnf_install --strict code
}

install_cursor() {
    if rpm -q cursor &>/dev/null; then
        log "Cursor already installed"
        return 0
    fi
    install_rpm_url "https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/latest"
}

install_android_studio() {
    flatpak_install com.google.AndroidStudio
}

install_flutter() {
    local dest="$HOME/development/flutter"
    dnf_install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel mesa-libGLU git curl unzip xz

    if [ -x "$dest/bin/flutter" ]; then
        log "Flutter already installed at $dest"
    else
        local base archive
        # The release index is several MB: parse it from stdin, not argv
        read -r base archive < <(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json |
            python3 -c 'import json,sys; d=json.load(sys.stdin); h=d["current_release"]["stable"]; print(d["base_url"], next(r["archive"] for r in d["releases"] if r["hash"] == h))')
        [ -n "$archive" ] || die "Could not resolve the latest Flutter stable archive"
        if is_simulate; then
            url_check "$base/$archive"
            log "[simulate] would extract $archive into $dest"
        else
            mkdir -p "$HOME/development"
            log "Downloading Flutter stable ($archive)..."
            curl -fSL --retry 3 "$base/$archive" | tar -xJ -C "$HOME/development"
        fi
    fi
    add_path_line 'export PATH="$HOME/development/flutter/bin:$PATH"'
}

install_antigravity() {
    if rpm -q antigravity &>/dev/null; then
        log "Antigravity already installed"
        return 0
    fi
    local base="https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm"
    local key="https://us-central1-yum.pkg.dev/doc/repo-signing-key.gpg"
    local tmp
    tmp="$(mktemp -d)"

    # Google's signing key uses a SHA-1 binding that rpm-sequoia on Fedora 40+
    # rejects ("Bad PGP signature"), so verify the repo metadata with gpg here.
    command -v gpg &>/dev/null || dnf_install gnupg2
    curl -fsSL -o "$tmp/key.gpg" "$key"
    curl -fsSL -o "$tmp/repomd.xml" "$base/repodata/repomd.xml"
    curl -fsSL -o "$tmp/repomd.xml.asc" "$base/repodata/repomd.xml.asc"
    mkdir -m 700 "$tmp/gnupg"
    GNUPGHOME="$tmp/gnupg" gpg -q --import "$tmp/key.gpg" 2>/dev/null
    if ! GNUPGHOME="$tmp/gnupg" gpg -q --verify "$tmp/repomd.xml.asc" "$tmp/repomd.xml" 2>/dev/null; then
        rm -rf "$tmp"
        die "Antigravity repository signature check failed"
    fi
    rm -rf "$tmp"
    log "Antigravity repository metadata signature verified"

    write_repo antigravity "[antigravity-rpm]
name=Antigravity RPM Repository
baseurl=$base
enabled=1
gpgcheck=0
repo_gpgcheck=0"
    dnf_install --strict antigravity
}

install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code is already installed."
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        log "Installing Node.js & npm..."
        dnf_install nodejs npm
    fi
    log "Installing Claude Code via npm..."
    $SUDO npm install -g @anthropic-ai/claude-code
}

for tool in "${TOOLS[@]}"; do
    case "$tool" in
    neovim | vscode | cursor | claude_code | android_studio | flutter | antigravity)
        log "=== $tool ==="
        "install_$tool"
        ;;
    *) warn "Unknown tool '$tool' (valid: ${ALL_TOOLS[*]})" ;;
    esac
done

log "Developer tools setup complete."
