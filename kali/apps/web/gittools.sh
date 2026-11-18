#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX GITTOOLS INSTALLER & SETUP
# Reconstruct exposed .git directories and extract commit source trees
# Upstream: https://github.com/internetwache/GitTools
# ============================================================================

REPO_URL="https://github.com/internetwache/GitTools.git"
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

echo "=== Installing GitTools Suite on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

if [ -z "$INSTALL_BASE" ]; then
    INSTALL_DIR="${TARGET_HOME}/tool/GitTools"
else
    INSTALL_DIR="${INSTALL_BASE}/GitTools"
fi

# 2. Check Prerequisites
log "Checking required dependencies (git, bash, curl, python3)..."
DEPS=(git bash curl python3)
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

# 3. Clone or Update GitTools
mkdir -p "$(dirname "$INSTALL_DIR")"
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Existing GitTools repository found at $INSTALL_DIR. Pulling updates..."
    git -C "$INSTALL_DIR" pull --ff-only || warn "Pull failed, continuing with existing code."
else
    log "Cloning GitTools into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/Dumper/gitdumper.sh" 2>/dev/null || true
chmod +x "$INSTALL_DIR/Extractor/extractor.sh" 2>/dev/null || true

# 4. Create Global Executable Wrappers in /usr/local/bin
log "Creating system-wide CLI wrappers..."

sudo tee /usr/local/bin/gitdumper >/dev/null <<EOF
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/Dumper/gitdumper.sh" "\$@"
EOF
sudo chmod 0755 /usr/local/bin/gitdumper

sudo tee /usr/local/bin/gitextractor >/dev/null <<EOF
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/Extractor/extractor.sh" "\$@"
EOF
sudo chmod 0755 /usr/local/bin/gitextractor

sudo tee /usr/local/bin/gitfinder >/dev/null <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_DIR/Finder/gitfinder.py" "\$@"
EOF
sudo chmod 0755 /usr/local/bin/gitfinder

# 5. Local User Symlinks
mkdir -p "$TARGET_HOME/.local/bin"
ln -sf /usr/local/bin/gitdumper "$TARGET_HOME/.local/bin/gitdumper" 2>/dev/null || true
ln -sf /usr/local/bin/gitextractor "$TARGET_HOME/.local/bin/gitextractor" 2>/dev/null || true
ln -sf /usr/local/bin/gitfinder "$TARGET_HOME/.local/bin/gitfinder" 2>/dev/null || true

# Set ownership
sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR" 2>/dev/null || true

echo ""
log "GitTools installation complete!"
log "Available commands:"
log "  1. gitdumper <URL> <dest-dir>       (Downloads exposed .git folder)"
log "  2. gitextractor <git-dir> <out-dir> (Extracts source code from .git)"
log "  3. gitfinder -i <targets.txt>       (Finds exposed .git repositories)"
