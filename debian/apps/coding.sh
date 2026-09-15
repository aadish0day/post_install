#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEVELOPER TOOLS
# Usage: coding.sh [TOOL...]
#   TOOL: neovim vscode cursor android_studio flutter antigravity
#   (no arguments = all tools)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ALL_TOOLS=(neovim vscode cursor claude_code android_studio flutter antigravity)
tools=("$@")
[ "${#tools[@]}" -gt 0 ] || tools=("${ALL_TOOLS[@]}")

install_neovim() {
    bash "$SCRIPT_DIR/neovim.sh"
}

install_vscode() {
    if command -v code >/dev/null 2>&1; then
        log "VS Code is already installed."
        return 0
    fi
    if pacstall_install vscode-deb; then
        return 0
    fi
    warn "Pacstall vscode-deb failed, using the Microsoft apt repository."
    add_apt_repo vscode https://packages.microsoft.com/keys/microsoft.asc \
        "deb [arch=amd64,arm64,armhf signed-by={keyring}] https://packages.microsoft.com/repos/code stable main"
    echo "code code/add-microsoft-repo boolean false" | $SUDO debconf-set-selections
    apt_install code
}

install_cursor() {
    if command -v cursor >/dev/null 2>&1; then
        log "Cursor is already installed."
        return 0
    fi
    local url
    url="$(url_ok "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest")" ||
        die "Could not resolve the latest Cursor .deb"
    install_deb_url "$url" cursor
}

install_android_studio() {
    if pacstall_installed android-studio || [ -d /opt/android-studio ]; then
        log "Android Studio is already installed."
        return 0
    fi
    apt_install default-jdk libc6:i386 libncurses6:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386
    if ! pacstall_install android-studio; then
        warn "Pacstall android-studio failed, using Flathub instead."
        flatpak_install com.google.AndroidStudio
    fi
}

install_flutter() {
    local dest="$HOME/development/flutter" url
    apt_install curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
    if [ -x "$dest/bin/flutter" ]; then
        log "Flutter is already installed at $dest."
    else
        url="$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json |
            python3 -c 'import json,sys; d=json.load(sys.stdin); h=d["current_release"]["stable"]; r=next(x for x in d["releases"] if x["hash"]==h); print(d["base_url"]+"/"+r["archive"])')"
        [ -n "$url" ] || die "Could not resolve the latest Flutter release."
        if is_simulate; then
            url_ok "$url" >/dev/null && log "[simulate] would extract $url to $dest"
            return 0
        fi
        log "Downloading Flutter SDK..."
        mkdir -p "$HOME/development"
        curl -fL "$url" | tar -xJ -C "$HOME/development"
    fi
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        append_line_once "$rc" 'export PATH="$HOME/development/flutter/bin:$PATH"'
    done
    log "Flutter installed. Run 'flutter doctor' in a new shell."
}

install_antigravity() {
    if pkg_installed antigravity; then
        log "Antigravity is already installed."
        return 0
    fi
    add_apt_repo antigravity https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
        "deb [signed-by={keyring}] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main"
    apt_install antigravity
}

install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code is already installed."
        return 0
    fi
    # Native installer (the npm package is deprecated); installs to ~/.local/bin, no sudo
    if is_simulate; then
        url_ok https://claude.ai/install.sh >/dev/null || die "Claude Code installer not reachable"
        log "[simulate] would install Claude Code with the native installer"
        return 0
    fi
    log "Installing Claude Code (native installer)..."
    curl -fsSL https://claude.ai/install.sh | bash
}

for tool in "${tools[@]}"; do
    case "$tool" in
    neovim) log "==> Neovim" && install_neovim ;;
    vscode) log "==> Visual Studio Code" && install_vscode ;;
    cursor) log "==> Cursor" && install_cursor ;;
    claude_code) log "==> Claude Code" && install_claude_code ;;
    android_studio) log "==> Android Studio" && install_android_studio ;;
    flutter) log "==> Flutter SDK" && install_flutter ;;
    antigravity) log "==> Antigravity" && install_antigravity ;;
    *) warn "Unknown tool: $tool (valid: ${ALL_TOOLS[*]})" ;;
    esac
done

log "Developer tools installation complete."
