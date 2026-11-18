#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX CORSCANNER INSTALLER & SETUP
# Cross-Origin Resource Sharing (CORS) Misconfiguration Scanner
# Upstream: https://github.com/chenjj/CORScanner
# ============================================================================

REPO_URL="https://github.com/chenjj/CORScanner.git"
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

echo "=== Installing CORScanner on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

if [ -z "$INSTALL_BASE" ]; then
    INSTALL_DIR="${TARGET_HOME}/tool/corscanner"
else
    INSTALL_DIR="${INSTALL_BASE}/corscanner"
fi

# 2. Check Prerequisites (Python venv, git)
log "Checking required system dependencies..."
DEPS=(git python3 python3-pip python3-venv python3-full build-essential)
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

# 3. Clone or Update CORScanner Repository
mkdir -p "$(dirname "$INSTALL_DIR")"
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Existing repository found at $INSTALL_DIR. Pulling updates..."
    git -C "$INSTALL_DIR" pull --ff-only || warn "Pull failed, continuing with existing code."
else
    log "Cloning CORScanner into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 4. Create and Configure Virtual Environment (PEP 668 Compliant)
VENV_DIR="$INSTALL_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    log "Creating Python virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

log "Installing Python dependencies in virtual environment..."
"$VENV_DIR/bin/pip" install --upgrade pip wheel setuptools >/dev/null 2>&1 || true
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 5. Create System-Wide Executable Wrappers
log "Creating system-wide CLI wrappers (/usr/local/bin/cors and /usr/local/bin/corscanner)..."
WRAPPER_FILE="/usr/local/bin/corscanner"
sudo tee "$WRAPPER_FILE" >/dev/null <<EOF
#!/usr/bin/env bash
exec "$VENV_DIR/bin/python3" "$INSTALL_DIR/cors_scan.py" "\$@"
EOF
sudo chmod 0755 "$WRAPPER_FILE"
sudo ln -sf "$WRAPPER_FILE" /usr/local/bin/cors

# 6. Local User Symlinks
mkdir -p "$TARGET_HOME/.local/bin"
ln -sf "$WRAPPER_FILE" "$TARGET_HOME/.local/bin/corscanner" 2>/dev/null || true
ln -sf "$WRAPPER_FILE" "$TARGET_HOME/.local/bin/cors" 2>/dev/null || true

# Set proper ownership
sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR" 2>/dev/null || true

echo ""
log "CORScanner installation complete!"
log "Commands available everywhere: 'cors' and 'corscanner'"
log "Example command: cors -u https://target.com/api -v"
