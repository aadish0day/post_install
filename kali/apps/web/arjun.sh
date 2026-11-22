#!/usr/bin/env bash
set -euo pipefail

# Arjun: HTTP parameter discovery (https://github.com/s0md3v/Arjun)
# Prefers Kali's packaged build; falls back to a pinned PyPI release via pipx.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
ARJUN_VERSION="${ARJUN_VERSION:-2.2.7}"

echo "=== Installing Arjun on Kali Linux ==="
if apt_has_candidate arjun; then
    apt_install arjun
else
    pipx_install_user "arjun==${ARJUN_VERSION}"
    path_hint
fi
remove_legacy_wrapper arjun

log "Arjun installation complete! Example: arjun -u https://target.com/api/v1/profile"
