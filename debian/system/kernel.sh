#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Liquorix Kernel (Debian/Ubuntu)
# High-performance desktop and gaming kernel.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

log "Configuring Liquorix Kernel repository..."

arch="$(dpkg --print-architecture)"
codename="$(os_codename)"
suite="${codename:-bookworm}"

key_url="https://liquorix.net/liquorix-keyring.gpg"
keyring="/etc/apt/keyrings/liquorix-keyring.gpg"

if is_simulate; then
    log "[simulate] would save Liquorix key from $key_url to $keyring"
    log "[simulate] would add Liquorix repository and install linux-image-liquorix-$arch"
    exit 0
fi

command -v gpg >/dev/null 2>&1 || apt_install gnupg curl
$SUDO install -m 0755 -d /etc/apt/keyrings

tmp_key="$(mktemp)"
if download "$key_url" "$tmp_key"; then
    if grep -q "BEGIN PGP" "$tmp_key"; then
        gpg --dearmor <"$tmp_key" | $SUDO tee "$keyring" >/dev/null
    else
        $SUDO install -m 0644 "$tmp_key" "$keyring"
    fi
    $SUDO chmod 0644 "$keyring"
    rm -f "$tmp_key"
else
    rm -f "$tmp_key"
    die "Failed to download Liquorix GPG key."
fi

echo "deb [arch=${arch} signed-by=${keyring}] https://liquorix.net/debian ${suite} main" | \
    $SUDO tee /etc/apt/sources.list.d/liquorix.list >/dev/null

apt_force_update
apt_install "linux-image-liquorix-${arch}" "linux-headers-liquorix-${arch}"

log "Liquorix kernel installation complete. Reboot to boot into the Liquorix kernel."
