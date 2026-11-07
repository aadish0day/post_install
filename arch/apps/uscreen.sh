#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# ARCH LINUX USCREEN INSTALLER, UPDATER & SYSTEM STABILITY FIX
# Turns Android tablets (e.g. Galaxy Tab S9) into low-latency USB second displays
# and drawing tablets with full pen/touch support.
#
# Version-aware: compares installed version (Arch binaries + tablet APK) with the
# latest GitHub release. Only installs/updates when latest > installed.
# If both are current, system setup + installs are skipped entirely.
#
# Usage: ./uscreen.sh [--check] [--force] [--no-apk]
#   --check    only report installed vs latest versions, change nothing
#   --force    reinstall everything even if already latest
#   --no-apk   skip tablet APK step
#
# Production fixes (run only when binaries need install/update, or --force):
# 1. Automatic kernel-headers matching running kernel for DKMS
# 2. EVDI driver setup & loglevel=2 patch (silences warning spam flood)
# 3. KWin Wayland crash patch (resolves KDE Bug 527984 on kwin 6.8.2-1)
# 4. Rootless uinput udev rules (allows pen/touch without root)
# 5. Latest UScreen binaries, desktop entry, icon, and systemd user service
# ============================================================================

USCREEN_REPO="majmichu1/UScreen"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uscreen-installer"

FORCE=0
CHECK=0
DO_APK=1
for arg in "$@"; do
    case "$arg" in
    --force) FORCE=1 ;;
    --check) CHECK=1 ;;
    --no-apk) DO_APK=0 ;;
    -h | --help)
        sed -n '4,17p' "$0"
        exit 0
        ;;
    *)
        echo "Unknown option: $arg"
        exit 1
        ;;
    esac
done

log() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

WORK_DIR="$(mktemp -d /tmp/uscreen_install_XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM
mkdir -p "$STATE_DIR"

LATEST_TAG=""
LATEST_VER=""
TARBALL_URL=""
APK_URL=""

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
# Version helpers
# ----------------------------------------------------------------------------
# a > b ? (strips leading v)
ver_gt() {
    local a="${1#v}" b="${2#v}"
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] &&
        [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" = "$a" ]
}

# Installed Arch-side version, parsed from `uscreen --version` (e.g. "uscreen 1.2.8")
local_version() {
    local bin=""
    if [ -x "${HOME}/.local/bin/uscreen" ]; then
        bin="${HOME}/.local/bin/uscreen"
    elif command -v uscreen &>/dev/null; then
        bin="$(command -v uscreen)"
    fi
    [ -z "$bin" ] && return 0
    "$bin" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true
}

ready_serials() {
    adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'
}

tablet_pkg() { # $1=serial -> installed uscreen package name (empty if none)
    local pkg
    pkg="$(adb -s "$1" shell pm list packages --user 0 2>/dev/null | tr -d '\r' | sed 's/^package://' | grep -i uscreen | head -n1 || true)"
    [ -z "$pkg" ] && pkg="$(adb -s "$1" shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' | grep -i uscreen | head -n1 || true)"
    echo "$pkg"
}

tablet_version() { # $1=serial $2=package -> versionName
    adb -s "$1" shell dumpsys package "$2" 2>/dev/null | tr -d '\r' |
        awk -F= '/versionName=/{print $2; exit}' || true
}

# ----------------------------------------------------------------------------
# Latest release lookup (single API call)
# ----------------------------------------------------------------------------
fetch_release_info() {
    log "Checking for latest UScreen release on GitHub..."
    local json="$WORK_DIR/release.json"

    if ! curl -fsSL "https://api.github.com/repos/${USCREEN_REPO}/releases/latest" -o "$json" 2>/dev/null; then
        warn "Could not reach GitHub API (offline or rate-limited)."
        return 1
    fi

    LATEST_TAG="$(jq -r '.tag_name // empty' "$json")"
    LATEST_VER="${LATEST_TAG#v}"
    TARBALL_URL="$(jq -r '[.assets[]?.browser_download_url | select(test("uscreen-.*-linux-x86_64\\.tar\\.gz$"))][0] // empty' "$json")"
    APK_URL="$(jq -r '[.assets[]?.browser_download_url | select(test("\\.apk$"))][0] // empty' "$json")"
    [ -z "$APK_URL" ] && APK_URL="https://github.com/${USCREEN_REPO}/releases/latest/download/uscreen.apk"

    [ -n "$LATEST_TAG" ] && log "Upstream latest release: $LATEST_TAG"
    [ -n "$LATEST_TAG" ]
}

report_status() {
    local cv
    cv="$(local_version)"
    log "Latest release : ${LATEST_VER:-unknown}"
    if [ -z "$cv" ]; then
        log "Arch installed : (none) -> would install"
    elif ver_gt "$LATEST_VER" "$cv"; then
        log "Arch installed : $cv -> UPDATE available"
    else
        log "Arch installed : $cv (up to date)"
    fi

    if command -v adb &>/dev/null; then
        local serial pkg tv
        for serial in $(ready_serials); do
            pkg="$(tablet_pkg "$serial")"
            if [ -z "$pkg" ]; then
                log "Tablet $serial : APK not installed -> would install"
                continue
            fi
            tv="$(tablet_version "$serial" "$pkg")"
            if [ -z "$tv" ]; then
                log "Tablet $serial : $pkg (version unreadable)"
            elif ver_gt "$LATEST_VER" "$tv"; then
                log "Tablet $serial : $tv -> UPDATE available"
            else
                log "Tablet $serial : $tv (up to date)"
            fi
        done
    fi
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
            local kwin_pkg="$WORK_DIR/kwin-6.8.2-2-x86_64.pkg.tar.zst"
            if curl -fSL -o "$kwin_pkg" "https://geo.mirror.pkgbuild.com/extra/os/x86_64/kwin-6.8.2-2-x86_64.pkg.tar.zst"; then
                sudo pacman -U --needed --noconfirm "$kwin_pkg"
                log "Successfully upgraded KWin to 6.8.2-2."
            fi
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
    cat <<'EOF' | sudo tee /etc/modprobe.d/uscreen-evdi.conf >/dev/null
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
    cat <<'EOF' | sudo tee /etc/udev/rules.d/60-uscreen-uinput.rules >/dev/null
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

    # Clean up stale PID file if daemon is not running
    local pid_file="${HOME}/.local/share/uscreen/uscreen.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            log "Removing stale daemon PID file ($pid)..."
            rm -f "$pid_file"
        fi
    fi

    local setup_dir="${HOME}/Downloads/uscreen-setup"
    local tarball=""

    # Prefer fresh download
    if [ -n "$TARBALL_URL" ]; then
        log "Downloading latest UScreen package from $TARBALL_URL..."
        tarball="$WORK_DIR/uscreen.tar.gz"
        if ! curl -fSL -o "$tarball" "$TARBALL_URL"; then
            warn "Download failed; falling back to local archive if available..."
            tarball=""
        fi
    fi

    # Fall back to existing local archive only if GitHub fetch failed / offline
    if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
        if [ -d "$setup_dir" ]; then
            tarball=$(find "$setup_dir" -maxdepth 2 -name "uscreen-*-linux-x86_64.tar.gz" 2>/dev/null | sort -V | tail -n1 || true)
            if [ -n "$tarball" ] && [ -f "$tarball" ]; then
                log "Using cached local archive: $tarball"
            fi
        fi
    fi

    if [ -n "$tarball" ] && [ -f "$tarball" ]; then
        # Stop service so binaries can be replaced cleanly
        local was_active=0
        if systemctl --user is-active --quiet uscreen.service 2>/dev/null; then
            was_active=1
            log "Stopping uscreen user service for update..."
            systemctl --user stop uscreen.service 2>/dev/null || true
        fi

        log "Extracting UScreen files..."
        local ex_root="$WORK_DIR/extract"
        mkdir -p "$ex_root"
        tar -xzf "$tarball" -C "$ex_root"
        local extracted_dir
        extracted_dir=$(find "$ex_root" -mindepth 1 -maxdepth 1 -type d -name "uscreen-*" | head -n1 || true)
        [ -z "$extracted_dir" ] && extracted_dir="$ex_root"

        # install(1) unlinks destination first, preventing "Text file busy"
        for f in uscreen uscreen-gui evdi_helper; do
            if [ -f "$extracted_dir/bin/$f" ]; then
                install -m 755 "$extracted_dir/bin/$f" "$bin_dir/$f"
            fi
        done
        if ls "$extracted_dir/bin"/libevdi.so* 1>/dev/null 2>&1; then
            cp -Pf "$extracted_dir/bin"/libevdi.so* "$bin_dir/"
        fi

        # Sync downloaded release to ~/Downloads/uscreen-setup if folder exists
        if [ -d "$setup_dir" ] && [ -f "$WORK_DIR/uscreen.tar.gz" ] && [ -n "$TARBALL_URL" ]; then
            cp -f "$WORK_DIR/uscreen.tar.gz" "$setup_dir/$(basename "$TARBALL_URL")" 2>/dev/null || true
        fi

        # Install desktop launcher with explicit full path
        if [ -f "$extracted_dir/scripts/uscreen.desktop" ]; then
            sed "s|^Exec=.*|Exec=$bin_dir/uscreen-gui|" "$extracted_dir/scripts/uscreen.desktop" >"$app_dir/uscreen.desktop"
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

        [ -n "$LATEST_TAG" ] && echo "$LATEST_TAG" >"$STATE_DIR/installed-version"

        if [ "$was_active" -eq 1 ]; then
            log "Restarting uscreen user service..."
            systemctl --user start uscreen.service 2>/dev/null || warn "Could not restart uscreen.service."
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
# 7. Tablet APK Update via ADB (Over USB) - per device, version-aware
# ----------------------------------------------------------------------------
update_tablet_apk() {
    if ! command -v adb &>/dev/null; then
        return 0
    fi

    adb start-server 2>/dev/null || true

    local bad
    bad="$(adb devices 2>/dev/null | awk 'NR>1 && ($2=="unauthorized" || $2=="offline"){print $1" ("$2")"}')"
    if [ -n "$bad" ]; then
        warn "Devices not ready: $bad"
        warn "Unlock the tablet and accept the 'Allow USB debugging' prompt."
    fi

    local serials
    serials="$(ready_serials)"
    if [ -z "$serials" ]; then
        log "No authorized Android tablet detected over USB."
        log "Skipping APK update for now. Ensure USB debugging is authorized."
        return 0
    fi

    local setup_dir="${HOME}/Downloads/uscreen-setup"
    local apk_tmp="$WORK_DIR/uscreen_update.apk"
    local have_apk=0
    local serial pkg tv need

    while IFS= read -r serial; do
        [ -z "$serial" ] && continue

        pkg="$(tablet_pkg "$serial")"
        tv=""
        [ -n "$pkg" ] && tv="$(tablet_version "$serial" "$pkg")"
        tv="${tv#v}"

        need=0
        if [ "$FORCE" -eq 1 ]; then
            need=1
        elif [ -z "$pkg" ]; then
            log "[$serial] UScreen APK not installed; installing ${LATEST_VER:-latest}."
            need=1
        elif [ -n "$tv" ] && [ -n "$LATEST_VER" ]; then
            if ver_gt "$LATEST_VER" "$tv"; then
                log "[$serial] APK update: $tv -> $LATEST_VER"
                need=1
            else
                log "[$serial] APK $tv is up to date (latest $LATEST_VER)."
            fi
        elif [ -z "$LATEST_VER" ]; then
            warn "[$serial] Latest version unknown (offline?); skipping APK."
        else
            warn "[$serial] Could not read installed APK version; installing latest."
            need=1
        fi
        [ "$need" -eq 0 ] && continue

        # Download once, lazily
        if [ "$have_apk" -eq 0 ]; then
            log "Downloading APK from $APK_URL..."
            if ! curl -fSL -o "$apk_tmp" "$APK_URL"; then
                warn "Could not download APK from $APK_URL."
                return 0
            fi
            have_apk=1
        fi

        log "[$serial] Installing APK via adb..."
        if adb -s "$serial" install -r -d "$apk_tmp"; then
            log "[$serial] Tablet APK updated successfully!"
            [ -d "$setup_dir" ] && cp -f "$apk_tmp" "$setup_dir/uscreen.apk" 2>/dev/null || true
        else
            warn "[$serial] Streamed install failed, trying fallback adb push..."
            if adb -s "$serial" push "$apk_tmp" /data/local/tmp/uscreen.apk 2>/dev/null &&
                adb -s "$serial" shell pm install -r -d /data/local/tmp/uscreen.apk 2>/dev/null; then
                adb -s "$serial" shell rm -f /data/local/tmp/uscreen.apk 2>/dev/null || true
                log "[$serial] Tablet APK installed successfully via fallback push!"
            else
                warn "[$serial] ADB APK update failed (signature mismatch? uninstall the old app first)."
                warn "[$serial] Manual install: $APK_URL"
            fi
        fi
    done <<<"$serials"
}

# ADB reverse ports (runtime config, cheap; runs every time a tablet is attached)
configure_adb_reverse() {
    command -v adb &>/dev/null || return 0
    local serial
    for serial in $(ready_serials); do
        log "[$serial] Configuring ADB reverse ports (8890, 8891)..."
        adb -s "$serial" reverse tcp:8890 tcp:8890 2>/dev/null || true
        adb -s "$serial" reverse tcp:8891 tcp:8891 2>/dev/null || true
    done
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
        local installed_version
        installed_version="$("$uscreen_cmd" --version 2>/dev/null || true)"
        log "Installed version: $installed_version"
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

    # jq is needed to parse release info before anything else
    command -v jq &>/dev/null || sudo pacman -S --needed --noconfirm jq
    command -v adb &>/dev/null || [ "$CHECK" -eq 1 ] || sudo pacman -S --needed --noconfirm android-tools

    fetch_release_info || true

    if [ "$CHECK" -eq 1 ]; then
        report_status
        exit 0
    fi

    # Decide whether the Arch side needs install/update
    local cur_ver need_bin=0
    cur_ver="$(local_version)"
    if [ "$FORCE" -eq 1 ]; then
        need_bin=1
    elif [ -z "$cur_ver" ]; then
        log "UScreen not installed; installing ${LATEST_VER:-latest}."
        need_bin=1
    elif [ -z "$LATEST_VER" ]; then
        warn "Latest version unknown (offline?); keeping installed $cur_ver."
    elif ver_gt "$LATEST_VER" "$cur_ver"; then
        log "UScreen update available: $cur_ver -> $LATEST_VER"
        need_bin=1
    else
        log "UScreen $cur_ver is up to date (latest $LATEST_VER)."
    fi

    if [ "$need_bin" -eq 1 ]; then
        install_dependencies
        check_and_fix_kwin
        configure_evdi
        configure_uinput
        install_uscreen_binaries
    fi

    [ "$DO_APK" -eq 1 ] && update_tablet_apk
    configure_adb_reverse
    verify_installation
}

main "$@"
