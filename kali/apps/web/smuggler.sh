#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX SMUGGLER INSTALLER & SETUP
# HTTP Request Smuggling and Desynchronization Testing Suite
# Upstream: https://github.com/defparam/smuggler
# ============================================================================

REPO_URL="https://github.com/defparam/smuggler.git"
INSTALL_BASE="${TOOL_DIR:-}"

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

echo "=== Installing Smuggler on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

if [ -z "$INSTALL_BASE" ]; then
    INSTALL_DIR="${TARGET_HOME}/tool/smuggler"
else
    INSTALL_DIR="${INSTALL_BASE}/smuggler"
fi

# 2. Check Prerequisites
log "Checking required dependencies (git, python3)..."
DEPS=(git python3)
MISSING_DEPS=()
for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
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

# 3. Clone or Update Smuggler
mkdir -p "$(dirname "$INSTALL_DIR")"
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Existing Smuggler repository found at $INSTALL_DIR. Pulling updates..."
    git -C "$INSTALL_DIR" pull --ff-only || warn "Pull failed, continuing with existing code."
else
    log "Cloning Smuggler into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 4. Create Global Wrapper in /usr/local/bin
log "Creating system-wide CLI wrapper (/usr/local/bin/smuggler)..."
sudo tee /usr/local/bin/smuggler >/dev/null <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_DIR/smuggler.py" "\$@"
EOF
sudo chmod 0755 /usr/local/bin/smuggler

# 5. Local User Symlink
mkdir -p "$TARGET_HOME/.local/bin"
ln -sf /usr/local/bin/smuggler "$TARGET_HOME/.local/bin/smuggler" 2>/dev/null || true

# Set ownership
sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR" 2>/dev/null || true

echo ""
log "Smuggler installation complete!"
log "Command available: 'smuggler'"
log "Example scan: smuggler -u https://target.com/"
