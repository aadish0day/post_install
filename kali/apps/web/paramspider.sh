#!/usr/bin/env bash
set -euo pipefail

# ParamSpider: URL parameter mining from web archives (https://github.com/devanshbatham/ParamSpider)
# Prefers Kali's packaged build; falls back to a pinned git commit via pipx.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
PARAMSPIDER_REF="${PARAMSPIDER_REF:-c44bdaae54789b237028e309b603d1aa5ad52e5e}"

echo "=== Installing ParamSpider on Kali Linux ==="
if apt_has_candidate paramspider; then
    apt_install paramspider
else
    pipx_install_user "git+https://github.com/devanshbatham/ParamSpider.git@${PARAMSPIDER_REF}"
    path_hint
fi
remove_legacy_wrapper paramspider

log "ParamSpider installation complete! Example: paramspider -d example.com"
