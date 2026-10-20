#!/usr/bin/env bash
# Shared system library for post_install suite.
# Provides common logging, environment checks, package and tool helpers.

set -euo pipefail

# ANSI color codes (exported/shared for caller scripts)
# shellcheck disable=SC2034
BOLD='\033[1m'
# shellcheck disable=SC2034
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 1. Logging and output helpers
log()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# 2. Simulation and container checks
is_simulate() {
    [ "${SIMULATE:-0}" = "1" ] || [ "${DRY_RUN_MODE:-false}" = true ]
}

in_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -qa container=lxc /proc/1/environ 2>/dev/null
}

# 3. Network and download utilities
check_network() {
    if is_simulate; then return 0; fi
    if ping -c 1 -W 2 1.1.1.1 &>/dev/null || ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        return 0
    fi
    curl -fsSIL --connect-timeout 3 https://www.google.com &>/dev/null || \
    curl -fsSIL --connect-timeout 3 https://archlinux.org &>/dev/null
}

download() {
    local url="$1"
    local dest="$2"
    if is_simulate; then
        log "[simulate] would download: $url -> $dest"
        return 0
    fi
    curl -fL --retry 3 --connect-timeout 20 -o "$dest" "$url"
}

github_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local json
    json="$(curl -fsSL --retry 3 --connect-timeout 15 "$api_url" 2>/dev/null || true)"
    if [ -n "$json" ]; then
        echo "$json" | grep -oE 'https://github\.com/[^"/]+/[^"/]+/releases/download/[^"]+' | grep -E "$pattern" | head -n1 || true
    fi
}

# 4. Privilege escalation helper
ensure_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    else
        err "Neither sudo nor doas found, and not running as root."
        return 1
    fi
    export SUDO
}
ensure_sudo || true

# 5. Environment configuration helpers
add_path_line() {
    local p="$1"
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$rc" ]; then
            append_line_once "$rc" "export PATH=\"${p}:\$PATH\""
        fi
    done
}

append_line_once() {
    local file="$1"
    local line="$2"
    if is_simulate; then
        log "[simulate] would append to $file: $line"
        return 0
    fi
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    touch "$file"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        printf '%s\n' "$line" >> "$file"
    fi
}

add_user_group() {
    local target_user="${SUDO_USER:-$USER}"
    local grp
    for grp in "$@"; do
        if is_simulate; then
            log "[simulate] would add $target_user to group $grp"
            continue
        fi
        if getent group "$grp" >/dev/null 2>&1; then
            if ! id -nG "$target_user" 2>/dev/null | grep -qw "$grp"; then
                ${SUDO:-sudo} usermod -aG "$grp" "$target_user" 2>/dev/null || true
            fi
        fi
    done
}

enable_service() {
    local svc="$1"
    if is_simulate; then
        log "[simulate] would enable service: $svc"
        return 0
    fi
    if in_container; then
        warn "Running inside container; skipping service enablement for $svc"
        return 0
    fi
    ${SUDO:-sudo} systemctl enable --now "$svc" 2>/dev/null || true
}

# 6. Flatpak management
ensure_flatpak() {
    command -v flatpak &>/dev/null || return 1
    if is_simulate; then
        log "[simulate] would configure flathub remote"
        return 0
    fi
    ${SUDO:-sudo} flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
}

flatpak_install() {
    local app_id="$1"
    if is_simulate; then
        log "[simulate] flatpak install -y flathub $app_id"
        return 0
    fi
    ensure_flatpak || return 1
    ${SUDO:-sudo} flatpak install -y flathub "$app_id"
}

# 7. Python tool managers (uv / pipx)
ensure_uv() {
    command -v uv &>/dev/null && return 0
    if is_simulate; then
        log "[simulate] would install astral-uv"
        return 0
    fi
    log "Installing uv (Fast Python package manager)..."
    local tmp_sh
    tmp_sh="$(mktemp -t uv_install.XXXXXX.sh)"
    curl -LsSf https://astral.sh/uv/install.sh -o "$tmp_sh"
    local sha
    sha="$(sha256sum "$tmp_sh" | awk '{print $1}')"
    log "Downloaded astral-uv installer (sha256: $sha)"
    sh "$tmp_sh"
    rm -f "$tmp_sh"
    add_path_line "$HOME/.cargo/bin"
    add_path_line "$HOME/.local/bin"
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
}

uv_tool_install() {
    local pkg="$1"
    if is_simulate; then
        log "[simulate] uv tool install $pkg"
        return 0
    fi
    ensure_uv
    uv tool install "$pkg"
}

pipx_install() {
    local pkg="$1"
    if is_simulate; then
        log "[simulate] pipx/uv install $pkg"
        return 0
    fi
    if command -v uv &>/dev/null; then
        uv tool install "$pkg"
    elif command -v pipx &>/dev/null; then
        pipx install "$pkg"
    else
        ensure_uv
        uv tool install "$pkg"
    fi
}

# 8. Module execution
run_module() {
    local script="$1"
    shift
    local args=("$@")

    if [[ "$script" != /* ]]; then
        script="${SCRIPT_DIR:-$PWD}/$script"
    fi

    if [ ! -f "$script" ]; then
        err "Script not found: $script"
        return 1
    fi

    local parent_dir
    parent_dir="$(cd "$(dirname "$script")/.." && pwd)"

    if is_simulate; then
        log "[simulate] would run: $script ${args[*]}"
        return 0
    fi

    (
        cd "$parent_dir" || exit 1
        bash "$script" "${args[@]}"
    )
}
