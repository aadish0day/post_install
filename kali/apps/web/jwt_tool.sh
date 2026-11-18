#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# KALI LINUX JWT_TOOL INSTALLER & SETUP
# Toolkit for testing, tweaking, and cracking JSON Web Tokens (JWTs).
# Upstream: https://github.com/ticarpi/jwt_tool
# ============================================================================

REPO_URL="https://github.com/ticarpi/jwt_tool.git"

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

echo "=== Installing and Setting up jwt_tool on Kali Linux ==="

# 1. Determine Target User & Home (handles sudo execution)
TARGET_USER="${SUDO_USER:-${USER:-$(whoami)}}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")
TARGET_HOME="${TARGET_HOME:-$HOME}"

INSTALL_DIR="${JWT_TOOL_DIR:-${TARGET_HOME}/tool/jwt_tool}"

# 2. Install Required System Dependencies
log "Installing required system packages (Python, venv, Git)..."
DEPS=(git python3 python3-pip python3-venv python3-full build-essential libssl-dev libffi-dev curl)
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

# 3. Clone or Update jwt_tool Repository
mkdir -p "$(dirname "$INSTALL_DIR")"

if [ -d "$INSTALL_DIR/.git" ]; then
    log "Existing repository found at $INSTALL_DIR. Pulling latest updates..."
    git -C "$INSTALL_DIR" pull --ff-only || warn "Failed to pull updates, proceeding with existing code."
else
    log "Cloning jwt_tool into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 4. Create and Configure Python Virtual Environment (PEP 668 Compliant)
VENV_DIR="$INSTALL_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    log "Creating Python virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

log "Installing/Updating Python requirements in virtual environment..."
"$VENV_DIR/bin/pip" install --upgrade pip wheel setuptools >/dev/null 2>&1 || true
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 5. Apply Python 3.14+ Compatibility Patch (configparser InvalidWriteError)
log "Checking and applying Python 3.14+ configparser patch to jwt_tool.py..."
"$VENV_DIR/bin/python3" -c "
import re
path = '$INSTALL_DIR/jwt_tool.py'
try:
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()
    new_code = re.sub(r\"'# [^']+': None,?\s*\", '', code)
    if new_code != code:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_code)
        print('[INFO] Applied Python 3.14 delimiter fix to jwt_tool.py')
    else:
        print('[INFO] jwt_tool.py is already patched or up-to-date.')
except Exception as e:
    print(f'[WARN] Could not patch jwt_tool.py: {e}')
"

# 6. Initialize jwtconf.ini & Cryptographic Keys
log "Verifying initial jwt_tool configuration..."
if [ ! -f "$TARGET_HOME/.jwt_tool/jwtconf.ini" ] || ! grep -q '\[argvals\]' "$TARGET_HOME/.jwt_tool/jwtconf.ini" 2>/dev/null; then
    log "Generating default configuration and crypto keys (~/.jwt_tool/jwtconf.ini)..."
    rm -f "$TARGET_HOME/.jwt_tool/jwtconf.ini" 2>/dev/null || true
    if [ "$TARGET_USER" != "$(whoami)" ]; then
        sudo -u "$TARGET_USER" "$VENV_DIR/bin/python3" "$INSTALL_DIR/jwt_tool.py" >/dev/null 2>&1 || true
    else
        "$VENV_DIR/bin/python3" "$INSTALL_DIR/jwt_tool.py" >/dev/null 2>&1 || true
    fi
fi

# 7. Create Global Executable Wrappers in /usr/local/bin
log "Creating system-wide CLI wrappers (/usr/local/bin/jwt_tool and /usr/local/bin/jwt-tool)..."
WRAPPER_FILE="/usr/local/bin/jwt_tool"
sudo tee "$WRAPPER_FILE" >/dev/null <<EOF
#!/usr/bin/env bash
exec "$VENV_DIR/bin/python3" "$INSTALL_DIR/jwt_tool.py" "\$@"
EOF
sudo chmod 0755 "$WRAPPER_FILE"
sudo ln -sf "$WRAPPER_FILE" /usr/local/bin/jwt-tool

# Local user bin symlinks
mkdir -p "$TARGET_HOME/.local/bin"
ln -sf "$WRAPPER_FILE" "$TARGET_HOME/.local/bin/jwt_tool" 2>/dev/null || true
ln -sf "$WRAPPER_FILE" "$TARGET_HOME/.local/bin/jwt-tool" 2>/dev/null || true

# 8. Set up Shell Aliases (in case ~/.local/bin is not in PATH)
log "Configuring shell aliases for user '$TARGET_USER'..."
RC_FILES=("$TARGET_HOME/.zshrc" "$TARGET_HOME/.bashrc")
if [ -n "${SUDO_USER:-}" ] && [ "$TARGET_HOME" != "$HOME" ]; then
    RC_FILES+=("$HOME/.zshrc" "$HOME/.bashrc")
fi

for rcfile in "${RC_FILES[@]}"; do
    if [ -f "$rcfile" ] || [ -L "$rcfile" ]; then
        append_line_once "$rcfile" "alias jwt_tool='$WRAPPER_FILE'"
        append_line_once "$rcfile" "alias jwt-tool='$WRAPPER_FILE'"
        if [ -n "${SUDO_USER:-}" ]; then
            chown -h "$TARGET_USER":"$TARGET_USER" "$rcfile" 2>/dev/null || true
        fi
    fi
done

# If dotfiles repo exists, ensure dotfile/zsh/.zshrc is also updated
if [ -d "$TARGET_HOME/dotfile/zsh" ] && [ -f "$TARGET_HOME/dotfile/zsh/.zshrc" ]; then
    append_line_once "$TARGET_HOME/dotfile/zsh/.zshrc" "alias jwt_tool='$WRAPPER_FILE'"
    append_line_once "$TARGET_HOME/dotfile/zsh/.zshrc" "alias jwt-tool='$WRAPPER_FILE'"
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME/dotfile/zsh/.zshrc" 2>/dev/null || true
    fi
fi

# 9. Set Proper File Ownership
log "Ensuring correct permissions for $TARGET_USER..."
sudo chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR" 2>/dev/null || true
if [ -d "$TARGET_HOME/.jwt_tool" ]; then
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.jwt_tool" 2>/dev/null || true
fi

echo ""
log "jwt_tool installation and setup complete!"
log "Installed in: $INSTALL_DIR"
log "CLI Commands available everywhere:"
log "  jwt_tool [args]"
log "  jwt-tool [args]"
log "Example test: jwt_tool -h"
