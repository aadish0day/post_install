#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX USCREEN INSTALLER & SYSTEM STABILITY FIX
# Turns Android tablets (e.g. Galaxy Tab S9) into low-latency USB second displays
# and drawing tablets with full pen/touch support.
#
# Incorporates all production fixes:
# 1. Automatic kernel-headers matching running kernel for DKMS
# 2. EVDI driver setup & loglevel=2 patch (silences warning spam flood)
# 3. KWin Wayland crash patch (resolves KDE Bug 527984 on kwin 6.8.2-1)
# 4. Rootless uinput udev rules (allows pen/touch without root)
# 5. Latest UScreen binaries, desktop entry, icon, and systemd user service
# ============================================================================

USCREEN_REPO="majmichu1/UScreen"

log() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# ----------------------------------------------------------------------------
# 1. Arch Linux & AUR Helper Detection
# ----------------------------------------------------------------------------
if [ ! -f /etc/arch-release ] && ! grep -qi "arch" /etc/os-release 2>/dev/null; then
    error "This script is tailored specifically for Arch Linux."
    exit 1
fi

aur_cmd=""
if command -v paru &>/dev/null; then
    aur_cmd="paru"
elif command -v yay &>/dev/null; then
    aur_cmd="yay"
fi

detect_kernel_headers() {
    local kver
    kver="$(uname -r)"
    case "$kver" in
        *zen*) echo "linux-zen-headers" ;;
        *lts*) echo "linux-lts-headers" ;;
        *hardened*) echo "linux-hardened-headers" ;;
        *cachyos*) echo "linux-cachyos-headers" ;;
        *) echo "linux-headers" ;;
    esac
}

# ----------------------------------------------------------------------------
# 2. Dependency & Kernel Headers Installation
# ----------------------------------------------------------------------------
install_dependencies() {
    local headers_pkg
    headers_pkg="$(detect_kernel_headers)"
    log "Checking core dependencies and kernel headers ($headers_pkg)..."

    sudo pacman -S --needed --noconfirm \
        "$headers_pkg" dkms ffmpeg android-tools android-udev curl jq tar zstd

    # Install evdi-dkms if not installed
    if ! pacman -Qq evdi-dkms &>/dev/null && ! pacman -Qq evdi &>/dev/null; then
        if [ -n "$aur_cmd" ]; then
            log "Installing evdi-dkms via $aur_cmd..."
            "$aur_cmd" -S --needed --noconfirm evdi-dkms
        else
            warn "No AUR helper found (paru/yay). Please ensure evdi-dkms is installed from AUR."
        fi
    else
        log "EVDI driver package already installed."
    fi
}

# ----------------------------------------------------------------------------
# 3. KWin Wayland Compatibility Fix (KDE Bug 527984)
# ----------------------------------------------------------------------------
check_and_fix_kwin() {
    if ! command -v pacman &>/dev/null || ! pacman -Qq kwin &>/dev/null; then
        return 0
    fi

    local kwin_ver
    kwin_ver="$(pacman -Q kwin | awk '{print $2}')"
    log "Installed KWin version: $kwin_ver"

    # In KWin 6.8.2-1, connecting an EVDI virtual display dereferences a null
    # render device in prepareDirectScanout(), crashing KWin and plasmashell.
    if [[ "$kwin_ver" == "6.8.2-1" ]]; then
        warn "KWin 6.8.2-1 detected! Vulnerable to KDE Bug 527984 (crash on virtual display connect)."
        log "Attempting upgrade to kwin >= 6.8.2-2..."

        sudo pacman -Syu --noconfirm kwin 2>/dev/null || true
        kwin_ver="$(pacman -Q kwin | awk '{print $2}')"

        if [[ "$kwin_ver" == "6.8.2-1" ]]; then
            log "Local mirror is outdated. Pulling kwin 6.8.2-2 directly from official Arch tier-1 mirror..."
            local kwin_tmp
            kwin_tmp="$(mktemp -d /tmp/kwin_fix_XXXXXX)"
            local kwin_pkg="$kwin_tmp/kwin-6.8.2-2-x86_64.pkg.tar.zst"
            if curl -fSL -o "$kwin_pkg" "https://geo.mirror.pkgbuild.com/extra/os/x86_64/kwin-6.8.2-2-x86_64.pkg.tar.zst"; then
                sudo pacman -U --needed --noconfirm "$kwin_pkg"
                log "Successfully upgraded KWin to 6.8.2-2."
            fi
            rm -rf "$kwin_tmp" 2>/dev/null || true
        else
            log "KWin successfully updated to $kwin_ver."
        fi
    else
        log "KWin version $kwin_ver is safe from KDE Bug 527984."
    fi
}

# ----------------------------------------------------------------------------
# 4. EVDI Kernel Module Configuration & Warning Flood Silence Fix
# ----------------------------------------------------------------------------
configure_evdi() {
    log "Configuring EVDI kernel module and log suppression..."

    sudo mkdir -p /etc/modprobe.d /etc/modules-load.d

    # Set initial_device_count=2 and initial_loglevel=2 (ERROR level only).
    # This silences the continuous 4Hz grabpix/update_request warning spam.
    cat << 'EOF' | sudo tee /etc/modprobe.d/uscreen-evdi.conf >/dev/null
# Configured for UScreen
# Log levels: 1=FATAL, 2=ERROR, 3=WARN, 4=INFO (default), 5=DEBUG, 6=VERBOSE
options evdi initial_device_count=2 initial_loglevel=2
EOF

    # Persist module loading at boot
    printf "evdi\nuinput\n" | sudo tee /etc/modules-load.d/uscreen.conf >/dev/null

    # Load uinput
    sudo modprobe uinput 2>/dev/null || true

    # Live hot-patch sysfs loglevel if module is already resident
    if [ -f "/sys/devices/evdi/loglevel" ]; then
        echo 2 | sudo tee /sys/devices/evdi/loglevel >/dev/null
        log "Live EVDI loglevel hot-patched to 2."
    fi

    # Load evdi module if not loaded
    if ! lsmod | grep -q '^evdi'; then
        sudo modprobe evdi 2>/dev/null || warn "evdi module not available yet (may require reboot after newly built DKMS)."
    fi

    # Ensure at least 1 EVDI device node exists
    if [ "$(cat /sys/devices/evdi/count 2>/dev/null || echo 0)" = "0" ]; then
        echo 1 | sudo tee /sys/devices/evdi/add >/dev/null 2>&1 || true
    fi
}

# ----------------------------------------------------------------------------
# 5. Rootless Input Permissions (Tablet S-Pen, Touch, Stylus Buttons)
# ----------------------------------------------------------------------------
configure_uinput() {
    log "Configuring uinput permissions for tablet pen and touch input..."

    sudo mkdir -p /etc/udev/rules.d
    cat << 'EOF' | sudo tee /etc/udev/rules.d/60-uscreen-uinput.rules >/dev/null
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
EOF

    sudo udevadm control --reload 2>/dev/null || true
    sudo udevadm trigger --name-match=uinput 2>/dev/null || true

    if getent group input &>/dev/null; then
        sudo usermod -aG input "$USER"
    fi
}

# ----------------------------------------------------------------------------
# 6. UScreen Binaries, Desktop Integration & Service
# ----------------------------------------------------------------------------
install_uscreen_binaries() {
    local bin_dir="${HOME}/.local/bin"
    local app_dir="${HOME}/.local/share/applications"
    local icon_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
    local systemd_dir="${HOME}/.config/systemd/user"

    mkdir -p "$bin_dir" "$app_dir" "$icon_dir" "$systemd_dir"

    local setup_dir="${HOME}/Downloads/uscreen-setup"
    local tarball=""

    # Check for existing local archive first
    if [ -d "$setup_dir" ]; then
        tarball=$(find "$setup_dir" -maxdepth 2 -name "uscreen-*-linux-x86_64.tar.gz" 2>/dev/null | head -n1 || true)
    fi

    local work_dir
    work_dir="$(mktemp -d /tmp/uscreen_install_XXXXXX)"
    trap 'rm -rf "$work_dir"' EXIT

    if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
        log "Fetching latest UScreen release asset from GitHub..."
        local release_url
        release_url=$(curl -fsSL "https://api.github.com/repos/${USCREEN_REPO}/releases/latest" 2>/dev/null \
            | grep -oP '"browser_download_url":\s*"\K[^"]*uscreen-.*-linux-x86_64\.tar\.gz' | head -n1 || true)

        if [ -n "$release_url" ]; then
            log "Downloading UScreen from $release_url..."
            tarball="$work_dir/uscreen.tar.gz"
            curl -fSL -o "$tarball" "$release_url"
        fi
    fi

    if [ -f "$tarball" ]; then
        log "Extracting UScreen files..."
        tar -xzf "$tarball" -C "$work_dir"
        local extracted_dir
        extracted_dir=$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -name "uscreen-*" | head -n1 || echo "$work_dir")

        # Install binaries
        if [ -f "$extracted_dir/bin/uscreen" ]; then
            cp -f "$extracted_dir/bin/uscreen" "$bin_dir/uscreen"
        fi
        if [ -f "$extracted_dir/bin/uscreen-gui" ]; then
            cp -f "$extracted_dir/bin/uscreen-gui" "$bin_dir/uscreen-gui"
        fi
        if [ -f "$extracted_dir/bin/evdi_helper" ]; then
            cp -f "$extracted_dir/bin/evdi_helper" "$bin_dir/evdi_helper"
        fi
        if ls "$extracted_dir/bin"/libevdi.so* 1>/dev/null 2>&1; then
            cp -Pf "$extracted_dir/bin"/libevdi.so* "$bin_dir/"
        fi

        # Install desktop launcher with explicit full path
        if [ -f "$extracted_dir/scripts/uscreen.desktop" ]; then
            sed "s|^Exec=.*|Exec=$bin_dir/uscreen-gui|" "$extracted_dir/scripts/uscreen.desktop" > "$app_dir/uscreen.desktop"
        fi

        # Install systemd user service
        if [ -f "$extracted_dir/scripts/uscreen.service" ]; then
            cp -f "$extracted_dir/scripts/uscreen.service" "$systemd_dir/uscreen.service"
            systemctl --user daemon-reload 2>/dev/null || true
        fi

        # Install scalable icons
        if [ -d "$extracted_dir/packaging/icons" ]; then
            cp -f "$extracted_dir/packaging/icons/"*.svg "$icon_dir/" 2>/dev/null || true
        fi
    else
        warn "Could not fetch release tarball. Checking existing local installation..."
        if ! command -v uscreen &>/dev/null && [ ! -f "$bin_dir/uscreen" ]; then
            error "UScreen binaries could not be located or downloaded."
            exit 1
        fi
    fi

    chmod +x "$bin_dir/uscreen" "$bin_dir/evdi_helper" 2>/dev/null || true
    if [ -f "$bin_dir/uscreen-gui" ]; then
        chmod +x "$bin_dir/uscreen-gui"
    fi

    # Symlink to /usr/local/bin so uscreen is available in system PATH
    sudo ln -sf "$bin_dir/uscreen" /usr/local/bin/uscreen 2>/dev/null || true
    sudo ln -sf "$bin_dir/evdi_helper" /usr/local/bin/evdi_helper 2>/dev/null || true

    # Update icon caches
    command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -q -t "${icon_dir%/scalable/apps}" 2>/dev/null || true
    command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# 7. Tablet APK Update via ADB (Over USB)
# ----------------------------------------------------------------------------
update_tablet_apk() {
    if ! command -v adb &>/dev/null; then
        return 0
    fi

    local attached
    attached="$(adb devices 2>/dev/null | grep -w "device" | awk '{print $1}' || true)"
    if [ -z "$attached" ]; then
        log "No Android tablet connected over USB; skipping APK update."
        return 0
    fi

    log "Android tablet detected over USB ($attached). Updating UScreen APK..."
    local apk_url="https://github.com/${USCREEN_REPO}/releases/latest/download/uscreen.apk"
    local apk_tmp="/tmp/uscreen_update.apk"

    if curl -fSL -o "$apk_tmp" "$apk_url"; then
        log "Pushing and updating uscreen.apk on tablet via ADB..."
        if adb install -r "$apk_tmp"; then
            log "Tablet APK updated successfully to latest release!"
        else
            warn "ADB APK update failed; you can install it manually from $apk_url."
        fi
        rm -f "$apk_tmp" 2>/dev/null || true
    else
        warn "Could not download APK from $apk_url."
    fi
}

# ----------------------------------------------------------------------------
# 8. Verification & Doctor Checks
# ----------------------------------------------------------------------------
verify_installation() {
    log "Running environment verification..."

    local uscreen_cmd=""
    if [ -x "${HOME}/.local/bin/uscreen" ]; then
        uscreen_cmd="${HOME}/.local/bin/uscreen"
    elif command -v uscreen &>/dev/null; then
        uscreen_cmd="$(command -v uscreen)"
    fi

    if [ -n "$uscreen_cmd" ]; then
        log "Running UScreen doctor..."
        "$uscreen_cmd" doctor || true
    fi

    if command -v adb &>/dev/null; then
        local attached
        attached="$(adb devices -l 2>/dev/null | grep -v "List of devices" | grep "device" || true)"
        if [ -n "$attached" ]; then
            log "Connected Android tablet detected via ADB:"
            echo "$attached" | sed 's/^/  -> /'
        else
            log "No Android device detected over USB yet."
            log "Enable USB debugging on your tablet and connect the cable."
        fi
    fi

    log "UScreen installation and configuration complete!"
    log "Quick start: run 'uscreen start' or launch UScreen from your application menu."
}

# ----------------------------------------------------------------------------
# Main Execution
# ----------------------------------------------------------------------------
main() {
    log "Starting UScreen installation & update for Arch Linux..."
    install_dependencies
    check_and_fix_kwin
    configure_evdi
    configure_uinput
    install_uscreen_binaries
    update_tablet_apk
    verify_installation
}

main "$@"
