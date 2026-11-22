#!/usr/bin/env bash
set -euo pipefail

# Smuggler: HTTP request smuggling / desync testing (https://github.com/defparam/smuggler)
# Pinned commit, user-owned launcher.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
SMUGGLER_REF="${SMUGGLER_REF:-2be871e6151ce85167a277fab21c74c851d8b20b}"
INSTALL_DIR="$TOOL_BASE/smuggler"

echo "=== Installing Smuggler on Kali Linux ==="
apt_install git python3
git_checkout_ref "https://github.com/defparam/smuggler.git" "$INSTALL_DIR" "$SMUGGLER_REF"

remove_legacy_wrapper smuggler
install_user_wrapper smuggler <<WRAP
#!/usr/bin/env bash
exec python3 "$INSTALL_DIR/smuggler.py" "\$@"
WRAP
path_hint

log "Smuggler installation complete! Example: smuggler -u https://target.com/"
