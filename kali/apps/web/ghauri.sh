#!/usr/bin/env bash
set -euo pipefail

# Ghauri: SQL injection detection & exploitation (https://github.com/r0oth3x49/ghauri)
# Not packaged in Kali: installed from a pinned git commit via pipx.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
GHAURI_REF="${GHAURI_REF:-18e367781caca5f9783a242f34aa90164edc902a}"

echo "=== Installing Ghauri on Kali Linux ==="
pipx_install_user "git+https://github.com/r0oth3x49/ghauri.git@${GHAURI_REF}"
path_hint
remove_legacy_wrapper ghauri

log "Ghauri installation complete! Example: ghauri -u \"http://target.com/item?id=1\" --dbs --batch"
