#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX ADVCPMV (Advanced Copy & Move)
# Coreutils cp and mv patched with progress bars.
# Compiles and installs advcp and advmv from upstream source.
# Configures aliases in target user's .zshrc and .bashrc (and dotfiles).
# ============================================================================

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

append_line_once() {
    local file="$1"
    local line="$2"
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    touch "$file"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        printf '%s\n' "$line" >>"$file"
        log "Added '$line' to $file"
    fi
}

echo "=== Installing Advanced Copy & Move (advcpmv) on Kali Linux ==="

# 1. Determine Target User & Home (handles sudo execution)
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

# Pinned upstream commit + patch (advcpmv 1.0 for coreutils 9.12). Override via env.
ADVCPMV_REF="${ADVCPMV_REF:-abd30958c6040a7b4446aa9e2308814cc6d20c9d}"
ADVCPMV_PATCH="${ADVCPMV_PATCH:-advcpmv-1.0-9.12.patch}"

# 2. Find existing install (/usr/local/bin preferred; /usr/bin from older versions of this script)
ADVCP_BIN=""
ADVMV_BIN=""
for d in /usr/local/bin /usr/bin; do
    if [ -x "$d/advcp" ] && [ -x "$d/advmv" ]; then
        ADVCP_BIN="$d/advcp"
        ADVMV_BIN="$d/advmv"
        break
    fi
done

if [ -n "$ADVCP_BIN" ]; then
    log "advcpmv binaries are already installed ($ADVCP_BIN)."
else
    log "Installing build dependencies for advcpmv..."
    DEPS=(build-essential patch curl xz-utils texinfo git)
    if command -v nala &>/dev/null; then
        sudo nala install -y "${DEPS[@]}"
    else
        sudo apt-get update -qq && sudo apt-get install -y "${DEPS[@]}"
    fi

    BUILD_DIR="$(mktemp -d /tmp/advcpmv_build_XXXXXX)"
    trap 'rm -rf "$BUILD_DIR"' EXIT

    log "Fetching upstream advcpmv at pinned commit ${ADVCPMV_REF:0:12}..."
    git init -q "$BUILD_DIR/src"
    git -C "$BUILD_DIR/src" remote add origin https://github.com/jarun/advcpmv.git
    git -C "$BUILD_DIR/src" fetch -q --depth 1 origin "$ADVCPMV_REF"
    git -C "$BUILD_DIR/src" checkout -q FETCH_HEAD
    [ -f "$BUILD_DIR/src/$ADVCPMV_PATCH" ] || {
        error "Patch $ADVCPMV_PATCH not found in upstream repo at $ADVCPMV_REF."
        exit 1
    }

    # Upstream install.sh (POSIX sh) downloads coreutils from ftp.gnu.org over HTTPS, applies the
    # LOCAL patch we pass (no network fetch of the patch from master) and builds cp/mv.
    log "Building advcpmv (this downloads and compiles coreutils)..."
    mkdir -p "$BUILD_DIR/work"
    (cd "$BUILD_DIR/work" && MAKEFLAGS="-j$(nproc)" sh "$BUILD_DIR/src/install.sh" "$BUILD_DIR/src/$ADVCPMV_PATCH")

    log "Installing binaries to /usr/local/bin..."
    sudo install -m 0755 "$BUILD_DIR/work/advcp" /usr/local/bin/advcp
    sudo install -m 0755 "$BUILD_DIR/work/advmv" /usr/local/bin/advmv
    ADVCP_BIN="/usr/local/bin/advcp"
    ADVMV_BIN="/usr/local/bin/advmv"

    log "Creating symlinks (cpg, mvg)..."
    sudo ln -sf /usr/local/bin/advcp /usr/local/bin/cpg
    sudo ln -sf /usr/local/bin/advmv /usr/local/bin/mvg
fi

# 4. Configure Shell Aliases for Target User & Root
log "Configuring shell aliases for user '$TARGET_USER' (home: $TARGET_HOME)..."

RC_FILES=("$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc")
if [ -n "${SUDO_USER:-}" ] && [ "$TARGET_HOME" != "$HOME" ]; then
    RC_FILES+=("$HOME/.zshrc" "$HOME/.bashrc")
fi

for rcfile in "${RC_FILES[@]}"; do
    if [ -f "$rcfile" ] || [ -L "$rcfile" ]; then
        append_line_once "$rcfile" "alias cp='$ADVCP_BIN -g'"
        append_line_once "$rcfile" "alias mv='$ADVMV_BIN -g'"
        if [ -n "${SUDO_USER:-}" ]; then
            chown -h "$TARGET_USER":"$TARGET_USER" "$rcfile" 2>/dev/null || true
        fi
    fi
done

# If dotfile repo exists, also ensure dotfile/zsh/.zshrc has it directly
if [ -d "$TARGET_HOME/dotfile/zsh" ] && [ -f "$TARGET_HOME/dotfile/zsh/.zshrc" ]; then
    append_line_once "$TARGET_HOME/dotfile/zsh/.zshrc" "alias cp='$ADVCP_BIN -g'"
    append_line_once "$TARGET_HOME/dotfile/zsh/.zshrc" "alias mv='$ADVMV_BIN -g'"
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/dotfile/zsh/.zshrc" 2>/dev/null || true
    fi
fi

log "advcpmv installation and configuration complete!"
