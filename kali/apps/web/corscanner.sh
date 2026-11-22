#!/usr/bin/env bash
set -euo pipefail

# CORScanner: CORS misconfiguration scanner (https://github.com/chenjj/CORScanner)
# Pinned commit, isolated venv, user-owned launcher (no root-owned wrapper).

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
CORSCANNER_REF="${CORSCANNER_REF:-593043f836a158246fc6a13a89a5a1401cbff0b5}"
INSTALL_DIR="$TOOL_BASE/corscanner"

echo "=== Installing CORScanner on Kali Linux ==="
apt_install git python3 python3-pip python3-venv python3-full build-essential
git_checkout_ref "https://github.com/chenjj/CORScanner.git" "$INSTALL_DIR" "$CORSCANNER_REF"
setup_venv "$INSTALL_DIR"

remove_legacy_wrapper corscanner
remove_legacy_wrapper cors
install_user_wrapper corscanner <<WRAP
#!/usr/bin/env bash
exec "$INSTALL_DIR/venv/bin/python3" "$INSTALL_DIR/cors_scan.py" "\$@"
WRAP
run_as_target ln -sf "$USER_BIN/corscanner" "$USER_BIN/cors"
path_hint

log "CORScanner installation complete! Example: corscanner -u https://target.com/api -v"
