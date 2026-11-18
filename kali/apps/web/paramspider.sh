#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX PARAMSPIDER INSTALLER & SETUP
# URL parameter mining from public web archives (Wayback, Common Crawl, OTX)
# Upstream: https://github.com/devanshbatham/ParamSpider
# ============================================================================

REPO_URL="git+https://github.com/devanshbatham/paramspider.git"

log() {
    echo -e "\e[1;34m[INFO]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\e[1;33m[WARN]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

echo "=== Installing ParamSpider on Kali Linux ==="

# 1. Target User & Paths
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

# 2. Check Prerequisites (pipx & git)
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

# Ensure pipx path is set
if [ "$TARGET_USER" != "$(whoami)" ]; then
    sudo -u "$TARGET_USER" pipx ensurepath >/dev/null 2>&1 || true
else
    pipx ensurepath >/dev/null 2>&1 || true
fi

# 3. Install ParamSpider via pipx (PEP 668 Compliant Isolated Environment)
log "Installing ParamSpider using pipx for user '$TARGET_USER'..."
if [ "$TARGET_USER" != "$(whoami)" ]; then
    sudo -u "$TARGET_USER" pipx install "$REPO_URL" --force
else
    pipx install "$REPO_URL" --force
fi

PIPX_BIN="$TARGET_HOME/.local/bin/paramspider"

# 4. Create Global Wrapper in /usr/local/bin
log "Creating system-wide CLI wrapper (/usr/local/bin/paramspider)..."
if [ -f "$PIPX_BIN" ]; then
    sudo ln -sf "$PIPX_BIN" /usr/local/bin/paramspider
else
    # Fallback wrapper
    sudo tee /usr/local/bin/paramspider >/dev/null <<EOF
#!/usr/bin/env bash
exec "$TARGET_HOME/.local/share/pipx/venvs/paramspider/bin/paramspider" "\$@"
EOF
    sudo chmod 0755 /usr/local/bin/paramspider
fi

echo ""
log "ParamSpider installation complete!"
log "Command available everywhere: 'paramspider'"
log "Example command: paramspider -d example.com --placeholder FUZZ --subs"
log "Results saved to: results/<domain>.txt"
