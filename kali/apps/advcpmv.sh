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
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

# 2. Check if already installed
if command -v advcp >/dev/null 2>&1 && command -v advmv >/dev/null 2>&1; then
    log "advcpmv binaries are already installed: $(command -v advcp), $(command -v advmv)"
else
    log "Installing build dependencies for advcpmv..."
    DEPS=(build-essential patch curl xz-utils texinfo)
    if command -v nala &>/dev/null; then
        sudo nala install -y "${DEPS[@]}"
    else
        sudo apt-get update -qq && sudo apt-get install -y "${DEPS[@]}"
    fi

    BUILD_DIR="$(mktemp -d /tmp/advcpmv_build_XXXXXX)"
    trap 'rm -rf "$BUILD_DIR"' EXIT

    log "Downloading upstream advcpmv installer..."
    curl -fsSL https://raw.githubusercontent.com/jarun/advcpmv/master/install.sh -o "$BUILD_DIR/install.sh"

    log "Patching installer for parallel compilation and doc bypass..."
    # shellcheck disable=SC2016
    sed -i 's/^[[:space:]]*make[[:space:]]*$/    touch doc\/*.info 2>\/dev\/null || true\n    make -j$(nproc) src\/cp src\/mv || make -j$(nproc)/' "$BUILD_DIR/install.sh"

    log "Building advcpmv..."
    (cd "$BUILD_DIR" && sh install.sh)

    log "Installing binaries to /usr/local/bin..."
    sudo install -m 0755 "$BUILD_DIR/advcp" /usr/local/bin/advcp
    sudo install -m 0755 "$BUILD_DIR/advmv" /usr/local/bin/advmv

    log "Creating symlinks (cpg, mvg)..."
    sudo ln -sf /usr/local/bin/advcp /usr/local/bin/cpg
    sudo ln -sf /usr/local/bin/advmv /usr/local/bin/mvg
fi

# 3. Locate binaries for aliases
ADVCP_BIN="$(command -v advcp || echo /usr/local/bin/advcp)"
ADVMV_BIN="$(command -v advmv || echo /usr/local/bin/advmv)"

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
