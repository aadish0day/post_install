#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX TPLMAP INSTALLER & SETUP
# Automatic Server-Side Template Injection (SSTI) detection & testing tool
# Upstream: https://github.com/epinna/tplmap
# ============================================================================

REPO_URL="https://github.com/epinna/tplmap.git"
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

echo "=== Installing tplmap (SSTI Engine) on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

if [ -z "$INSTALL_BASE" ]; then
    INSTALL_DIR="${TARGET_HOME}/tool/tplmap"
else
    INSTALL_DIR="${INSTALL_BASE}/tplmap"
fi

# 2. Clone Git Repository
mkdir -p "$(dirname "$INSTALL_DIR")"
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Existing repository found at $INSTALL_DIR. Pulling updates..."
    git -C "$INSTALL_DIR" pull --ff-only || warn "Pull failed, continuing with existing code."
else
    log "Cloning tplmap into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/tplmap.py" 2>/dev/null || true

# 3. Determine Execution Strategy (Docker vs Python 2)
# Modern Kali (Python 3.14+) deprecated native Python 2.
log "Configuring tplmap launcher wrapper..."

WRAPPER_FILE="/usr/local/bin/tplmap"

if command -v docker &>/dev/null && systemctl is-active --quiet docker 2>/dev/null; then
    log "Docker detected. Creating hybrid container/native wrapper..."
    sudo tee "$WRAPPER_FILE" >/dev/null <<EOF
#!/usr/bin/env bash
if command -v python2 &>/dev/null; then
    exec python2 "$INSTALL_DIR/tplmap.py" "\$@"
elif command -v docker &>/dev/null; then
    exec docker run --rm -it --net=host epinna/tplmap "\$@"
else
    echo "[ERROR] tplmap requires Python 2 or Docker to run on modern Kali Linux." >&2
    exit 1
fi
EOF
else
    log "Creating direct Python launcher wrapper..."
    sudo tee "$WRAPPER_FILE" >/dev/null <<EOF
#!/usr/bin/env bash
if command -v python2 &>/dev/null; then
    exec python2 "$INSTALL_DIR/tplmap.py" "\$@"
elif command -v docker &>/dev/null; then
    exec docker run --rm -it --net=host epinna/tplmap "\$@"
else
    echo "[ERROR] tplmap requires Python 2 or Docker to run on modern Kali Linux." >&2
    echo "Tip: Run 'kali/apps/docker.sh' to enable Docker support, or install python2." >&2
    exit 1
fi
EOF
fi

sudo chmod 0755 "$WRAPPER_FILE"

# 4. Local User Symlink
mkdir -p "$TARGET_HOME/.local/bin"
ln -sf "$WRAPPER_FILE" "$TARGET_HOME/.local/bin/tplmap" 2>/dev/null || true

sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR" 2>/dev/null || true

echo ""
log "tplmap setup complete!"
log "Command available: 'tplmap'"
log "Installed in: $INSTALL_DIR"
log "Example command: tplmap -u \"http://target.com/page?name=John\""
