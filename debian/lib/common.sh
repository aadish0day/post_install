#!/usr/bin/env bash
# ============================================================================
# Shared helpers for debian/ scripts.
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
#
# Environment:
#   SIMULATE=1    resolve packages with `apt-get -s`, set up repos for real,
#                 only HEAD-check large downloads (used for testing)
#   GITHUB_TOKEN  optional token for GitHub API requests (avoids rate limits)
# ============================================================================

[ -n "${_POST_INSTALL_DEBIAN_LIB:-}" ] && return 0
_POST_INSTALL_DEBIAN_LIB=1

SIMULATE="${SIMULATE:-0}"
export DEBIAN_FRONTEND=noninteractive

log() { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m %s\n' "$*" >&2; }
err() { printf '\e[1;31m[ERROR]\e[0m %s\n' "$*" >&2; }
die() {
    err "$*"
    exit 1
}

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

is_simulate() { [ "$SIMULATE" = "1" ]; }

in_container() {
    [ -f /run/.containerenv ] || [ -f /.dockerenv ]
}

current_user() {
    id -un
}

is_ubuntu() {
    local id="" id_like=""
    # shellcheck disable=SC1091
    id="$(. /etc/os-release && echo "${ID:-}")"
    # shellcheck disable=SC1091
    id_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    [ "$id" = "ubuntu" ] || [[ " $id_like " == *" ubuntu "* ]]
}

os_codename() {
    # shellcheck disable=SC1091
    . /etc/os-release && echo "${VERSION_CODENAME:-}"
}

# Download helper: download URL DEST
download() {
    curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"
}

# HEAD-check a URL (follows redirects). Prints the effective URL.
url_ok() {
    curl -fsSIL --retry 2 --connect-timeout 20 -o /dev/null -w '%{url_effective}\n' "$1"
}

# ----------------------------------------------------------------------------
# APT
# ----------------------------------------------------------------------------
_APT_UPDATED=0

apt_update() {
    if [ "$_APT_UPDATED" = "0" ]; then
        log "Updating apt package lists..."
        $SUDO apt-get update -qq
        _APT_UPDATED=1
    fi
}

apt_force_update() {
    _APT_UPDATED=0
    apt_update
}

# Print the subset of the given packages that have an install candidate.
apt_available() {
    apt-cache policy "$@" 2>/dev/null | awk '
        /^[^ \t].*:$/ { pkg = substr($0, 1, length($0) - 1) }
        /^[ \t]+Candidate:/ { if ($2 != "(none)") print pkg }
    '
}

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# apt_install PKG... : install packages that exist, warn about the rest.
apt_install() {
    [ "$#" -gt 0 ] || return 0
    apt_update

    local avail_list p
    local -a pkgs=() missing=()
    avail_list="$(apt_available "$@")"
    for p in "$@"; do
        if grep -qxF -- "$p" <<<"$avail_list"; then
            pkgs+=("$p")
        else
            missing+=("$p")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        warn "Not available in configured apt repos, skipping: ${missing[*]}"
    fi
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    if is_simulate; then
        local out
        log "[simulate] apt-get install ${#pkgs[@]} packages"
        if ! out="$(apt-get -s install -y "${pkgs[@]}" 2>&1)"; then
            printf '%s\n' "$out" | tail -n 25 >&2
            err "apt-get simulation failed"
            return 1
        fi
        log "[simulate] OK: $(grep -c '^Inst ' <<<"$out" || true) packages would be installed"
        return 0
    fi

    log "Installing ${#pkgs[@]} packages with apt..."
    $SUDO apt-get install -y "${pkgs[@]}"
}

# install_deb_url URL [NAME] : download a .deb and install it with dependencies.
install_deb_url() {
    local url="$1" name="${2:-package}" tmp
    if is_simulate; then
        log "[simulate] would install $name from $url"
        url_ok "$url" >/dev/null || {
            err "URL not reachable: $url"
            return 1
        }
        return 0
    fi
    tmp="$(mktemp -d)"
    log "Downloading $name..."
    download "$url" "$tmp/pkg.deb" || {
        rm -rf "$tmp"
        return 1
    }
    chmod 644 "$tmp/pkg.deb"
    chmod 755 "$tmp"
    apt_update
    if ! $SUDO apt-get install -y "$tmp/pkg.deb"; then
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
}

# add_apt_repo NAME KEY_URL "deb [signed-by={keyring}] URL SUITE COMPONENTS"
add_apt_repo() {
    local name="$1" key_url="$2" line="$3"
    local keyring="/etc/apt/keyrings/${name}.gpg" tmp
    command -v gpg >/dev/null 2>&1 || {
        _APT_UPDATED=0
        apt_update
        $SUDO apt-get install -y gnupg
    }
    $SUDO install -m 0755 -d /etc/apt/keyrings
    tmp="$(mktemp)"
    download "$key_url" "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    if grep -q "BEGIN PGP" "$tmp"; then
        gpg --dearmor <"$tmp" | $SUDO tee "$keyring" >/dev/null
    else
        $SUDO install -m 0644 "$tmp" "$keyring"
    fi
    $SUDO chmod 0644 "$keyring"
    rm -f "$tmp"
    echo "${line//\{keyring\}/$keyring}" | $SUDO tee "/etc/apt/sources.list.d/${name}.list" >/dev/null
    log "Added apt repository: $name"
    _APT_UPDATED=0
}

# ----------------------------------------------------------------------------
# GitHub releases
# ----------------------------------------------------------------------------
# github_asset_url OWNER/REPO REGEX : print the first latest-release asset URL matching REGEX
github_asset_url() {
    local repo="$1" regex="$2" json
    local -a auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    json="$(curl -fsSL --retry 2 "${auth[@]}" -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${repo}/releases/latest")" || return 1
    grep -oE '"browser_download_url": *"[^"]+"' <<<"$json" |
        sed -E 's/.*"(https[^"]+)"$/\1/' | grep -E -- "$regex" | head -n1
}

# ----------------------------------------------------------------------------
# Flatpak
# ----------------------------------------------------------------------------
ensure_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        if is_simulate; then
            apt_install flatpak
            return 0
        fi
        apt_update
        $SUDO apt-get install -y flatpak
    fi
    command -v flatpak >/dev/null 2>&1 || return 0
    $SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# flatpak_install APP_ID...
flatpak_install() {
    ensure_flatpak
    local app
    for app in "$@"; do
        if is_simulate; then
            if command -v flatpak >/dev/null 2>&1; then
                flatpak remote-info flathub "$app" >/dev/null || {
                    err "Flatpak $app not found on Flathub"
                    return 1
                }
            else
                url_ok "https://flathub.org/apps/$app" >/dev/null || return 1
            fi
            log "[simulate] would install flatpak $app"
            continue
        fi
        log "Installing flatpak $app..."
        $SUDO flatpak install -y --noninteractive flathub "$app"
    done
}

# ----------------------------------------------------------------------------
# Pacstall
# ----------------------------------------------------------------------------
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ensure_pacstall() {
    command -v pacstall >/dev/null 2>&1 && return 0
    bash "$_LIB_DIR/../system/pacstall.sh"
    command -v pacstall >/dev/null 2>&1
}

_PACSTALL_INDEX=""
pacstall_exists() {
    if [ -z "$_PACSTALL_INDEX" ]; then
        _PACSTALL_INDEX="$(curl -fsSL --retry 2 https://pacstall.dev/api/repology 2>/dev/null |
            grep -oE '"name":"[^"]+"' | cut -d'"' -f4)" || true
    fi
    if [ -n "$_PACSTALL_INDEX" ]; then
        grep -qxF -- "$1" <<<"$_PACSTALL_INDEX"
    else
        pacstall -S "$1" 2>/dev/null | grep -q -- "$1"
    fi
}

pacstall_installed() {
    [ -f "/var/lib/pacstall/metadata/$1" ]
}

# pacstall_install PKG... : returns nonzero if any package failed so callers can fall back
pacstall_install() {
    local pkg rc=0
    for pkg in "$@"; do
        if pacstall_installed "$pkg"; then
            log "Pacstall package $pkg is already installed."
            continue
        fi
        if ! pacstall_exists "$pkg"; then
            warn "Pacstall package $pkg does not exist."
            rc=1
            continue
        fi
        if is_simulate; then
            log "[simulate] would install Pacstall package $pkg"
            continue
        fi
        ensure_pacstall || {
            warn "Pacstall is not available."
            return 1
        }
        log "Installing $pkg with Pacstall..."
        if ! pacstall -I "$pkg" -P </dev/null; then
            warn "Pacstall failed to install $pkg"
            rc=1
        fi
    done
    return $rc
}

# ----------------------------------------------------------------------------
# pipx
# ----------------------------------------------------------------------------
pipx_install() {
    command -v pipx >/dev/null 2>&1 || apt_install pipx
    local pkg name
    for pkg in "$@"; do
        name="${pkg%%[*}"
        if is_simulate; then
            url_ok "https://pypi.org/pypi/$name/json" >/dev/null || {
                err "PyPI package $name not found"
                return 1
            }
            log "[simulate] would pipx install $pkg"
            continue
        fi
        if pipx list --short 2>/dev/null | grep -q "^$name "; then
            log "$pkg already installed with pipx."
        else
            log "Installing $pkg with pipx..."
            pipx install "$pkg"
        fi
    done
    pipx ensurepath >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
# System integration
# ----------------------------------------------------------------------------
# enable_service UNIT [--now]
enable_service() {
    local unit="$1"
    shift || true
    if in_container; then
        warn "Container detected, not enabling $unit"
        return 0
    fi
    if is_simulate; then
        log "[simulate] would enable $unit"
        return 0
    fi
    $SUDO systemctl enable "$@" "$unit" || warn "Could not enable $unit"
}

# add_user_group GROUP [USER]
add_user_group() {
    local group="$1" user="${2:-$(current_user)}"
    [ "$user" = "root" ] && return 0
    if ! getent group "$group" >/dev/null; then
        warn "Group $group does not exist, skipping."
        return 0
    fi
    if is_simulate; then
        log "[simulate] would add $user to $group"
        return 0
    fi
    $SUDO usermod -aG "$group" "$user"
    log "Added $user to group $group"
}

# append_line_once FILE LINE
append_line_once() {
    local file="$1" line="$2"
    touch "$file"
    grep -qxF -- "$line" "$file" || printf '\n%s\n' "$line" >>"$file"
}
