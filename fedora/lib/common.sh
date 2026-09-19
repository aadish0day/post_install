#!/usr/bin/env bash
# ============================================================================
# Shared helpers for fedora/ scripts.
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
#
# Environment:
#   SIMULATE=1    resolve packages with `dnf install --assumeno` and only
#                 HEAD-check large downloads (repo setup still runs for real)
#   GITHUB_TOKEN  optional, avoids GitHub API rate limits
# ============================================================================

[ -n "${_POST_INSTALL_FEDORA_LIB:-}" ] && return 0
_POST_INSTALL_FEDORA_LIB=1

SIMULATE="${SIMULATE:-0}"
# shellcheck disable=SC2034 # used by scripts that source this file
FEDORA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\e[1;34m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[WARN]\e[0m %s\n' "$*" >&2; }
err() { printf '\e[1;31m[ERROR]\e[0m %s\n' "$*" >&2; }
die() {
    err "$*"
    exit 1
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

in_container() {
    [ -f /run/.containerenv ] || [ -f /.dockerenv ]
}

is_simulate() {
    [ "$SIMULATE" = "1" ]
}

fedora_release() {
    rpm -E %fedora
}

# ----------------------------------------------------------------------------
# Packages
# ----------------------------------------------------------------------------

# dnf_install [--strict] [--allowerasing ...] PKG...
# Installs what is available and reports anything dnf could not find.
# --strict turns unavailable packages into an error.
dnf_install() {
    local extra=() strict=0
    while [ $# -gt 0 ] && [[ "$1" == --* ]]; do
        if [ "$1" = "--strict" ]; then
            strict=1
        else
            extra+=("$1")
        fi
        shift
    done
    [ $# -eq 0 ] && return 0

    local out rc=0 skipped
    out="$(mktemp)"

    if is_simulate; then
        log "[simulate] dnf install ${*}"
        $SUDO dnf install --assumeno --skip-unavailable "${extra[@]}" "$@" >"$out" 2>&1 || rc=$?
        if grep -qE "Failed to resolve the transaction|^Problem|conflicting requests|nothing provides" "$out"; then
            cat "$out" >&2
            rm -f "$out"
            err "dnf could not resolve the transaction"
            return 1
        fi
        # --assumeno exits 1 after a successful resolve ("Operation aborted")
        if [ "$rc" -ne 0 ] && ! grep -qE "Operation aborted|Nothing to do" "$out"; then
            cat "$out" >&2
            rm -f "$out"
            return "$rc"
        fi
        grep -E "^ Installing:|^ Upgrading:|^ Replacing:|^ Removing:|Nothing to do" "$out" | sed 's/^/    /' || true
    else
        log "dnf install ${*}"
        $SUDO dnf install -y --skip-unavailable "${extra[@]}" "$@" 2>&1 | tee "$out" || rc=$?
        if [ "$rc" -ne 0 ]; then
            rm -f "$out"
            err "dnf install failed (exit $rc)"
            return "$rc"
        fi
    fi

    skipped="$(grep -oE "No match for argument: [^ ]+" "$out" | awk '{print $NF}' | tr '\n' ' ' || true)"
    rm -f "$out"
    if [ -n "$skipped" ]; then
        if [ "$strict" -eq 1 ]; then
            err "Required packages not available: $skipped"
            return 1
        fi
        warn "Not available in enabled repos, skipped: $skipped"
    fi
    return 0
}

# install_rpm_url URL  (dnf resolves the rpm's dependencies)
install_rpm_url() {
    local url="$1"
    if is_simulate; then
        url_check "$url"
        log "[simulate] would install rpm $url"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    log "Downloading $url"
    curl -fSL --retry 3 -o "$tmp/package.rpm" "$url"
    $SUDO dnf install -y "$tmp/package.rpm"
    rm -rf "$tmp"
}

# url_check URL  (fails if the URL is unreachable)
url_check() {
    curl -fsSIL --retry 2 -o /dev/null "$1" || die "URL not reachable: $1"
    log "Reachable: $1"
}

# ----------------------------------------------------------------------------
# Repositories
# ----------------------------------------------------------------------------

# add_repo_file URL [NAME]  (dnf5 dropped `config-manager --add-repo`)
add_repo_file() {
    local url="$1" name="${2:-$(basename "$1")}"
    [[ "$name" == *.repo ]] || name="$name.repo"
    if [ -f "/etc/yum.repos.d/$name" ]; then
        log "Repo $name already present"
        return 0
    fi
    log "Adding repo $name from $url"
    curl -fsSL --retry 3 "$url" | $SUDO tee "/etc/yum.repos.d/$name" >/dev/null
}

# write_repo NAME CONTENT
write_repo() {
    printf '%s\n' "$2" | $SUDO tee "/etc/yum.repos.d/$1.repo" >/dev/null
    log "Wrote /etc/yum.repos.d/$1.repo"
}

ensure_dnf_plugins() {
    rpm -q dnf5-plugins &>/dev/null || rpm -q dnf-plugins-core &>/dev/null ||
        $SUDO dnf install -y dnf5-plugins
}

# copr_enable OWNER/PROJECT
copr_enable() {
    ensure_dnf_plugins
    if dnf repolist 2>/dev/null | grep -q "copr:copr.fedorainfracloud.org:${1/\//:}"; then
        log "COPR $1 already enabled"
        return 0
    fi
    log "Enabling COPR $1"
    $SUDO dnf copr enable -y "$1"
}

rpmfusion_enable() {
    if rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null; then
        log "RPM Fusion already enabled"
        return 0
    fi
    local rel
    rel="$(fedora_release)"
    log "Enabling RPM Fusion free + nonfree"
    $SUDO dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${rel}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${rel}.noarch.rpm"
}

# swap_ffmpeg  Replace Fedora's codec-limited ffmpeg-free with RPM Fusion ffmpeg
swap_ffmpeg() {
    rpmfusion_enable
    if rpm -q ffmpeg &>/dev/null; then
        log "RPM Fusion ffmpeg already installed"
    elif rpm -q ffmpeg-free &>/dev/null; then
        log "Swapping ffmpeg-free for RPM Fusion ffmpeg..."
        if is_simulate; then
            log "[simulate] would run: dnf swap ffmpeg-free ffmpeg --allowerasing"
        else
            $SUDO dnf swap -y ffmpeg-free ffmpeg --allowerasing
        fi
    else
        dnf_install --allowerasing ffmpeg
    fi
}

terra_enable() {
    if rpm -q terra-release &>/dev/null || [ -f /etc/yum.repos.d/terra.repo ]; then
        log "Terra repo already enabled"
        return 0
    fi
    add_repo_file "https://raw.githubusercontent.com/terrapkg/subatomic-repos/main/terra.repo" terra.repo
    # Import the signing key now so later (and --assumeno) transactions can read the repo
    $SUDO rpm --import "https://repos.fyralabs.com/terra$(fedora_release)/key.asc"
}

# ----------------------------------------------------------------------------
# Downloads
# ----------------------------------------------------------------------------

# github_asset_url OWNER/REPO REGEX  -> first matching asset of the latest release
github_asset_url() {
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$1/releases/latest" |
        grep -oE '"browser_download_url": *"[^"]+"' |
        sed -E 's/.*"(https[^"]+)"$/\1/' |
        grep -E "$2" | head -n1 || true
}

# install_github_binary OWNER/REPO ASSET_REGEX BINARY...
# Downloads a .tar.gz/.tar.xz/.zip release asset and installs the named
# binaries (found anywhere in the archive) into /usr/local/bin.
install_github_binary() {
    local repo="$1" regex="$2"
    shift 2
    local bin missing=0
    for bin in "$@"; do
        command -v "$bin" &>/dev/null || missing=1
    done
    if [ "$missing" -eq 0 ]; then
        log "$* already installed"
        return 0
    fi

    local url
    url="$(github_asset_url "$repo" "$regex")"
    [ -n "$url" ] || die "No release asset matching '$regex' in $repo"
    if is_simulate; then
        url_check "$url"
        log "[simulate] would install $* from $url"
        return 0
    fi

    local tmp file
    tmp="$(mktemp -d)"
    log "Downloading $url"
    curl -fSL --retry 3 -o "$tmp/asset" "$url"
    case "$url" in
    *.zip)
        command -v unzip &>/dev/null || $SUDO dnf install -y unzip
        unzip -q "$tmp/asset" -d "$tmp/x"
        ;;
    *) mkdir -p "$tmp/x" && tar -xf "$tmp/asset" -C "$tmp/x" ;;
    esac
    for bin in "$@"; do
        file="$(find "$tmp/x" -type f -name "$bin" | head -n1)"
        [ -n "$file" ] || die "Binary $bin not found in $url"
        $SUDO install -m 0755 "$file" "/usr/local/bin/$bin"
        log "Installed /usr/local/bin/$bin"
    done
    rm -rf "$tmp"
}

# install_pkg_or_github PKG OWNER/REPO ASSET_REGEX BINARY...
# Tries the rpm (e.g. from COPR) in its own transaction; if that fails or the
# binary is still missing, installs the upstream GitHub release binary instead.
install_pkg_or_github() {
    local pkg="$1" repo="$2" regex="$3"
    shift 3
    if command -v "$1" &>/dev/null; then
        log "$1 already installed"
        return 0
    fi
    if dnf_install "$pkg" && { is_simulate || command -v "$1" &>/dev/null; }; then
        return 0
    fi
    warn "$pkg rpm unavailable or failed to download, using GitHub release from $repo"
    install_github_binary "$repo" "$regex" "$@"
}

# ----------------------------------------------------------------------------
# Python CLI Tools (uv tool)
# ----------------------------------------------------------------------------

ensure_uv() {
    if command -v uv &>/dev/null; then
        return 0
    fi
    if dnf_install uv &>/dev/null && command -v uv &>/dev/null; then
        return 0
    fi
    log "Installing uv via official installer..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

# uv_tool_install PACKAGE...  (per-user, into ~/.local/bin)
uv_tool_install() {
    ensure_uv
    local pkg
    for pkg in "$@"; do
        local bin_name="${pkg%%[*}"
        if [ -x "${UV_TOOL_BIN_DIR:-$HOME/.local/bin}/$bin_name" ] && "${UV_TOOL_BIN_DIR:-$HOME/.local/bin}/$bin_name" --version &>/dev/null; then
            log "uv tool $pkg already installed"
        elif is_simulate; then
            curl -fsS -o /dev/null "https://pypi.org/pypi/${bin_name}/json" || die "$pkg not found on PyPI"
            log "[simulate] uv tool $pkg is available on PyPI"
        else
            log "Installing $pkg with uv tool..."
            uv tool install --force "$pkg"
        fi
    done
    add_path_line 'export PATH="$HOME/.local/bin:$PATH"'
}

# Backward compatibility alias
pipx_install() {
    uv_tool_install "$@"
}

# ----------------------------------------------------------------------------
# Flatpak
# ----------------------------------------------------------------------------

ensure_flathub() {
    command -v flatpak &>/dev/null || $SUDO dnf install -y flatpak
    $SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# flatpak_install APP_ID...
flatpak_install() {
    ensure_flathub
    local app
    for app in "$@"; do
        if flatpak info "$app" &>/dev/null; then
            log "Flatpak $app already installed"
        elif is_simulate || in_container; then
            # Flatpak apps need a real session/bwrap; just confirm they exist on Flathub
            flatpak remote-info flathub "$app" >/dev/null || die "Flatpak $app not found on Flathub"
            log "[simulate] flatpak $app is available on Flathub"
        else
            log "Installing flatpak $app"
            $SUDO flatpak install -y --noninteractive flathub "$app"
        fi
    done
}

# ----------------------------------------------------------------------------
# System integration
# ----------------------------------------------------------------------------

# enable_service UNIT [--now]
enable_service() {
    if in_container; then
        warn "Container detected, not enabling $1"
        return 0
    fi
    if systemctl list-unit-files "$1" &>/dev/null; then
        $SUDO systemctl enable ${2:-} "$1" || warn "Could not enable $1"
    else
        warn "Unit $1 not found"
    fi
}

# enable_user_service UNIT
enable_user_service() {
    if in_container; then
        warn "Container detected, not enabling user unit $1"
        return 0
    fi
    systemctl --user enable --now "$1" 2>/dev/null || warn "Could not enable user unit $1"
}

# add_user_group GROUP...
add_user_group() {
    local user group
    user="$(id -un)"
    for group in "$@"; do
        if getent group "$group" &>/dev/null; then
            $SUDO usermod -aG "$group" "$user" && log "Added $user to $group"
        else
            warn "Group $group does not exist, skipping"
        fi
    done
}

# add_path_line LINE  (appends to ~/.zshrc and ~/.bashrc once)
add_path_line() {
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        touch "$rc"
        grep -qxF "$1" "$rc" || printf '\n%s\n' "$1" >>"$rc"
    done
}

# grub_add_args ARG...  (Fedora uses grubby / BLS entries)
grub_add_args() {
    if in_container; then
        warn "Container detected, not changing kernel arguments ($*)"
        return 0
    fi
    command -v grubby &>/dev/null || $SUDO dnf install -y grubby
    $SUDO grubby --update-kernel=ALL --args="$*"
    log "Kernel arguments added: $*"
}
