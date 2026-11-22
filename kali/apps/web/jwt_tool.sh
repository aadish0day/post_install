#!/usr/bin/env bash
set -euo pipefail

# jwt_tool: JWT testing toolkit (https://github.com/ticarpi/jwt_tool)
# Pinned release (v2.3.0), isolated venv, user-owned launchers.
#
# A small compatibility patch (Python 3.14 configparser) is applied to the working
# tree after checkout. git_checkout_ref discards it before every update, so the
# patch never blocks a later upgrade.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
JWT_TOOL_REF="${JWT_TOOL_REF:-3bc7407cf2222d6a821dcc19c776e5a1b1cb9a9b}"
INSTALL_DIR="${JWT_TOOL_DIR:-$TOOL_BASE/jwt_tool}"

echo "=== Installing jwt_tool on Kali Linux ==="
apt_install git python3 python3-pip python3-venv python3-full build-essential libssl-dev libffi-dev curl
git_checkout_ref "https://github.com/ticarpi/jwt_tool.git" "$INSTALL_DIR" "$JWT_TOOL_REF"
setup_venv "$INSTALL_DIR"

log "Applying Python 3.14+ configparser compatibility patch..."
run_as_target "$INSTALL_DIR/venv/bin/python3" - "$INSTALL_DIR/jwt_tool.py" <<'PY'
import re, sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()
    new_code = re.sub(r"'# [^']+': None,?\s*", '', code)
    if new_code != code:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_code)
        print('[INFO] Applied Python 3.14 delimiter fix to jwt_tool.py')
    else:
        print('[INFO] jwt_tool.py needs no patch.')
except Exception as e:
    print(f'[WARN] Could not patch jwt_tool.py: {e}')
PY

# Initialise config + keys. Never delete an existing config: back it up instead.
CONF="$TARGET_HOME/.jwt_tool/jwtconf.ini"
if [ ! -f "$CONF" ] || ! grep -q '\[argvals\]' "$CONF" 2>/dev/null; then
    if [ -f "$CONF" ]; then
        BAK="$CONF.bak.$(date +%s)"
        log "Existing $CONF lacks [argvals]; backing up to $BAK"
        run_as_target mv "$CONF" "$BAK"
    fi
    log "Generating default configuration and keys (~/.jwt_tool/)..."
    run_as_target "$INSTALL_DIR/venv/bin/python3" "$INSTALL_DIR/jwt_tool.py" >/dev/null 2>&1 || true
fi

remove_legacy_wrapper jwt_tool
remove_legacy_wrapper jwt-tool
install_user_wrapper jwt_tool <<WRAP
#!/usr/bin/env bash
exec "$INSTALL_DIR/venv/bin/python3" "$INSTALL_DIR/jwt_tool.py" "\$@"
WRAP
run_as_target ln -sf "$USER_BIN/jwt_tool" "$USER_BIN/jwt-tool"
path_hint

log "jwt_tool installation complete! Installed in: $INSTALL_DIR  (commands: jwt_tool, jwt-tool)"
