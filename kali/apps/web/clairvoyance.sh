#!/usr/bin/env bash
set -euo pipefail

# Clairvoyance: GraphQL schema reconstruction (https://github.com/nikitastupin/clairvoyance)
# Pinned PyPI release installed with pipx.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
CLAIRVOYANCE_VERSION="${CLAIRVOYANCE_VERSION:-2.5.5}"

echo "=== Installing Clairvoyance on Kali Linux ==="
pipx_install_user "clairvoyance==${CLAIRVOYANCE_VERSION}"
path_hint
remove_legacy_wrapper clairvoyance

log "Clairvoyance installation complete! Example: clairvoyance https://target.com/graphql -o schema.json"
