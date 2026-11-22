# shellcheck shell=bash
# ============================================================================
# Shared helpers for kali/apps/web/*.sh (sourced; not run directly).
#
# Design rules:
#   - tool code lives under $TOOL_BASE (default ~/cybersec), owned by the user
#   - launchers go in ~/.local/bin (user-owned). We never create root-owned
#     /usr/local/bin wrappers that exec user-writable code (sudo <tool> would
#     otherwise run anything the user can write).
#   - git sources are pinned to a commit; override with <TOOL>_REF=<ref>
# ============================================================================

log() { echo -e "\e[1;34m[INFO]\e[0m $(date '+%H:%M:%S') - $1"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $(date '+%H:%M:%S') - $1" >&2; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $(date '+%H:%M:%S') - $1" >&2; }

# shellcheck disable=SC2034
web_init() {
    TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
    TARGET_HOME="${TARGET_HOME:-$HOME}"
    TOOL_BASE="${TOOL_DIR:-$TARGET_HOME/cybersec}"
    USER_BIN="$TARGET_HOME/.local/bin"
}

# Run a command as the target user (no-op wrapper when already that user)
run_as_target() {
    if [ "$(id -un)" = "$TARGET_USER" ]; then
        "$@"
    else
        sudo -u "$TARGET_USER" "$@"
    fi
}

apt_install() {
    local missing=() p
    for p in "$@"; do
        dpkg -s "$p" &>/dev/null || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] && return 0
    log "Installing missing packages: ${missing[*]}..."
    if command -v nala &>/dev/null; then
        sudo env DEBIAN_FRONTEND=noninteractive nala install -y "${missing[@]}"
    else
        sudo apt-get update -qq
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    fi
}

# True if the package has an installable candidate in the configured repos
apt_has_candidate() {
    local c
    c="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [ -n "$c" ] && [ "$c" != "(none)" ]
}

# Check a file against an expected sha256
verify_sha256() {
    local file="$1" want="$2" got
    got="$(sha256sum "$file" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
        error "Checksum mismatch for $(basename "$file")"
        error "  expected: $want"
        error "  actual:   $got"
        return 1
    fi
}

# git_checkout_ref <url> <dir> <ref>: clone/update <dir> to exactly <ref> (commit or tag).
# Discards local edits to tracked files first (so re-applied patches never block updates).
git_checkout_ref() {
    local url="$1" dir="$2" ref="$3"
    run_as_target mkdir -p "$(dirname "$dir")"
    if [ ! -d "$dir/.git" ]; then
        run_as_target git init -q "$dir"
        run_as_target git -C "$dir" remote add origin "$url"
    fi
    run_as_target git -C "$dir" checkout -q -- . 2>/dev/null || true
    log "Fetching $ref from $url..."
    run_as_target git -C "$dir" fetch -q --depth 1 origin "$ref"
    run_as_target git -C "$dir" checkout -q FETCH_HEAD
}

# Create a python venv in <dir>/venv and install <dir>/requirements.txt
setup_venv() {
    local dir="$1"
    [ -d "$dir/venv" ] || run_as_target python3 -m venv "$dir/venv"
    run_as_target "$dir/venv/bin/pip" install -q --upgrade pip wheel setuptools >/dev/null 2>&1 || true
    if [ -f "$dir/requirements.txt" ]; then
        run_as_target "$dir/venv/bin/pip" install -q -r "$dir/requirements.txt"
    fi
}

# Remove root-owned wrappers/symlinks left in /usr/local/bin by older versions of these scripts
remove_legacy_wrapper() {
    local f="/usr/local/bin/$1"
    if [ -L "$f" ]; then
        case "$(readlink "$f")" in
        "$TARGET_HOME"/*)
            sudo rm -f "$f"
            log "Removed legacy root-owned symlink $f"
            ;;
        esac
    elif [ -f "$f" ] && grep -qF "$TARGET_HOME" "$f" 2>/dev/null; then
        sudo rm -f "$f"
        log "Removed legacy root-owned wrapper $f"
    fi
}

# install_user_wrapper <name>  (script body on stdin) -> ~/.local/bin/<name>, user-owned
install_user_wrapper() {
    local name="$1"
    run_as_target mkdir -p "$USER_BIN"
    run_as_target rm -f "$USER_BIN/$name"
    run_as_target tee "$USER_BIN/$name" >/dev/null
    run_as_target chmod 0755 "$USER_BIN/$name"
}

path_hint() {
    case ":$PATH:" in
    *":$USER_BIN:"*) ;;
    *) warn "$USER_BIN is not in PATH for this shell; open a new terminal or add it to PATH." ;;
    esac
}

# pipx_install_user <spec>
pipx_install_user() {
    apt_install pipx git
    run_as_target pipx ensurepath >/dev/null 2>&1 || true
    log "Installing $1 via pipx for '$TARGET_USER'..."
    run_as_target pipx install --force "$1"
}
