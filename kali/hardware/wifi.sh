#!/usr/bin/env bash
# Realtek RTL88xxAU (RTL8811AU / 8812AU / 8821AU) WiFi driver installer for Kali Linux
#
# Driver choice (WIFI_DRIVER=auto|kali|morrownr, default auto):
#   kali      Kali's realtek-rtl88xxau-dkms (RTL8811/8812/8821AU, maintained with Kali kernels)
#   morrownr  morrownr/8821au-20210708 (RTL8811AU/8821AU ONLY; does not support RTL8812AU)
#   auto      try kali first, fall back to morrownr
set -euo pipefail

# Auto-elevate
if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$(readlink -f "$0")" "$@"
fi

WIFI_DRIVER="${WIFI_DRIVER:-auto}"
MORROWNR_REF="${MORROWNR_REF:-1a819991f5b75e64dfcf922b96a6681f367cbba0}"
export DEBIAN_FRONTEND=noninteractive

case "$WIFI_DRIVER" in
auto | kali | morrownr) ;;
*)
    echo "ERROR: WIFI_DRIVER must be auto, kali or morrownr (got '$WIFI_DRIVER')." >&2
    exit 1
    ;;
esac

echo "Installing RTL88xxAU WiFi drivers (WIFI_DRIVER=$WIFI_DRIVER)..."

# Report any Realtek USB adapter so a wrong/missing adapter is obvious
if command -v lsusb >/dev/null 2>&1; then
    if lsusb | grep -qi 'realtek'; then
        echo "Detected Realtek USB device(s):"
        lsusb | grep -i 'realtek' | sed 's/^/  /'
    else
        echo "WARNING: no Realtek USB adapter detected right now (plug it in before testing). Installing anyway."
    fi
fi

# Headers: use the architecture metapackage so DKMS gets headers for the NEWEST installed kernel.
# (linux-headers-$(uname -r) fails or targets a stale kernel after a kernel upgrade in the same run.)
ARCH="$(dpkg --print-architecture)"
apt-get update
apt-get install -y dkms git build-essential bc libelf-dev "linux-headers-${ARCH}" iw rfkill

install_kali_pkg() {
    echo "Installing Kali package realtek-rtl88xxau-dkms..."
    apt-get install -y realtek-rtl88xxau-dkms
}

install_morrownr() {
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    echo "Fetching morrownr/8821au-20210708 at ${MORROWNR_REF:0:12}..."
    git init -q "$tmp/8821au"
    git -C "$tmp/8821au" remote add origin https://github.com/morrownr/8821au-20210708.git
    git -C "$tmp/8821au" fetch -q --depth 1 origin "$MORROWNR_REF"
    git -C "$tmp/8821au" checkout -q FETCH_HEAD
    (cd "$tmp/8821au" && chmod +x install-driver.sh && ./install-driver.sh NoPrompt)
}

installed=0
case "$WIFI_DRIVER" in
kali)
    install_kali_pkg && installed=1
    ;;
morrownr)
    install_morrownr && installed=1
    ;;
auto)
    if install_kali_pkg; then
        installed=1
    else
        echo "Kali package failed; falling back to morrownr 8821au (RTL8811AU/8821AU only)..."
        install_morrownr && installed=1
    fi
    ;;
esac

if [ "$installed" -ne 1 ]; then
    echo "Error: WiFi driver installation failed." >&2
    exit 1
fi

echo
echo "DKMS status:"
dkms status 2>/dev/null | grep -Ei '8812au|88xxau|8821au|rtl88' || echo "  (no rtl88xx DKMS entry found; check 'dkms status')"
echo
echo "WiFi drivers installed. Running kernel: $(uname -r)."
echo "Reboot to load the module built for the newest installed kernel."
