#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA USCREEN INSTALLER, UPDATER & SYSTEM STABILITY FIX
# Turns Android tablets (e.g. Galaxy Tab S9) into low-latency USB second displays
# and drawing tablets with full pen/touch support.
#
# Version-aware: compares installed version (Fedora RPM + tablet APK) with
# the latest GitHub release. Only installs/updates when latest > installed.
# If both are current, system setup + installs are skipped entirely.
#
# Usage: ./uscreen.sh [--check] [--force] [--no-apk]
#   --check    only report installed vs latest versions, change nothing
#   --force    reinstall everything even if already latest
#   --no-apk   skip tablet APK step
#
# Specific Fedora requirements handled:
# - RPM Fusion enabled for full ffmpeg codec support (swaps ffmpeg-free)
# - DisplayLink evdi DKMS module built from upstream (not packaged for Fedora)
# - Official UScreen RPM package installed with --allowerasing
# - Rootless uinput udev rules and evdi modprobe configurations
# - Automated tablet APK update and ADB reverse port forwarding (8890, 8891)
# ============================================================================

USCREEN_REPO="majmichu1/UScreen"

FORCE=0
CHECK=0
DO_APK=1
for arg in "$@"; do
    case "$arg" in
    --force) FORCE=1 ;;
    --check) CHECK=1 ;;
    --no-apk) DO_APK=0 ;;
    -h | --help)
        sed -n '4,24p' "$0"
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

LATEST_TAG=""
LATEST_VER=""
RPM_URL=""
RPM_DIGEST=""
TARBALL_URL=""
TARBALL_DIGEST=""
APK_URL=""
APK_DIGEST=""

# ----------------------------------------------------------------------------
# 1. OS & Package Manager Detection
# ----------------------------------------------------------------------------
check_os() {
    if [ ! -f /etc/fedora-release ] && ! grep -qi "fedora" /etc/os-release 2>/dev/null; then
        if [ "$CHECK" -eq 1 ]; then
            warn "Host is not Fedora Linux; running in check-only mode."
        else
            error "This script is tailored specifically for Fedora Linux."
            exit 1
        fi
    fi
}

dnf_bin="dnf"
if command -v dnf5 &>/dev/null; then
    dnf_bin="dnf5"
fi

dnf_cmd() {
    sudo "$dnf_bin" "$@"
}

# ----------------------------------------------------------------------------
# Version helpers
# ----------------------------------------------------------------------------
ver_gt() {
    local a="${1#v}" b="${2#v}"
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] || return 1
    local ab="${a%%-*}" bb="${b%%-*}"
    if [ "$ab" = "$bb" ]; then
        if [ "$a" = "$ab" ]; then return 0; fi
        if [ "$b" = "$bb" ]; then return 1; fi
    fi
    [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" = "$a" ]
}

verify_digest() {
    local file="$1" want="${2#sha256:}" got
    if [ -z "$want" ]; then
        warn "No upstream checksum published for $(basename "$file"); skipping integrity check."
        return 0
    fi
    got="$(sha256sum "$file" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
        error "Checksum mismatch for $(basename "$file") (expected $want, got $got)."
        return 1
    fi
    log "Checksum OK: $(basename "$file")"
}

system_setup_incomplete() {
    dkms status 2>/dev/null | grep -q 'evdi' || return 0
    [ -f /etc/modprobe.d/uscreen-evdi.conf ] || return 0
    [ -f /etc/modules-load.d/uscreen.conf ] || return 0
    [ -f /etc/udev/rules.d/60-uscreen-uinput.rules ] || return 0
    return 1
}

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

tablet_pkg() {
    local pkg
    pkg="$(adb -s "$1" shell pm list packages --user 0 2>/dev/null | tr -d '\r' | sed 's/^package://' | grep -i uscreen | head -n1 || true)"
    [ -z "$pkg" ] && pkg="$(adb -s "$1" shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' | grep -i uscreen | head -n1 || true)"
    echo "$pkg"
}

tablet_version() {
    adb -s "$1" shell dumpsys package "$2" 2>/dev/null | tr -d '\r' |
        awk -F= '/versionName=/{print $2; exit}' || true
}

# ----------------------------------------------------------------------------
# 2. Latest release lookup (single GitHub API call)
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

    RPM_URL="$(jq -r '[.assets[]?.browser_download_url | select(test("uscreen.*\\.x86_64\\.rpm$"))][0] // empty' "$json")"
    RPM_DIGEST="$(jq -r '[.assets[]? | select(.browser_download_url | test("uscreen.*\\.x86_64\\.rpm$"))][0].digest // empty' "$json")"

    TARBALL_URL="$(jq -r '[.assets[]?.browser_download_url | select(test("uscreen-.*-linux-x86_64\\.tar\\.gz$"))][0] // empty' "$json")"
    TARBALL_DIGEST="$(jq -r '[.assets[]? | select(.browser_download_url | test("uscreen-.*-linux-x86_64\\.tar\\.gz$"))][0].digest // empty' "$json")"

    APK_URL="$(jq -r '[.assets[]?.browser_download_url | select(test("\\.apk$"))][0] // empty' "$json")"
    APK_DIGEST="$(jq -r '[.assets[]? | select(.browser_download_url | test("\\.apk$"))][0].digest // empty' "$json")"
    [ -z "$APK_URL" ] && APK_URL="https://github.com/${USCREEN_REPO}/releases/latest/download/uscreen.apk"

    # Also parse SHA256SUMS asset if digests are not embedded in API
    local sums_url
    sums_url="$(jq -r '[.assets[]?.browser_download_url | select(test("SHA256SUMS$"))][0] // empty' "$json")"
    if [ -n "$sums_url" ]; then
        curl -fsSL "$sums_url" -o "$WORK_DIR/SHA256SUMS" 2>/dev/null || true
        if [ -f "$WORK_DIR/SHA256SUMS" ]; then
            if [ -z "$RPM_DIGEST" ] && [ -n "$RPM_URL" ]; then
                local rpm_name
                rpm_name="$(basename "$RPM_URL")"
                RPM_DIGEST="$(awk -v f="$rpm_name" '$2==f || $2=="*"f {print $1; exit}' "$WORK_DIR/SHA256SUMS" || true)"
            fi
            if [ -z "$APK_DIGEST" ] && [ -n "$APK_URL" ]; then
                local apk_name
                apk_name="$(basename "$APK_URL")"
                APK_DIGEST="$(awk -v f="$apk_name" '$2==f || $2=="*"f {print $1; exit}' "$WORK_DIR/SHA256SUMS" || true)"
            fi
            if [ -z "$TARBALL_DIGEST" ] && [ -n "$TARBALL_URL" ]; then
                local tb_name
                tb_name="$(basename "$TARBALL_URL")"
                TARBALL_DIGEST="$(awk -v f="$tb_name" '$2==f || $2=="*"f {print $1; exit}' "$WORK_DIR/SHA256SUMS" || true)"
            fi
        fi
    fi

    [ -n "$LATEST_TAG" ] && log "Upstream latest release: $LATEST_TAG"
    [ -n "$LATEST_TAG" ]
}

report_status() {
    local cv
    cv="$(local_version)"
    log "Latest release : ${LATEST_VER:-unknown}"
    if [ -z "$LATEST_VER" ]; then
        warn "Latest version unknown (offline or rate-limited); cannot compare."
        log "Host installed : ${cv:-(none)}"
        return 0
    fi
    if [ -z "$cv" ]; then
        log "Host installed : (none) -> would install"
    elif ver_gt "$LATEST_VER" "$cv"; then
        log "Host installed : $cv -> UPDATE available"
    else
        log "Host installed : $cv (up to date)"
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
# 3. RPM Fusion, Dependencies & EVDI Module Build for Fedora
# ----------------------------------------------------------------------------
install_dependencies() {
    log "Checking core dependencies, kernel headers, and RPM Fusion on Fedora..."

    # 1. Enable RPM Fusion for ffmpeg (stock Fedora only has ffmpeg-free)
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        log "Enabling RPM Fusion free repository..."
        local fedora_ver
        fedora_ver="$(rpm -E %fedora 2>/dev/null || echo "41")"
        dnf_cmd install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm" 2>/dev/null || true
    fi

    # Swap ffmpeg-free with full ffmpeg if needed
    if ! rpm -q ffmpeg &>/dev/null; then
        log "Installing full ffmpeg from RPM Fusion (--allowerasing)..."
        dnf_cmd install -y --allowerasing ffmpeg 2>/dev/null || warn "Could not install full ffmpeg. Retrying with basic dependencies."
    fi

    # Core required packages for Fedora
    local kver
    kver="$(uname -r)"
    local core_pkgs=(
        android-tools
        "kernel-devel-${kver}"
        kernel-headers
        dkms
        git
        make
        gcc
        curl
        jq
        tar
        libdrm
    )

    log "Ensuring required build tools and kernel headers are installed..."
    dnf_cmd install -y "${core_pkgs[@]}"

    # EVDI module setup:
    # DisplayLink evdi is NOT packaged in Fedora official repositories.
    # We build the DKMS module directly from upstream DisplayLink/evdi v1.15.1
    if ! dkms status 2>/dev/null | grep -q 'evdi'; then
        log "EVDI is not packaged in Fedora repositories. Building DisplayLink evdi v1.15.1 DKMS module from source..."
        local evdi_src="$WORK_DIR/evdi"
        rm -rf "$evdi_src"
        if git clone --depth 1 --branch v1.15.1 https://github.com/DisplayLink/evdi.git "$evdi_src"; then
            (
                cd "$evdi_src/module"
                sudo make install_dkms
                sudo modprobe evdi 2>/dev/null || true
            )
            log "DisplayLink evdi v1.15.1 DKMS module installed successfully on Fedora."
        else
            warn "Could not clone DisplayLink evdi repo. Please verify internet connection."
        fi
    else
        log "EVDI DKMS module is already installed."
    fi
}

# ----------------------------------------------------------------------------
# 4. EVDI Kernel Module & Rootless Uinput Configuration
# ----------------------------------------------------------------------------
configure_system_files() {
    log "Configuring EVDI module parameters and udev permissions..."

    sudo mkdir -p /etc/modprobe.d /etc/modules-load.d /etc/udev/rules.d

    # /etc/modprobe.d/uscreen-evdi.conf
    # options evdi initial_device_count=2 initial_loglevel=2 (silences 4Hz spam)
    cat <<'EOF' | sudo tee /etc/modprobe.d/uscreen-evdi.conf >/dev/null
# Configured for UScreen
# Log levels: 1=FATAL, 2=ERROR, 3=WARN, 4=INFO, 5=DEBUG, 6=VERBOSE
options evdi initial_device_count=2 initial_loglevel=2
EOF

    # /etc/modules-load.d/uscreen.conf
    printf "evdi\nuinput\n" | sudo tee /etc/modules-load.d/uscreen.conf >/dev/null

    # /etc/udev/rules.d/60-uscreen-uinput.rules
    cat <<'EOF' | sudo tee /etc/udev/rules.d/60-uscreen-uinput.rules >/dev/null
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
EOF

    # Reload udev and load modules
    sudo udevadm control --reload 2>/dev/null || true
    sudo udevadm trigger --name-match=uinput 2>/dev/null || true

    sudo modprobe uinput 2>/dev/null || true
    if [ -f "/sys/devices/evdi/loglevel" ]; then
        echo 2 | sudo tee /sys/devices/evdi/loglevel >/dev/null || true
    fi
    sudo modprobe evdi 2>/dev/null || true

    if [ "$(cat /sys/devices/evdi/count 2>/dev/null || echo 0)" = "0" ]; then
        echo 1 | sudo tee /sys/devices/evdi/add >/dev/null 2>&1 || true
    fi
}

# ----------------------------------------------------------------------------
# 5. UScreen Package (.rpm) or Binary Installation
# ----------------------------------------------------------------------------
install_uscreen_package() {
    local installed_rpm=false

    # Prefer official .rpm package on Fedora x86_64
    if [ -n "$RPM_URL" ] && [ "$(uname -m)" = "x86_64" ]; then
        log "Downloading UScreen RPM package from $RPM_URL..."
        local rpm_target="$WORK_DIR/uscreen.rpm"
        if curl -fSL -o "$rpm_target" "$RPM_URL"; then
            if verify_digest "$rpm_target" "$RPM_DIGEST"; then
                log "Installing UScreen RPM package (--allowerasing)..."
                # Stop service before upgrade
                systemctl --user stop uscreen.service 2>/dev/null || true

                if dnf_cmd install -y --allowerasing "$rpm_target" 2>/dev/null; then
                    installed_rpm=true
                fi
            fi
        fi
    fi

    # Fallback: install from official tarball if .rpm failed or unavailable
    if [ "$installed_rpm" = false ]; then
        warn "Fedora RPM package install was not completed. Falling back to universal tarball..."
        install_uscreen_from_tarball
    fi

    # Enable and start user service as documented: systemctl --user enable --now uscreen
    log "Configuring systemd user service..."
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now uscreen.service 2>/dev/null || warn "Could not enable uscreen.service immediately (starts on next login)."

    # Update desktop icon caches
    command -v gtk-update-icon-cache &>/dev/null && sudo gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true
    command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 2>/dev/null || true
}

install_uscreen_from_tarball() {
    local bin_dir="${HOME}/.local/bin"
    local app_dir="${HOME}/.local/share/applications"
    local icon_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
    local systemd_dir="${HOME}/.config/systemd/user"

    mkdir -p "$bin_dir" "$app_dir" "$icon_dir" "$systemd_dir"

    local tarball="$WORK_DIR/uscreen.tar.gz"
    if [ -n "$TARBALL_URL" ]; then
        log "Downloading UScreen tarball from $TARBALL_URL..."
        curl -fSL -o "$tarball" "$TARBALL_URL"
        verify_digest "$tarball" "$TARBALL_DIGEST"
    else
        error "No tarball download URL available."
        exit 1
    fi

    log "Extracting UScreen files..."
    local ex_root="$WORK_DIR/extract"
    mkdir -p "$ex_root"
    tar -xzf "$tarball" -C "$ex_root"
    local extracted_dir
    extracted_dir=$(find "$ex_root" -mindepth 1 -maxdepth 1 -type d -name "uscreen-*" | head -n1 || true)
    [ -z "$extracted_dir" ] && extracted_dir="$ex_root"

    for f in uscreen uscreen-gui evdi_helper; do
        if [ -f "$extracted_dir/bin/$f" ]; then
            install -m 755 "$extracted_dir/bin/$f" "$bin_dir/$f"
        fi
    done
    if ls "$extracted_dir/bin"/libevdi.so* 1>/dev/null 2>&1; then
        cp -Pf "$extracted_dir/bin"/libevdi.so* "$bin_dir/"
    fi

    if [ -f "$extracted_dir/scripts/uscreen.desktop" ]; then
        sed "s|^Exec=.*|Exec=$bin_dir/uscreen-gui|" "$extracted_dir/scripts/uscreen.desktop" >"$app_dir/uscreen.desktop"
    fi

    if [ -f "$extracted_dir/scripts/uscreen.service" ]; then
        cp -f "$extracted_dir/scripts/uscreen.service" "$systemd_dir/uscreen.service"
    fi

    if [ -d "$extracted_dir/packaging/icons" ]; then
        cp -f "$extracted_dir/packaging/icons/"*.svg "$icon_dir/" 2>/dev/null || true
    fi

    sudo ln -sf "$bin_dir/uscreen" /usr/local/bin/uscreen 2>/dev/null || true
    sudo ln -sf "$bin_dir/evdi_helper" /usr/local/bin/evdi_helper 2>/dev/null || true
}

# ----------------------------------------------------------------------------
# 6. Tablet APK Update via ADB (Over USB)
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

        if [ "$have_apk" -eq 0 ]; then
            log "Downloading APK from $APK_URL..."
            if curl -fSL -o "$apk_tmp" "$APK_URL" && verify_digest "$apk_tmp" "$APK_DIGEST"; then
                have_apk=1
            else
                warn "Could not download/verify APK from $APK_URL."
                have_apk=-1
            fi
        fi
        if [ "$have_apk" -ne 1 ]; then
            warn "[$serial] Skipping APK install (no verified APK)."
            continue
        fi

        log "[$serial] Installing APK via adb..."
        if adb -s "$serial" install -r -d "$apk_tmp"; then
            log "[$serial] Tablet APK updated successfully!"
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
# 7. Verification & Doctor Checks
# ----------------------------------------------------------------------------
verify_installation() {
    log "Running environment verification..."

    local uscreen_cmd=""
    if command -v uscreen &>/dev/null; then
        uscreen_cmd="$(command -v uscreen)"
    elif [ -x "${HOME}/.local/bin/uscreen" ]; then
        uscreen_cmd="${HOME}/.local/bin/uscreen"
    fi

    if [ -n "$uscreen_cmd" ]; then
        local installed_version
        installed_version="$("$uscreen_cmd" --version 2>/dev/null || true)"
        log "Installed version: $installed_version"
        log "Running UScreen doctor..."
        "$uscreen_cmd" doctor || true
    fi

    # Validate VA-API device path in config to prevent failure on hybrid GPU profile switch
    local cfg="${HOME}/.config/uscreen/config.toml"
    if [ -f "$cfg" ]; then
        local va_dev
        va_dev="$(grep -E '^\s*vaapi_device\s*=' "$cfg" | sed -E 's/.*=\s*"([^"]*)".*/\1/' || true)"
        if [ -n "$va_dev" ] && [ ! -e "$va_dev" ]; then
            warn "Configured vaapi_device '$va_dev' does not exist."
            warn "Resetting vaapi_device in $cfg to \"\" for automatic GPU detection."
            sed -i -E 's/^\s*vaapi_device\s*=.*/vaapi_device = ""/' "$cfg"
        fi
    fi

    log "UScreen installation and configuration complete!"
    log "Quick start: run 'systemctl --user start uscreen' or launch UScreen from your application menu."
}

# ----------------------------------------------------------------------------
# Main Execution
# ----------------------------------------------------------------------------
main() {
    log "Starting UScreen installation & update for Fedora..."

    check_os

    if [ "$CHECK" -eq 0 ]; then
        # Ensure jq is installed
        command -v jq &>/dev/null || dnf_cmd install -y jq
    fi

    fetch_release_info || true

    if [ "$CHECK" -eq 1 ]; then
        report_status
        exit 0
    fi

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

    local need_sys=0
    if [ "$FORCE" -eq 1 ]; then
        need_sys=1
    elif system_setup_incomplete; then
        warn "System setup (EVDI/uinput/udev) looks incomplete; configuring."
        need_sys=1
    fi

    if [ "$need_sys" -eq 1 ]; then
        install_dependencies
        configure_system_files
    fi

    [ "$need_bin" -eq 1 ] && install_uscreen_package

    [ "$DO_APK" -eq 1 ] && update_tablet_apk
    configure_adb_reverse
    verify_installation
}

main "$@"
