#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX GHAURI INSTALLER & SETUP
# Advanced cross-platform SQL injection detection & exploitation engine
# Upstream: https://github.com/r0oth3x49/ghauri
# ============================================================================

REPO_URL="git+https://github.com/r0oth3x49/ghauri.git"

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

echo "=== Installing Ghauri on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

# 2. Check Prerequisites
log "Checking required dependencies (pipx, git, python3)..."
DEPS=(pipx git python3 python3-pip)
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

# 3. Install Ghauri via pipx
log "Installing Ghauri via pipx for user '$TARGET_USER'..."
if [ "$TARGET_USER" != "$(whoami)" ]; then
    sudo -u "$TARGET_USER" pipx install "$REPO_URL" --force
else
    pipx install "$REPO_URL" --force
fi

PIPX_BIN="$TARGET_HOME/.local/bin/ghauri"

# 4. Create Global Wrapper in /usr/local/bin
log "Creating system-wide CLI wrapper (/usr/local/bin/ghauri)..."
if [ -f "$PIPX_BIN" ]; then
    sudo ln -sf "$PIPX_BIN" /usr/local/bin/ghauri
else
    sudo tee /usr/local/bin/ghauri >/dev/null <<EOF
#!/usr/bin/env bash
exec "$TARGET_HOME/.local/share/pipx/venvs/ghauri/bin/ghauri" "\$@"
EOF
    sudo chmod 0755 /usr/local/bin/ghauri
fi

echo ""
log "Ghauri installation complete!"
log "Command available everywhere: 'ghauri'"
log "Example command: ghauri -u \"http://target.com/item?id=1\" --dbs --batch"
