#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX CLAIRVOYANCE INSTALLER & SETUP
# GraphQL Schema Reconstruction via Typo Suggestions (when introspection disabled)
# Upstream: https://github.com/nikitastupin/clairvoyance
# ============================================================================

PACKAGE_NAME="clairvoyance"

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

echo "=== Installing Clairvoyance GraphQL Tool on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

# 2. Check Prerequisites
log "Checking required dependencies (pipx, python3)..."
DEPS=(pipx python3 python3-pip)
MISSING_DEPS=()
for dep in "${DEPS[@]}"; do
    if ! dpkg -s "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log "Installing missing dependencies: ${MISSING_DEPS[*]}..."
    if command -v nala &>/dev/null; then
        sudo nala install -y "${MISSING_DEPS[@]}"
    else
        sudo apt-get update -qq && sudo apt-get install -y "${MISSING_DEPS[@]}"
    fi
fi

# Ensure pipx path
if [ "$TARGET_USER" != "$(whoami)" ]; then
    sudo -u "$TARGET_USER" pipx ensurepath >/dev/null 2>&1 || true
else
    pipx ensurepath >/dev/null 2>&1 || true
fi

# 3. Install Clairvoyance via pipx
log "Installing Clairvoyance via pipx for user '$TARGET_USER'..."
if [ "$TARGET_USER" != "$(whoami)" ]; then
    sudo -u "$TARGET_USER" pipx install "$PACKAGE_NAME" --force
else
    pipx install "$PACKAGE_NAME" --force
fi

PIPX_BIN="$TARGET_HOME/.local/bin/clairvoyance"

# 4. Create Global Wrapper in /usr/local/bin
log "Creating system-wide CLI wrapper (/usr/local/bin/clairvoyance)..."
if [ -f "$PIPX_BIN" ]; then
    sudo ln -sf "$PIPX_BIN" /usr/local/bin/clairvoyance
else
    sudo tee /usr/local/bin/clairvoyance >/dev/null <<EOF
#!/usr/bin/env bash
exec "$TARGET_HOME/.local/share/pipx/venvs/clairvoyance/bin/clairvoyance" "\$@"
EOF
    sudo chmod 0755 /usr/local/bin/clairvoyance
fi

echo ""
log "Clairvoyance installation complete!"
log "Command available everywhere: 'clairvoyance'"
log "Example command: clairvoyance https://target.com/graphql -o schema.json"
