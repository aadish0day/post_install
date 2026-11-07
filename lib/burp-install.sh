#!/usr/bin/env bash
# ============================================================================
# Universal Burp Suite Professional Shared Core Installer
# ============================================================================

set -euo pipefail

BURP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$BURP_LIB_DIR/burp-common.sh" ]]; then
    # shellcheck source=lib/burp-common.sh
    source "$BURP_LIB_DIR/burp-common.sh"
elif [[ -n "${ROOT_DIR:-}" && -f "$ROOT_DIR/lib/burp-common.sh" ]]; then
    # shellcheck source=lib/burp-common.sh
    source "$ROOT_DIR/lib/burp-common.sh"
fi

BURP_STABLE_VERSION="${DEFAULT_BURP_VER:-2026.10.1}"
REPO_DIR="${REPO_DIR:-$HOME/Documents/Crack/Burpsuite-Professional}"
JYTHON_URL="https://repo1.maven.org/maven2/org/python/jython-standalone/2.7.4/jython-standalone-2.7.4.jar"
JYTHON_JAR="jython-standalone-2.7.4.jar"
JYTHON_FILE="$REPO_DIR/$JYTHON_JAR"
JRUBY_VERSION="9.4.9.0"
JRUBY_URL="https://repo1.maven.org/maven2/org/jruby/jruby-complete/${JRUBY_VERSION}/jruby-complete-${JRUBY_VERSION}.jar"
JRUBY_JAR="jruby-complete-${JRUBY_VERSION}.jar"
JRUBY_FILE="$REPO_DIR/$JRUBY_JAR"

LOADER_URLS=(
    "https://codeberg.org/code07/test01/raw/branch/main/loader.jar"
)

# Helper function to find best Java 21 binary
find_java_bin() {
    local j
    if [ -n "${BURP_JAVA:-}" ] && [ -x "$BURP_JAVA" ]; then
        echo "$BURP_JAVA"
        return 0
    fi
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        echo "$JAVA_HOME/bin/java"
        return 0
    fi
    for j in \
        "/usr/lib/jvm/java-21-openjdk/bin/java" \
        "/usr/lib/jvm/java-21-openjdk-amd64/bin/java" \
        "/usr/lib/jvm/java-21-openjdk-arm64/bin/java" \
        "/usr/lib/jvm/jre-21-openjdk/bin/java" \
        "/usr/lib/jvm/java-21/bin/java" \
        "/usr/lib/jvm/default-runtime/bin/java"; do
        if [ -x "$j" ]; then
            echo "$j"
            return 0
        fi
    done
    if command -v java &>/dev/null; then
        echo "java"
        return 0
    fi
    echo "java"
}

# Helper function to find burp binary
find_burp_bin() {
    if [ -n "${BURP_BIN:-}" ] && [ "$BURP_BIN" != "none" ] && [ -x "$BURP_BIN" ]; then
        echo "$BURP_BIN"
        return 0
    fi
    local b
    for b in "$HOME/.local/bin/burpsuitepro" "/usr/local/bin/burpsuitepro" "${REPO_DIR:-$HOME/Documents/Crack/Burpsuite-Professional}/burpsuitepro"; do
        if [ -x "$b" ]; then
            echo "$b"
            return 0
        fi
    done
    if command -v burpsuitepro &>/dev/null; then
        command -v burpsuitepro
        return 0
    fi
    return 1
}

# Helper function to get file size in bytes
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# Helper function to compare version strings: returns 0 (true) if $1 >= $2
version_ge() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Helper function to verify that a file is a valid jar/zip archive
is_valid_jar() {
    local jar="$1"
    local min_size="${2:-1048576}" # Default 1MB minimum size
    if [[ ! -f "$jar" ]]; then
        return 1
    fi
    local sz
    sz="$(get_file_size "$jar")"
    if [[ "$sz" -le "$min_size" ]]; then
        return 1
    fi
    if command -v unzip &>/dev/null; then
        unzip -tq "$jar" >/dev/null 2>&1
        return $?
    elif command -v python3 &>/dev/null; then
        python3 -c "import zipfile, sys; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$jar" 2>/dev/null
        return $?
    fi
    # Fallback to checking PK zip magic header
    local magic
    magic="$(head -c 2 "$jar" 2>/dev/null || true)"
    [[ "$magic" == "PK" ]]
}

# Pre-seed JRE Warning Suppression
suppress_jre_warnings() {
    echo "Configuring JRE warning suppression..."
    local prefs_dir="$HOME/.java/.userPrefs/burp"
    local prefs_file="$prefs_dir/prefs.xml"
    mkdir -p "$prefs_dir"

    local entries=(
        "suite.alertsdisabledforjre-3189538875"
        "suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-3189538875"
        "burp.suite.alertsdisabledforjre-1115054815"
        "burp.suite.alertsdisabledforjre-1872878544"
        "burp.suite.alertsdisabledforjre-413592390"
    )

    local key
    for key in "${entries[@]}"; do
        merge_pref_entry "$prefs_file" "$key" "true"
    done
    echo "JRE warning suppression configured."
}

# Verify unprivileged user namespaces on Arch Linux
burp_check_user_namespaces() {
    echo "Checking unprivileged user namespaces for embedded Chromium..."
    local userns_sysctl="/proc/sys/user/max_user_namespaces"
    local userns_clone="/proc/sys/kernel/unprivileged_userns_clone"

    # Detect when user.max_user_namespaces is disabled (0) on Arch
    if [[ -f "$userns_sysctl" ]] && [[ "$(cat "$userns_sysctl" 2>/dev/null || echo 1)" -eq 0 ]]; then
        echo "Detected user.max_user_namespaces=0 (user namespaces disabled)."
        echo "Attempting to enable unprivileged user namespaces..."
        if [[ $EUID -eq 0 ]]; then
            sysctl -w user.max_user_namespaces=10000 2>/dev/null || true
            echo "user.max_user_namespaces=10000" >/etc/sysctl.d/99-burp-userns.conf 2>/dev/null || true
        elif command -v sudo &>/dev/null; then
            sudo sysctl -w user.max_user_namespaces=10000 2>/dev/null || true
            echo "user.max_user_namespaces=10000" | sudo tee /etc/sysctl.d/99-burp-userns.conf >/dev/null 2>&1 || true
        fi
    fi

    # Detect when kernel.unprivileged_userns_clone is 0 (e.g. linux-hardened)
    if [[ -f "$userns_clone" ]] && [[ "$(cat "$userns_clone" 2>/dev/null || echo 1)" -eq 0 ]]; then
        echo "Detected kernel.unprivileged_userns_clone=0."
        echo "Attempting to enable unprivileged user namespaces..."
        if [[ $EUID -eq 0 ]]; then
            sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
            echo "kernel.unprivileged_userns_clone=1" >/etc/sysctl.d/99-burp-userns.conf 2>/dev/null || true
        elif command -v sudo &>/dev/null; then
            sudo sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
            echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.d/99-burp-userns.conf >/dev/null 2>&1 || true
        fi
    fi

    local userns_ok=true
    if [[ -f "$userns_sysctl" ]] && [[ "$(cat "$userns_sysctl" 2>/dev/null || echo 1)" -eq 0 ]]; then
        userns_ok=false
    fi
    if [[ -f "$userns_clone" ]] && [[ "$(cat "$userns_clone" 2>/dev/null || echo 1)" -eq 0 ]]; then
        userns_ok=false
    fi
    if ! unshare --user true 2>/dev/null; then
        userns_ok=false
    fi

    if [[ "$userns_ok" == false ]]; then
        echo "[!] Warning: Unprivileged user namespaces appear disabled or restricted."
        echo "    Burp Suite's embedded Chromium browser requires user namespaces to sandbox."
        if [[ -f "$userns_clone" ]] && [[ "$(cat "$userns_clone" 2>/dev/null || echo 1)" -eq 0 ]]; then
            echo "    Enable them with: sudo sysctl -w kernel.unprivileged_userns_clone=1"
            echo "    Or persist via: echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/99-burp-userns.conf"
        else
            echo "    Enable them with: sudo sysctl -w user.max_user_namespaces=10000"
            echo "    Or persist via: echo 'user.max_user_namespaces=10000' | sudo tee /etc/sysctl.d/99-burp-userns.conf"
        fi
    else
        echo "Unprivileged user namespaces verified (embedded Chromium sandbox supported)."
    fi
}

# Verify unprivileged user namespaces on Debian / Kali
burp_enable_debian_userns() {
    if [[ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || true)" == "0" ]]; then
        echo "Enabling unprivileged user namespaces for embedded Chromium sandbox..."
        if command -v sudo &>/dev/null; then
            sudo sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
            echo "kernel.unprivileged_userns_clone=1" | sudo tee /etc/sysctl.d/99-burp-userns.conf >/dev/null 2>&1 || true
        elif [[ $EUID -eq 0 ]]; then
            sysctl -w kernel.unprivileged_userns_clone=1 2>/dev/null || true
            echo "kernel.unprivileged_userns_clone=1" >/etc/sysctl.d/99-burp-userns.conf 2>/dev/null || true
        fi
    fi
}

# Install scalable and raster icons across user and system hicolor themes
install_burp_system_icons() {
    local svg_source="${1:-}"
    if [[ -z "$svg_source" || ! -f "$svg_source" ]]; then
        if [[ -f "$REPO_DIR/burp_suite_pro_icon.svg" ]]; then
            svg_source="$REPO_DIR/burp_suite_pro_icon.svg"
        else
            echo "Warning: Icon source SVG not found ($svg_source). Skipping icon installation."
            return 0
        fi
    fi

    echo "Installing Burp Suite system icons..."
    local user_icon_base="$HOME/.local/share/icons/hicolor"
    local user_pixmaps="$HOME/.local/share/pixmaps"
    mkdir -p "$user_icon_base/scalable/apps" "$user_pixmaps"

    cp -f "$svg_source" "$user_icon_base/scalable/apps/burpsuitepro.svg"
    cp -f "$svg_source" "$user_pixmaps/burpsuitepro.svg"

    local sizes=(16 24 32 48 64 128 256 512)
    local s
    for s in "${sizes[@]}"; do
        local user_size_dir="$user_icon_base/${s}x${s}/apps"
        mkdir -p "$user_size_dir"
        local target_png="$user_size_dir/burpsuitepro.png"
        if command -v rsvg-convert &>/dev/null; then
            rsvg-convert -w "$s" -h "$s" "$svg_source" -o "$target_png" 2>/dev/null || true
        elif command -v convert &>/dev/null; then
            convert -background none "$svg_source" -resize "${s}x${s}" "$target_png" 2>/dev/null || true
        elif command -v magick &>/dev/null; then
            magick "$svg_source" -background none -resize "${s}x${s}" "$target_png" 2>/dev/null || true
        fi
    done

    # System-wide installation only when explicitly running as root
    if [[ $EUID -eq 0 ]]; then
        local sys_icon_base="/usr/local/share/icons/hicolor"
        local sys_pixmaps="/usr/share/pixmaps"
        mkdir -p "$sys_icon_base/scalable/apps" "$sys_pixmaps" 2>/dev/null || true
        cp -f "$svg_source" "$sys_icon_base/scalable/apps/burpsuitepro.svg" 2>/dev/null || true
        cp -f "$svg_source" "$sys_pixmaps/burpsuitepro.svg" 2>/dev/null || true
        for s in "${sizes[@]}"; do
            if [[ -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" ]]; then
                mkdir -p "$sys_icon_base/${s}x${s}/apps" 2>/dev/null || true
                cp -f "$user_icon_base/${s}x${s}/apps/burpsuitepro.png" "$sys_icon_base/${s}x${s}/apps/burpsuitepro.png" 2>/dev/null || true
            fi
        done
        gtk-update-icon-cache -f -q -t "$sys_icon_base" 2>/dev/null || true
    fi

    # Rebuild user icon cache
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -q -t "$user_icon_base" 2>/dev/null || true
    fi
}

# Install custom MIME type for Burp Suite project files
install_burp_system_mime() {
    echo "Installing Burp Suite project MIME type..."
    local user_mime_dir="$HOME/.local/share/mime/packages"
    mkdir -p "$user_mime_dir"

    cat <<'EOF' >"$user_mime_dir/burpsuitepro.xml"
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-burp-project">
    <comment>Burp Suite Project</comment>
    <icon name="burpsuitepro"/>
    <glob pattern="*.burp"/>
    <glob pattern="*.burpstate"/>
  </mime-type>
</mime-info>
EOF

    if command -v update-mime-database &>/dev/null; then
        update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    fi

    # System-wide MIME installation only when explicitly running as root
    if [[ $EUID -eq 0 ]]; then
        local sys_mime_dir="/usr/local/share/mime/packages"
        mkdir -p "$sys_mime_dir" 2>/dev/null || true
        cp -f "$user_mime_dir/burpsuitepro.xml" "$sys_mime_dir/burpsuitepro.xml" 2>/dev/null || true
        update-mime-database /usr/local/share/mime 2>/dev/null || true
    fi
}

burp_usage() {
    cat <<EOF
Usage: install.sh [OPTIONS] [VERSION]

Install Burp Suite Professional with selectable version channel.

Options:
  -v, --version <ver>   Install an exact version (e.g. 2026.10.1)
      --channel <name>  Version channel: stable (tested) or latest (UNTESTED)
  -f, --force           Re-download even if files already exist
      --skip-launch     Install without launching Burp Suite
  -h, --help            Show this help and exit

Environment:
  BURP_VERSION          Same as --version; -v takes precedence
EOF
}

run_burp_installation() {
    local distro_label="$1"
    local dep_func="$2"
    local sandbox_func="$3"
    shift 3

    local skip_launch=false
    local force_download=false
    local custom_version=""
    local channel=""
    local explicit_version=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            burp_usage
            exit 0
            ;;
        -v | --version)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: $1 requires a version argument." >&2
                burp_usage
                exit 1
            fi
            custom_version="$2"
            explicit_version=true
            shift 2
            ;;
        --version=*)
            custom_version="${1#*=}"
            explicit_version=true
            shift
            ;;
        --skip-launch)
            skip_launch=true
            shift
            ;;
        -f | --force)
            force_download=true
            shift
            ;;
        --channel)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: $1 requires a channel argument (stable or latest)." >&2
                burp_usage
                exit 1
            fi
            channel="$2"
            shift 2
            ;;
        --channel=*)
            channel="${1#*=}"
            shift
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            burp_usage
            exit 1
            ;;
        *)
            if [[ -z "$custom_version" && "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                custom_version="$1"
                explicit_version=true
                shift
            else
                echo "ERROR: Unknown option or argument: $1" >&2
                burp_usage
                exit 1
            fi
            ;;
        esac
    done

    # Validate channel argument if provided
    if [[ -n "$channel" ]]; then
        local channel_norm="${channel,,}"
        if [[ "$channel_norm" != "stable" && "$channel_norm" != "latest" ]]; then
            echo "ERROR: Invalid channel '$channel'. Allowed channels are: stable, latest" >&2
            burp_usage
            exit 1
        fi
        channel="$channel_norm"
    fi

    # Version resolution
    local burp_ver=""
    if [[ -n "$custom_version" ]]; then
        burp_ver="$custom_version"
        if [[ -n "$channel" ]]; then
            echo "WARNING: Both --channel ($channel) and explicit version ($custom_version) specified. Explicit version takes precedence over --channel." >&2
        fi
        echo "Using specified Burp Suite version: $burp_ver"
    elif [[ -n "${BURP_VERSION:-}" ]]; then
        burp_ver="$BURP_VERSION"
        explicit_version=true
        if [[ -n "$channel" ]]; then
            echo "WARNING: Both --channel ($channel) and BURP_VERSION ($BURP_VERSION) specified. BURP_VERSION takes precedence over --channel." >&2
        fi
        echo "Using environment BURP_VERSION: $burp_ver"
    else
        channel="${channel:-stable}"
        if [[ "$channel" == "stable" ]]; then
            burp_ver="$BURP_STABLE_VERSION"
            echo "Using stable (tested) Burp Suite version: $burp_ver"
        elif [[ "$channel" == "latest" ]]; then
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║  ⚠  WARNING: Latest channel selected (UNTESTED)            ║"
            echo "║  This fetches the newest release from PortSwigger.          ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo "Fetching latest Burp Suite version from PortSwigger..."
            burp_ver="$(curl -sSL --connect-timeout 10 --max-time 15 'https://portswigger.net/burp/releases/data?pageSize=10' 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        for r in data.get('ResultSet', {}).get('Results', []):
            if any(b.get('BuildCategoryPlatform') == 'Jar' for b in r.get('builds', [])):
                v = r.get('version')
                if v:
                    print(v)
                    sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)"

            if [[ -z "$burp_ver" ]]; then
                burp_ver="$BURP_STABLE_VERSION"
                echo "PortSwigger release API unavailable. Falling back to stable version: $burp_ver"
            else
                echo "Latest version detected: $burp_ver"
            fi
        else
            echo "ERROR: Invalid channel '$channel'. Use 'stable' or 'latest'." >&2
            exit 1
        fi
    fi

    local jar_name="burpsuite_pro_v${burp_ver}.jar"
    local download_url="https://portswigger.net/burp/releases/download?product=desktop&version=${burp_ver}&type=Jar"

    echo "=== Installing Burp Suite Professional ($distro_label) ==="

    # Check for active running instances
    if pgrep -f "(java|openjdk).*[b]urpsuite_pro_v.*\.jar" >/dev/null 2>&1; then
        echo "[!] Warning: Burp Suite Professional is currently running."
        echo "Please close Burp Suite to avoid file lock issues."
        if [ -t 0 ]; then
            read -rp "Press Enter once Burp Suite is closed, or Ctrl+C to cancel..." || true
        fi
    fi

    # 1. Install dependencies & run sandbox check
    if declare -f "$dep_func" >/dev/null 2>&1; then
        "$dep_func"
    fi
    if declare -f "$sandbox_func" >/dev/null 2>&1; then
        "$sandbox_func"
    fi

    # 2. Setup install directory
    mkdir -p "$REPO_DIR"

    # Download loader.jar
    local loader_file="$REPO_DIR/loader.jar"
    local min_loader_size=10240
    if [[ -f "$loader_file" ]] && is_valid_jar "$loader_file" "$min_loader_size" && [[ "$force_download" == false ]]; then
        echo "Existing loader.jar verified (> 10KB valid archive). Skipping download."
    else
        echo "Downloading loader.jar..."
        local loader_downloaded=false
        local url
        for url in "${LOADER_URLS[@]}"; do
            echo "Attempting loader download from: $url"
            if curl -fL --connect-timeout 10 --max-time 60 --progress-bar -o "$loader_file.tmp" "$url" 2>/dev/null; then
                if is_valid_jar "$loader_file.tmp" "$min_loader_size"; then
                    mv -f "$loader_file.tmp" "$loader_file"
                    echo "Successfully downloaded loader.jar"
                    loader_downloaded=true
                    break
                else
                    rm -f "$loader_file.tmp"
                fi
            fi
        done
        if [[ "$loader_downloaded" == false ]]; then
            if [[ -f "$loader_file" ]] && is_valid_jar "$loader_file" "$min_loader_size"; then
                echo "WARNING: Failed to re-download loader.jar, preserving existing valid file."
            else
                echo "ERROR: Failed to download valid loader.jar from all mirrors." >&2
                exit 1
            fi
        fi
    fi

    # 3. Download Burp Suite Pro JAR
    cd "$REPO_DIR" || exit 1
    local skip_download=false
    local min_jar_size=10485760 # 10MB
    local target_jar="$REPO_DIR/$jar_name"

    if [[ "$force_download" == false ]]; then
        if [[ -f "$target_jar" ]] && is_valid_jar "$target_jar" "$min_jar_size"; then
            local target_size
            target_size="$(get_file_size "$target_jar")"
            echo "Burp Suite Professional v$burp_ver ($jar_name) already present and valid ($((target_size / 1024 / 1024))MB)."
            skip_download=true
        elif [[ -f "${target_jar}.bk" ]] && is_valid_jar "${target_jar}.bk" "$min_jar_size"; then
            echo "Restoring previous backup of Burp Suite Professional v$burp_ver (${jar_name}.bk)..."
            cp -f "${target_jar}.bk" "$target_jar"
            skip_download=true
        elif compgen -G "$REPO_DIR/burpsuite_pro_v*.jar" >/dev/null; then
            local latest_valid_jar=""
            local latest_valid_ver=""
            while IFS= read -r candidate; do
                [[ -z "$candidate" || ! -f "$candidate" ]] && continue
                if is_valid_jar "$candidate" "$min_jar_size"; then
                    latest_valid_jar="$candidate"
                    latest_valid_ver="$(basename "$candidate" | sed -E 's/^burpsuite_pro_v(.*)\.jar$/\1/')"
                fi
            done < <(find "$REPO_DIR" -maxdepth 1 -name 'burpsuite_pro_v*.jar' 2>/dev/null | sort -V)

            if [[ -n "$latest_valid_jar" ]]; then
                if [[ "$explicit_version" == true ]]; then
                    if [[ "$latest_valid_ver" == "$burp_ver" ]]; then
                        echo "Found requested version $burp_ver already installed ($latest_valid_jar). Skipping download."
                        skip_download=true
                        jar_name="$(basename "$latest_valid_jar")"
                    elif version_ge "$latest_valid_ver" "$burp_ver"; then
                        echo "Detected newer version installed ($latest_valid_ver), but requested explicit downgrade to $burp_ver."
                        echo "Proceeding to download target version $burp_ver..."
                        skip_download=false
                    else
                        echo "Found older version ($latest_valid_ver). Upgrading to requested $burp_ver..."
                        skip_download=false
                    fi
                else
                    if version_ge "$latest_valid_ver" "$burp_ver"; then
                        echo "Found installed version $latest_valid_ver, which is >= requested $burp_ver. Skipping download."
                        skip_download=true
                        jar_name="$(basename "$latest_valid_jar")"
                        burp_ver="$latest_valid_ver"
                    else
                        echo "Found older version ($latest_valid_ver). Upgrading to $burp_ver..."
                    fi
                fi
            fi
        fi
    fi

    if [[ "$skip_download" == false ]]; then
        echo "Downloading Burp Suite Professional $burp_ver ($jar_name)..."
        local jar_downloaded=false
        if command -v aria2c &>/dev/null; then
            echo "Using aria2c accelerator (16 connections)..."
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$jar_name.tmp" "$download_url"; then
                if is_valid_jar "$jar_name.tmp" "$min_jar_size"; then
                    jar_downloaded=true
                fi
            fi
            rm -f "$REPO_DIR/$jar_name.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$jar_downloaded" == false ]] && command -v curl &>/dev/null; then
            echo "Using curl with auto-resume..."
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$jar_name.tmp" "$download_url"; then
                if is_valid_jar "$jar_name.tmp" "$min_jar_size"; then
                    jar_downloaded=true
                fi
            fi
        fi
        if [[ "$jar_downloaded" == false ]] && command -v wget &>/dev/null; then
            echo "Using wget fallback..."
            if wget -O "$jar_name.tmp" --quiet --show-progress "$download_url"; then
                if is_valid_jar "$jar_name.tmp" "$min_jar_size"; then
                    jar_downloaded=true
                fi
            fi
        fi

        if [[ "$jar_downloaded" == false || ! -f "$jar_name.tmp" ]] || ! is_valid_jar "$jar_name.tmp" "$min_jar_size"; then
            echo "ERROR: Failed to download valid Burp Suite JAR file (archive corrupted or truncated)." >&2
            rm -f "$jar_name.tmp" "$REPO_DIR/$jar_name.tmp.aria2" 2>/dev/null || true
            exit 1
        fi

        mv -f "$jar_name.tmp" "$jar_name"
    fi

    # Display checksums
    if [[ -f "$jar_name" ]]; then
        echo "--- File Checksums ---"
        echo "SHA256: $(sha256sum "$jar_name" | cut -d' ' -f1)"
        echo "MD5:    $(md5sum "$jar_name" | cut -d' ' -f1)"
    fi

    # Backup older Burp JARs only AFTER new jar has been fully verified and placed
    for old_jar in "$REPO_DIR"/burpsuite_pro_v*.jar; do
        if [[ -f "$old_jar" && "$(basename "$old_jar")" != "$jar_name" ]]; then
            echo "Backing up previous version $(basename "$old_jar") to $(basename "$old_jar").bk"
            mv -f "$old_jar" "${old_jar}.bk"
        fi
    done

    # Prune old .bk jars: keep at most the 2 most recent .bk files in $REPO_DIR (B10)
    local -a bk_files=()
    local bk
    local -A seen_bk=()
    for bk in "$REPO_DIR"/*.jar.bk "$REPO_DIR"/burpsuite_pro*.bk; do
        [ -f "$bk" ] || continue
        if [[ -n "${seen_bk["$bk"]:-}" ]]; then
            continue
        fi
        seen_bk["$bk"]=1
        local mtime
        mtime=$(stat -c %Y "$bk" 2>/dev/null || stat -f %m "$bk" 2>/dev/null || echo 0)
        bk_files+=("$mtime $bk")
    done

    if [ ${#bk_files[@]} -gt 2 ]; then
        local -a sorted_bks=()
        mapfile -t sorted_bks < <(printf '%s\n' "${bk_files[@]}" | sort -k1,1rn | cut -d' ' -f2-)
        local i
        for ((i = 2; i < ${#sorted_bks[@]}; i++)); do
            echo "Pruning older backup jar: $(basename "${sorted_bks[i]}")"
            rm -f "${sorted_bks[i]}"
        done
    fi

    # 4. Create or update clean launcher binary immediately after JAR installation (B3, B9)
    mkdir -p "$HOME/.local/bin"
    local launcher_path="$HOME/.local/bin/burpsuitepro"

    echo "Creating launcher script at $launcher_path..."
    cat <<EOF >"$launcher_path"
#!/bin/bash
# ==============================================================================
# Burp Suite Professional Advanced Launcher
# Non-reparenting WM compatibility, dynamic memory, GC tuning, HiDPI scaling,
# robust CLI path resolution, conflict detection, diagnostics & crash logging.
# ==============================================================================

# Non-reparenting WM compatibility: set only for tiling/non-reparenting window managers
# (i3, sway, bspwm, dwm, hyprland, xmonad, river, niri, etc.).
# Explicitly unset on KDE (KWin), GNOME (Mutter), XFCE, Cinnamon, and MATE where
# _JAVA_AWT_WM_NONREPARENTING=1 causes blank popups, detached menus, and positioning glitches.
desktop_env="\${XDG_CURRENT_DESKTOP:-}:\${DESKTOP_SESSION:-}"
desktop_env_lower="\${desktop_env,,}"
if echo "\$desktop_env_lower" | grep -qE "kde|plasma|gnome|xfce|cinnamon|mate"; then
    unset _JAVA_AWT_WM_NONREPARENTING
elif echo "\$desktop_env_lower" | grep -qE "i3|sway|bspwm|dwm|hyprland|xmonad|qtile|awesome|river|niri"; then
    export _JAVA_AWT_WM_NONREPARENTING=1
fi

# Detect active X11 / XWayland display safely without destroying valid DISPLAY
detect_x11_display() {
    if [ -n "\${DISPLAY:-}" ]; then
        if command -v xdpyinfo &>/dev/null; then
            if xdpyinfo -display "\$DISPLAY" >/dev/null 2>&1; then
                return 0
            fi
            unset DISPLAY
        elif command -v xset &>/dev/null; then
            if xset -display "\$DISPLAY" q >/dev/null 2>&1; then
                return 0
            fi
            unset DISPLAY
        else
            # Neither probe tool available; trust DISPLAY if socket exists or assume valid
            local disp_num="\${DISPLAY#*:}"
            disp_num="\${disp_num%%.*}"
            if [ -z "\$disp_num" ] || [ -S "/tmp/.X11-unix/X\${disp_num}" ] || [ -e "/tmp/.X11-unix/X\${disp_num}" ]; then
                return 0
            fi
        fi
    fi

    # Probe /tmp/.X11-unix/X* sockets
    for sock in /tmp/.X11-unix/X*; do
        [ -e "\$sock" ] || [ -S "\$sock" ] || continue
        disp_num="\${sock##*/X}"
        [[ "\$disp_num" =~ ^[0-9]+\$ ]] || continue
        if command -v xdpyinfo &>/dev/null; then
            if xdpyinfo -display ":\$disp_num" >/dev/null 2>&1; then
                export DISPLAY=":\${disp_num}"
                return 0
            fi
        elif command -v xset &>/dev/null; then
            if xset -display ":\$disp_num" q >/dev/null 2>&1; then
                export DISPLAY=":\${disp_num}"
                return 0
            fi
        elif [ -S "\$sock" ]; then
            export DISPLAY=":\${disp_num}"
            return 0
        fi
    done

    # If running under Wayland and no X socket found yet, XWayland may start on demand
    if [ -n "\${WAYLAND_DISPLAY:-}" ]; then
        for _ in 1 2 3 4 5 6; do
            sleep 0.5
            for sock in /tmp/.X11-unix/X*; do
                [ -e "\$sock" ] || [ -S "\$sock" ] || continue
                disp_num="\${sock##*/X}"
                [[ "\$disp_num" =~ ^[0-9]+\$ ]] || continue
                if (command -v xdpyinfo &>/dev/null && xdpyinfo -display ":\$disp_num" >/dev/null 2>&1) || \\
                   (command -v xset &>/dev/null && xset -display ":\$disp_num" q >/dev/null 2>&1) || \\
                   [ -S "\$sock" ]; then
                    export DISPLAY=":\${disp_num}"
                    return 0
                fi
            done
        done
        echo "[!] Warning: No responding X11/XWayland display found for Wayland session (\$WAYLAND_DISPLAY)." >&2
        echo "    Burp Suite requires XWayland. If launch fails, ensure xorg-xwayland is installed." >&2
        export DISPLAY=:0
        return 0
    fi

    export DISPLAY=:0
}

detect_x11_display

REPO_DIR="\${REPO_DIR:-$REPO_DIR}"
DEFAULT_JAR_NAME="$jar_name"
DEFAULT_BURP_VER="$burp_ver"

# Dynamic JAR resolution: check BURP_JAR override first, then newest valid jar
if [ -n "\${BURP_JAR:-}" ]; then
    if [ -f "\$BURP_JAR" ]; then
        RESOLVED_JAR="\$BURP_JAR"
        JAR_NAME="\$(basename "\$BURP_JAR")"
    elif [ -f "\$REPO_DIR/\$BURP_JAR" ]; then
        RESOLVED_JAR="\$REPO_DIR/\$BURP_JAR"
        JAR_NAME="\$BURP_JAR"
    else
        echo "ERROR: Specified BURP_JAR '\$BURP_JAR' does not exist." >&2
        exit 1
    fi
else
    RESOLVED_JAR=""
    JAR_NAME=""
    while IFS= read -r candidate; do
        [ -z "\$candidate" ] && continue
        [ ! -f "\$candidate" ] && continue
        cand_size=\$(stat -c%s "\$candidate" 2>/dev/null || stat -f%z "\$candidate" 2>/dev/null || echo 0)
        if [ "\$cand_size" -gt 10485760 ]; then
            RESOLVED_JAR="\$candidate"
            JAR_NAME="\$(basename "\$candidate")"
        fi
    done < <(find "\$REPO_DIR" -maxdepth 1 -name 'burpsuite_pro_v*.jar' 2>/dev/null | sort -V)

    if [ -z "\$RESOLVED_JAR" ]; then
        JAR_NAME="\$DEFAULT_JAR_NAME"
        RESOLVED_JAR="\$REPO_DIR/\$JAR_NAME"
    fi
fi

BURP_VERSION="\${BURP_VERSION:-}"
if [ -z "\$BURP_VERSION" ]; then
    if [[ "\$JAR_NAME" =~ burpsuite_pro_v(.*)\.jar\$ ]]; then
        BURP_VERSION="\${BASH_REMATCH[1]}"
    else
        BURP_VERSION="\$DEFAULT_BURP_VER"
    fi
fi

# Locate best Java 21+ binary (respects BURP_JAVA or JAVA_HOME if provided)
JAVA_BIN="java"
if [ -n "\${BURP_JAVA:-}" ] && [ -x "\$BURP_JAVA" ]; then
    JAVA_BIN="\$BURP_JAVA"
elif [ -n "\${JAVA_HOME:-}" ] && [ -x "\$JAVA_HOME/bin/java" ]; then
    JAVA_BIN="\$JAVA_HOME/bin/java"
else
    for j in \\
        "/usr/lib/jvm/java-21-openjdk/bin/java" \\
        "/usr/lib/jvm/java-21-openjdk-amd64/bin/java" \\
        "/usr/lib/jvm/java-21-openjdk-arm64/bin/java" \\
        "/usr/lib/jvm/jre-21-openjdk/bin/java" \\
        "/usr/lib/jvm/java-21/bin/java" \\
        "/usr/lib/jvm/default-runtime/bin/java"; do
        if [ -x "\$j" ]; then
            JAVA_BIN="\$j"
            break
        fi
    done
fi

# Safe background log file location (prefer private XDG_RUNTIME_DIR)
LOG_DIR="\${XDG_RUNTIME_DIR:-/tmp}"
LOG_FILE="\$LOG_DIR/burpsuitepro-\${UID:-\$USER}.log"

# Port 8080 conflict detector with process inspection
check_port_8080() {
    local conflict=false
    local proc_desc=""

    if command -v ss >/dev/null 2>&1; then
        local ss_out
        ss_out=\$(ss -tlnpH 'sport = :8080' 2>/dev/null || true)
        if [ -n "\$ss_out" ]; then
            conflict=true
            if [[ "\$ss_out" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
                proc_desc="\${BASH_REMATCH[1]} (PID \${BASH_REMATCH[2]})"
            fi
        fi
    elif command -v lsof >/dev/null 2>&1; then
        local lsof_out
        lsof_out=\$(lsof -iTCP:8080 -sTCP:LISTEN -Pn -Fp -Fc 2>/dev/null || true)
        if [ -n "\$lsof_out" ]; then
            conflict=true
            local l_pid l_cmd
            l_pid=\$(echo "\$lsof_out" | grep -m1 '^p' | cut -c2- || true)
            l_cmd=\$(echo "\$lsof_out" | grep -m1 '^c' | cut -c2- || true)
            [ -n "\$l_cmd" ] && proc_desc="\$l_cmd (PID \$l_pid)"
        fi
    fi

    if [ "\$conflict" = true ]; then
        local msg="Port 8080 is already in use by \${proc_desc:-another process}."
        if [ -t 1 ]; then
            echo "[!] Warning: \$msg" >&2
            echo "    Burp Suite default proxy listener may conflict. Close the conflicting app or reconfigure listeners." >&2
        elif command -v notify-send &>/dev/null; then
            notify-send -u normal -i burpsuitepro "Burp Suite Port Conflict" "\$msg Burp's default proxy listener may fail to bind." 2>/dev/null || true
        fi
        return 1
    fi
    return 0
}

# Resolve relative paths before changing working directory
resolve_abs_path() {
    local target="\$1"
    [ -z "\$target" ] && return
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "\$target" 2>/dev/null && return
    fi
    if command -v readlink >/dev/null 2>&1; then
        readlink -m "\$target" 2>/dev/null && return
        readlink -f "\$target" 2>/dev/null && return
    fi
    if [[ "\$target" = /* ]]; then
        echo "\$target"
    else
        echo "\$PWD/\$target"
    fi
}

BURP_ARGS=()
HAS_PROJECT_FILE=false
FORCE_NEW=0
DRY_RUN=0
PRINT_CMD_ONLY=0
DO_DIAG=false
DO_BURP_DIAG=false
DO_BURP_HELP=false
DO_BURP_VERSION=false

while [ \$# -gt 0 ]; do
    case "\$1" in
        -h|--help)
            cat <<'HLP'
Burp Suite Professional Launcher

Usage: burpsuitepro [OPTIONS] [BURP_ARGUMENTS...]
       burpsuitepro [PROJECT_FILE.burp]

Wrapper Options:
  -k, --keygen             Launch the key loader / keygen (loader.jar)
  -v, --version            Display Burp Suite & Java runtime version information
      --burp-version       Query Burp Suite JAR directly for version details
  -p, --path               Display Burp Suite installation directory path
  -j, --jar                Display the resolved Burp Suite JAR path
  -t, --trust-ca           Auto-import Burp CA certificate into system & browsers
      --new-window         Launch a new instance even if Burp is already running
  -n, --dry-run            Preview execution environment and Java command line without launching
      --print-cmd          Print only the full executable Java command line without launching
  -d, --diag,
      --diagnostics        Display full launcher diagnostics and run native Burp diagnostics
      --burp-diag          Run native Burp Suite diagnostics only
      --log                View the background / GUI execution log
  -h, --help               Show this help message
      --burp-help          Query Burp Suite JAR directly for native CLI help

Burp Suite Native Arguments:
  --project-file <file>    Open or create specified project file (relative paths supported)
  --config-file <file>     Load project configuration file(s) (can be repeated)
  --user-config-file <file> Load user configuration file(s) (can be repeated)
  --disable-extensions     Prevent loading of extensions on startup
  --use-defaults           Start with default settings
  --diagnostics            Print native diagnostic information and exit
  --collaborator-server    Run in Collaborator server mode
  --collaborator-config <file>
                           Specify Collaborator server configuration file
  --data-dir <dir>         Specify data directory
  --auto-repair            Automatically repair a corrupted project file
  --unpause-spider-and-scanner
                           Do not pause Spider and Scanner when opening existing project
  --disable-auto-update    Suppress auto-update checks
  --developer-extension-class-name <name>
                           Fully qualified name of locally-developed extension class

Environment Variables:
  BURP_JAR                 Path or filename of Burp JAR to run (e.g. BURP_JAR=burpsuite_pro_v2026.11.jar)
  BURP_MAX_RAM             Maximum Java heap memory (e.g. 8g, 8192m, 60%, or -Xmx8g; defaults to 50% RAM)
                           (Also respects BURP_MEMORY or BURP_RAM)
  BURP_GC                  Garbage collector override: ZGC, G1, Parallel, Shenandoah, or none
  BURP_JAVA_OPTS           Custom JVM flags appended to command line (preserves required opens)
  JAVA_OPTS                Standard JVM flags (appended before BURP_JAVA_OPTS)
  BURP_SCALE               UI scaling factor (e.g. BURP_SCALE=1, 1.25, 2; overrides -Dsun.java2d.uiScale)
  BURP_TOOLKIT             Override AWT toolkit (defaults to sun.awt.X11.XToolkit for Wayland/X11)
  BURP_JAVA                Path to explicit java binary
  _JAVA_AWT_WM_NONREPARENTING
                           Set to 1 for tiling window managers (auto-detected for i3, sway, hyprland, etc.)

Note:
  Positional project files (e.g. 'burpsuitepro project.burp') are automatically
  resolved to absolute paths and mapped to '--project-file'.
HLP
            exit 0
            ;;
        --burp-help)
            DO_BURP_HELP=true
            shift
            ;;
        -v|--version)
            echo "Burp Suite Professional v\$BURP_VERSION (\$JAR_NAME)"
            echo "Java Runtime: \$("\$JAVA_BIN" -version 2>&1 | head -n 1)"
            exit 0
            ;;
        --burp-version)
            DO_BURP_VERSION=true
            shift
            ;;
        -k|--keygen)
            echo "Starting Burp Suite Keygen / Loader..."
            exec "\$JAVA_BIN" -jar "\$REPO_DIR/loader.jar"
            ;;
        -p|--path)
            echo "\$REPO_DIR"
            exit 0
            ;;
        -j|--jar)
            echo "\$RESOLVED_JAR"
            exit 0
            ;;
        -t|--trust-ca)
            shift
            if [ -x "\$REPO_DIR/burp-trust-ca.sh" ]; then
                exec "\$REPO_DIR/burp-trust-ca.sh" "\$@"
            else
                echo "ERROR: CA trust script not found at \$REPO_DIR/burp-trust-ca.sh" >&2
                exit 1
            fi
            ;;
        --new-window|--new-instance|--force-new)
            FORCE_NEW=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        --print-cmd)
            PRINT_CMD_ONLY=1
            shift
            ;;
        -d|--diag|--diagnostics)
            DO_DIAG=true
            shift
            ;;
        --burp-diag)
            DO_BURP_DIAG=true
            shift
            ;;
        --log)
            echo "Log File: \$LOG_FILE"
            if [ -f "\$LOG_FILE" ]; then
                echo "--- Recent Log Output (last 50 lines) ---"
                tail -n 50 "\$LOG_FILE"
            else
                echo "No background log file found yet."
            fi
            exit 0
            ;;
        --project-file)
            HAS_PROJECT_FILE=true
            if [ \$# -ge 2 ]; then
                BURP_ARGS+=("--project-file" "\$(resolve_abs_path "\$2")")
                shift 2
            else
                BURP_ARGS+=("\$1")
                shift
            fi
            ;;
        --project-file=*)
            HAS_PROJECT_FILE=true
            val="\${1#*=}"
            BURP_ARGS+=("--project-file=\$(resolve_abs_path "\$val")")
            shift
            ;;
        --config-file|--user-config-file|--collaborator-config|--data-dir)
            flag="\$1"
            if [ \$# -ge 2 ]; then
                BURP_ARGS+=("\$flag" "\$(resolve_abs_path "\$2")")
                shift 2
            else
                BURP_ARGS+=("\$flag")
                shift
            fi
            ;;
        --config-file=*|--user-config-file=*|--collaborator-config=*|--data-dir=*)
            flag="\${1%%=*}"
            val="\${1#*=}"
            BURP_ARGS+=("\${flag}=\$(resolve_abs_path "\$val")")
            shift
            ;;
        --developer-extension-class-name)
            BURP_ARGS+=("\$1")
            shift
            if [ \$# -gt 0 ]; then
                BURP_ARGS+=("\$1")
                shift
            fi
            ;;
        --developer-extension-class-name=*)
            BURP_ARGS+=("\$1")
            shift
            ;;
        -*)
            BURP_ARGS+=("\$1")
            shift
            ;;
        *)
            if [[ "\$1" =~ \.(burp|burpstate)\$ ]] && [ "\$HAS_PROJECT_FILE" = false ]; then
                HAS_PROJECT_FILE=true
                BURP_ARGS+=("--project-file" "\$(resolve_abs_path "\$1")")
            elif [ -e "\$1" ] || [[ "\$1" =~ / ]] || [[ "\$1" =~ \.(json|xml|config)\$ ]]; then
                BURP_ARGS+=("\$(resolve_abs_path "\$1")")
            else
                BURP_ARGS+=("\$1")
            fi
            shift
            ;;
    esac
done

# If Burp is already running and no new window or project file requested, focus existing window
if [ "\$FORCE_NEW" -eq 0 ] && [ "\$DRY_RUN" -eq 0 ] && [ "\$PRINT_CMD_ONLY" -eq 0 ] && [ "\$DO_DIAG" = false ] && [ "\$DO_BURP_DIAG" = false ] && [ "\$DO_BURP_HELP" = false ] && [ "\$DO_BURP_VERSION" = false ]; then
    running_pid=\$(pgrep -f '(java|openjdk).*[b]urpsuite_pro_v.*\.jar' | head -n1 || true)
    if [ -n "\$running_pid" ] && [ "\$HAS_PROJECT_FILE" = false ]; then
        focused=0
        if command -v xdotool &>/dev/null; then
            for wid in \$(xdotool search --class "burp" 2>/dev/null || xdotool search --name "Burp Suite" 2>/dev/null); do
                wname="\$(xdotool getwindowname "\$wid" 2>/dev/null || true)"
                if [[ "\$wname" =~ "Burp Suite" ]]; then
                    xdotool windowactivate "\$wid" 2>/dev/null || xdotool windowraise "\$wid" 2>/dev/null || true
                    focused=1
                    break
                fi
            done
            if [ "\$focused" -eq 0 ]; then
                first_wid=\$(xdotool search --class "burp" 2>/dev/null | tail -n1 || true)
                if [ -n "\$first_wid" ]; then
                    xdotool windowactivate "\$first_wid" 2>/dev/null || xdotool windowraise "\$first_wid" 2>/dev/null || true
                    focused=1
                fi
            fi
        fi

        if [ -t 1 ]; then
            echo "Burp Suite Professional is already running (PID \$running_pid). Focused existing window."
            echo "Use 'burpsuitepro --new-window' if you need to open an additional instance."
        elif command -v notify-send &>/dev/null; then
            notify-send -u low -i burpsuitepro "Burp Suite Professional" "Focused existing instance (PID \$running_pid)." 2>/dev/null || true
        fi
        exit 0
    fi
fi

# Parse user-supplied JVM options from JAVA_OPTS and BURP_JAVA_OPTS safely
USER_OPTS=()
if [ -n "\${JAVA_OPTS:-}" ]; then
    read -r -a _STD_OPTS <<< "\$JAVA_OPTS"
    USER_OPTS+=("\${_STD_OPTS[@]}")
fi
if [ -n "\${BURP_JAVA_OPTS:-}" ]; then
    read -r -a _BURP_OPTS <<< "\$BURP_JAVA_OPTS"
    USER_OPTS+=("\${_BURP_OPTS[@]}")
fi

user_has_gc=0
user_has_mem=0
for uopt in "\${USER_OPTS[@]}"; do
    if [[ "\$uopt" =~ ^-XX:\+Use.*GC\$ ]]; then
        user_has_gc=1
    fi
    if [[ "\$uopt" =~ ^(-Xmx|-XX:MaxRAMPercentage=) ]]; then
        user_has_mem=1
    fi
done

# Dynamic memory sizing (defaults to 50% RAM; respects explicit percentages, sizes, or user flags)
BURP_MEM_VAL="\${BURP_MAX_RAM:-\${BURP_MEMORY:-\${BURP_RAM:-}}}"
MEM_OPTS=("-XX:MaxRAMPercentage=50")
if [ -n "\$BURP_MEM_VAL" ]; then
    if [[ "\$BURP_MEM_VAL" =~ ^([0-9]+)%\$ ]]; then
        MEM_OPTS=("-XX:MaxRAMPercentage=\${BASH_REMATCH[1]}")
    elif [[ "\$BURP_MEM_VAL" =~ ^-Xmx ]]; then
        MEM_OPTS=("\$BURP_MEM_VAL")
    elif [[ "\$BURP_MEM_VAL" =~ ^[0-9]+[gGmMkK]\$ ]]; then
        MEM_OPTS=("-Xmx\$BURP_MEM_VAL")
    elif [[ "\$BURP_MEM_VAL" =~ ^[0-9]+\$ ]]; then
        if [ "\$BURP_MEM_VAL" -le 100 ]; then
            MEM_OPTS=("-XX:MaxRAMPercentage=\$BURP_MEM_VAL")
        else
            MEM_OPTS=("-Xmx\${BURP_MEM_VAL}m")
        fi
    else
        MEM_OPTS=("-Xmx\$BURP_MEM_VAL")
    fi
elif [ "\$user_has_mem" -eq 1 ]; then
    MEM_OPTS=()
fi

# Garbage Collector configuration with Generational ZGC & G1GC fallback
GC_OPTS=()
if [ "\$user_has_gc" -eq 0 ]; then
    if [ -n "\${BURP_GC:-}" ]; then
        case "\${BURP_GC,,}" in
            zgc)
                if "\$JAVA_BIN" -XX:+UseZGC -XX:+ZGenerational -version >/dev/null 2>&1; then
                    GC_OPTS=("-XX:+UseZGC" "-XX:+ZGenerational")
                elif "\$JAVA_BIN" -XX:+UseZGC -version >/dev/null 2>&1; then
                    GC_OPTS=("-XX:+UseZGC")
                else
                    echo "[!] Warning: ZGC requested via BURP_GC but unsupported by \$JAVA_BIN. Falling back to G1GC." >&2
                    GC_OPTS=("-XX:+UseG1GC")
                fi
                ;;
            g1|g1gc)
                GC_OPTS=("-XX:+UseG1GC")
                ;;
            parallel)
                GC_OPTS=("-XX:+UseParallelGC")
                ;;
            shenandoah)
                GC_OPTS=("-XX:+UseShenandoahGC")
                ;;
            none)
                GC_OPTS=()
                ;;
            *)
                echo "[!] Warning: Unknown BURP_GC='\$BURP_GC'. Using auto-detected GC." >&2
                if "\$JAVA_BIN" -XX:+UseZGC -XX:+ZGenerational -version >/dev/null 2>&1; then
                    GC_OPTS=("-XX:+UseZGC" "-XX:+ZGenerational")
                elif "\$JAVA_BIN" -XX:+UseZGC -version >/dev/null 2>&1; then
                    GC_OPTS=("-XX:+UseZGC")
                else
                    GC_OPTS=("-XX:+UseG1GC")
                fi
                ;;
        esac
    else
        GC_OPTS=("-XX:+UseG1GC")
        if "\$JAVA_BIN" -XX:+UseZGC -XX:+ZGenerational -version >/dev/null 2>&1; then
            GC_OPTS=("-XX:+UseZGC" "-XX:+ZGenerational")
        elif "\$JAVA_BIN" -XX:+UseZGC -version >/dev/null 2>&1; then
            GC_OPTS=("-XX:+UseZGC")
        fi
    fi
fi

# UI Scaling (HiDPI / KDE Wayland Fractional Scaling)
BURP_SCALE_OPTS=()
BURP_SCALE_VAL="\${BURP_SCALE:-\${BURP_UI_SCALE:-}}"
if [ -n "\$BURP_SCALE_VAL" ]; then
    BURP_SCALE_OPTS=("-Dsun.java2d.uiScale=\$BURP_SCALE_VAL" "-Dflatlaf.uiScale=\$BURP_SCALE_VAL")
else
    if [ -n "\${WAYLAND_DISPLAY:-}" ] && [[ "\${XDG_CURRENT_DESKTOP:-}" =~ KDE|Plasma ]]; then
        kwin_xwayland_scale=\$(kreadconfig6 --file kwinrc --group Xwayland --key Scale 2>/dev/null \\
            || kreadconfig5 --file kwinrc --group Xwayland --key Scale 2>/dev/null || echo "")
        if [ "\$kwin_xwayland_scale" = "0" ] || [ "\$kwin_xwayland_scale" = "false" ]; then
            # System handles XWayland scaling; lock Burp to 1.0 to prevent double-scaling blur
            BURP_SCALE_OPTS=("-Dsun.java2d.uiScale=1.0" "-Dflatlaf.uiScale=1.0")
        fi
    fi
fi

if [ ! -f "\$RESOLVED_JAR" ]; then
    echo "ERROR: Burp Suite JAR not found at '\$RESOLVED_JAR'." >&2
    exit 1
fi

BURP_TOOLKIT_VAL="\${BURP_TOOLKIT:-sun.awt.X11.XToolkit}"

if [ "\$DO_BURP_HELP" = true ]; then
    exec "\$JAVA_BIN" -jar "\$RESOLVED_JAR" --help
fi

if [ "\$DO_BURP_VERSION" = true ]; then
    exec "\$JAVA_BIN" -jar "\$RESOLVED_JAR" --version
fi

JVM_OPTS=(
    # Module openings declared in PortSwigger Burp Suite manifest & Swing internals
    --add-opens=java.desktop/javax.swing=ALL-UNNAMED
    --add-opens=java.desktop/java.awt=ALL-UNNAMED
    --add-opens=java.desktop/java.awt.color=ALL-UNNAMED
    --add-opens=java.base/java.lang=ALL-UNNAMED
    --add-opens=java.base/java.util=ALL-UNNAMED
    --add-opens=java.base/javax.crypto=ALL-UNNAMED
    --add-opens=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED
    # Module openings strictly required by loader.jar (ASM instrumentation)
    --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED
    --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED
    # Memory and Garbage Collection options
    "\${MEM_OPTS[@]}"
    "\${GC_OPTS[@]}"
    # Deduplicate repetitive HTTP header/string allocations in proxy history
    -XX:+UseStringDeduplication
    # Font and Desktop rendering
    -Dawt.useSystemAAFontSettings=lcd
    "\${BURP_SCALE_OPTS[@]}"
    -Dawt.toolkit="\$BURP_TOOLKIT_VAL"
    # User-customized JVM options (BURP_JAVA_OPTS / JAVA_OPTS)
    "\${USER_OPTS[@]}"
    # Bytecode instrumentation agent & Target application JAR
    -javaagent:"\$REPO_DIR/loader.jar"
    -jar "\$RESOLVED_JAR"
)

if [ "\$PRINT_CMD_ONLY" -eq 1 ]; then
    printf '%q ' "\$JAVA_BIN" "\${JVM_OPTS[@]}" "\${BURP_ARGS[@]}"
    echo ""
    exit 0
fi

if [ "\$DRY_RUN" -eq 1 ]; then
    echo "=== Burp Suite Execution Preview (Dry Run) ==="
    echo "Working Directory: \$REPO_DIR"
    echo "Environment:"
    echo "  DISPLAY=\${DISPLAY:-:0}"
    [ -n "\${WAYLAND_DISPLAY:-}" ] && echo "  WAYLAND_DISPLAY=\$WAYLAND_DISPLAY"
    [ -n "\${_JAVA_AWT_WM_NONREPARENTING:-}" ] && echo "  _JAVA_AWT_WM_NONREPARENTING=\$_JAVA_AWT_WM_NONREPARENTING"
    echo "Command Line:"
    printf "  %q" "\$JAVA_BIN"
    for opt in "\${JVM_OPTS[@]}"; do
        printf " %q" "\$opt"
    done
    for arg in "\${BURP_ARGS[@]}"; do
        printf " %q" "\$arg"
    done
    echo
    echo "==============================================="
    exit 0
fi

if [ "\$DO_DIAG" = true ]; then
    echo "================================================================================"
    echo "                      Burp Suite Professional Diagnostics                       "
    echo "================================================================================"
    echo "Launcher Path:        \$0"
    echo "Burp Repository:      \$REPO_DIR"
    echo "Resolved JAR:         \$RESOLVED_JAR"
    if [ -f "\$RESOLVED_JAR" ]; then
        jar_sz=\$(stat -c%s "\$RESOLVED_JAR" 2>/dev/null || stat -f%z "\$RESOLVED_JAR" 2>/dev/null || echo 0)
        echo "JAR Size:             \$(( jar_sz / 1024 / 1024 )) MB (\$jar_sz bytes)"
    else
        echo "JAR Status:           MISSING"
    fi
    echo "Burp Version:         \$BURP_VERSION"
    echo "Key Loader JAR:       \$REPO_DIR/loader.jar \$([ -f "\$REPO_DIR/loader.jar" ] && echo '[Present]' || echo '[MISSING]')"
    echo "Jython 2.7.4 JAR:     \$REPO_DIR/jython-standalone-2.7.4.jar \$([ -f "\$REPO_DIR/jython-standalone-2.7.4.jar" ] && echo '[Present]' || echo '[Not installed]')"
    echo "JRuby Complete JAR:   \$REPO_DIR/jruby-complete-9.4.9.0.jar \$([ -f "\$REPO_DIR/jruby-complete-9.4.9.0.jar" ] && echo '[Present]' || echo '[Not installed]')"
    echo "Burp Trust CA Script: \$REPO_DIR/burp-trust-ca.sh \$([ -x "\$REPO_DIR/burp-trust-ca.sh" ] && echo '[Present, Executable]' || echo '[MISSING]')"
    echo
    echo "--- Java Runtime ---"
    echo "Java Binary:          \$JAVA_BIN"
    j_ver=\$("\$JAVA_BIN" -version 2>&1 | head -n 1 || echo "unknown")
    echo "Java Version:         \$j_ver"
    echo "Heap Config:          \${MEM_OPTS[*]:-default}"
    echo "Garbage Collector:    \${GC_OPTS[*]:-default}"
    echo "AWT Toolkit:          \$BURP_TOOLKIT_VAL"
    if [ \${#BURP_SCALE_OPTS[@]} -gt 0 ]; then
        echo "UI Scaling:           \${BURP_SCALE_OPTS[*]}"
    else
        echo "UI Scaling:           Default (unscaled / automatic)"
    fi
    echo
    echo "--- Display & Environment ---"
    echo "Display Server:       \${DISPLAY:-not set}"
    echo "Wayland Display:      \${WAYLAND_DISPLAY:-not set}"
    echo "Desktop Environment:  \${XDG_CURRENT_DESKTOP:-not set} (\${DESKTOP_SESSION:-not set})"
    echo "AWT Non-reparenting:  \${_JAVA_AWT_WM_NONREPARENTING:-0 (unset)}"
    echo "Background Log File:  \${LOG_FILE}"
    echo
    echo "--- Network & Ports ---"
    check_port_8080 || true
    running_burps=\$(pgrep -f "(java|openjdk).*[b]urpsuite_pro_v.*\.jar" 2>/dev/null | tr '\n' ' ' | sed 's/ \$//' || true)
    if [ -n "\$running_burps" ]; then
        echo "[!] Active Burp Process: Detected running instance(s) with PID: \$running_burps"
    else
        echo "[OK] No other Burp Suite instances running"
    fi
    echo "================================================================================"
    echo
    echo "=== Running Native Burp Suite Diagnostics ==="
    cd "\$REPO_DIR" || exit 1
    coproc JAVA_PROC { "\$JAVA_BIN" "\${JVM_OPTS[@]}" --diagnostics 2>&1; }
    while IFS= read -r line <&"\${JAVA_PROC[0]}"; do
        echo "\$line"
        if [[ "\$line" =~ superuser ]]; then
            break
        fi
    done
    kill "\${JAVA_PROC_PID}" 2>/dev/null || true
    wait "\${JAVA_PROC_PID}" 2>/dev/null || true
    exit 0
fi

if [ "\$DO_BURP_DIAG" = true ]; then
    cd "\$REPO_DIR" || exit 1
    coproc JAVA_PROC { "\$JAVA_BIN" "\${JVM_OPTS[@]}" --diagnostics 2>&1; }
    while IFS= read -r line <&"\${JAVA_PROC[0]}"; do
        echo "\$line"
        if [[ "\$line" =~ superuser ]]; then
            break
        fi
    done
    kill "\${JAVA_PROC_PID}" 2>/dev/null || true
    wait "\${JAVA_PROC_PID}" 2>/dev/null || true
    exit 0
fi

# Conflict and instance warnings before launch
check_port_8080 || true

if [ -t 1 ]; then
    running_pids=\$(pgrep -f "(java|openjdk).*[b]urpsuite_pro_v.*\.jar" 2>/dev/null | tr '\n' ' ' | sed 's/ \$//' || true)
    if [ -n "\$running_pids" ]; then
        echo "[!] Notice: Another Burp Suite instance is currently running (PID: \$running_pids)." >&2
    fi
fi

cd "\$REPO_DIR" || exit 1

if [ -t 1 ]; then
    exec "\$JAVA_BIN" "\${JVM_OPTS[@]}" "\${BURP_ARGS[@]}"
else
    # Rotate previous session log
    if [ -f "\$LOG_FILE" ]; then
        mv -f "\$LOG_FILE" "\$LOG_FILE.old" 2>/dev/null || true
    fi

    "\$JAVA_BIN" "\${JVM_OPTS[@]}" "\${BURP_ARGS[@]}" >"\$LOG_FILE" 2>&1
    EXIT_CODE=\$?

    # Only notify on abnormal termination (exclude clean exit 0, SIGINT 130, SIGTERM 143)
    if [ \$EXIT_CODE -ne 0 ] && [ \$EXIT_CODE -ne 130 ] && [ \$EXIT_CODE -ne 143 ]; then
        exit_desc="Burp Suite process exited with error code \$EXIT_CODE"
        case \$EXIT_CODE in
            137) exit_desc="Burp Suite killed by OS / Out of Memory (SIGKILL). Consider increasing BURP_MAX_RAM." ;;
            139) exit_desc="Burp Suite crashed with JVM Segmentation Fault (SIGSEGV)." ;;
        esac

        ERR_MSG=\$(tail -n 8 "\$LOG_FILE" 2>/dev/null | tr -d '\000-\011\013-\037')
        [ -z "\$ERR_MSG" ] && ERR_MSG="\$exit_desc"
        NOTIFY_BODY=\$(printf "%s:\n\n%s\n\nLog: %s" "\$exit_desc" "\$ERR_MSG" "\$LOG_FILE")

        if command -v notify-send &>/dev/null; then
            notify-send -u critical -i burpsuitepro "Burp Suite Error" "\$NOTIFY_BODY" 2>/dev/null || true
        elif command -v kdialog &>/dev/null; then
            kdialog --error "\$NOTIFY_BODY" 2>/dev/null || true
        fi
        exit \$EXIT_CODE
    fi
fi
EOF
    chmod +x "$launcher_path"

    # System-wide binary symlink only when running as root
    if [[ $EUID -eq 0 ]]; then
        mkdir -p /usr/local/bin 2>/dev/null || true
        ln -sf "$launcher_path" /usr/local/bin/burpsuitepro 2>/dev/null || true
    fi

    # 5. Copy local assets and system integrations
    local core_dir="${BURP_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    echo "Copying shared configuration and icon..."
    if [[ -f "$core_dir/burp/.config.ini" ]]; then
        cp -f "$core_dir/burp/.config.ini" "$REPO_DIR/" 2>/dev/null || true
    fi
    if [[ -f "$core_dir/burp/burp_suite_pro_icon.svg" ]]; then
        cp -f "$core_dir/burp/burp_suite_pro_icon.svg" "$REPO_DIR/" 2>/dev/null || true
    fi
    if [[ -f "$core_dir/burp-trust-ca.sh" ]]; then
        cp -f "$core_dir/burp-trust-ca.sh" "$REPO_DIR/burp-trust-ca.sh"
        chmod +x "$REPO_DIR/burp-trust-ca.sh"
    fi

    install_burp_system_icons "$REPO_DIR/burp_suite_pro_icon.svg"
    install_burp_system_mime

    suppress_jre_warnings

    # Pre-seed Burp Suite license & preferences safely without overwriting other user settings (B1, B7)
    local prefs_dir="$HOME/.java/.userPrefs/burp"
    local prefs_file="$prefs_dir/prefs.xml"
    mkdir -p "$prefs_dir"

    local seed_license_key="license1"
    local seed_license_val="QKLM8/zjeX0FDxLCu5RTDbUc3jgF5M+7U+1qDz6yBjuvYAn2zh0uJq9gCfbOHS4mVlbyb7O0fZyFaQcK+3ebZC29Goqrc80aBZR6BQBSNDvdJqOWpxVZat/P1DHTsOB7cirx9E5NLm18OLtASpkVObKMOnfMiwYBBbqouffwTsxuqhOtj6ctAEjH92GhaVmYHSMHTuipOIEx38XYk+isqe4fYQGvpyOSW4/Ka96eY0fVQNzYUDnEnW5ecc0TG+dvW8jFwgo02yyQ+cLP+i8W8d96Kc8AopXsF67+60ceFTZobP8v3Otb7r6JAEK0TEIX7ZzHakGZTqad8sb559Lj5oHvt4dbkvNzJdrjNDe8OUYPWslw91/On6UQi41rEcj7lahwRRpdV9fYwAotUrHiu2YF87a8a5UXO0z0XvjA/6eKk7DAldfwcvtmDgH/NlzZuEVrO7AxMhGt4CNopbjkqtXB3PxMB6J0ZOnyMbH/tFY9oLoir25KQr7TPFkfydK5Jbf1cz5UKk8lXfAf/lqBOZxcYoZnyocgSLm169Jx6ur42wTreOONfBFqWGtdAUBYuQwVBe3GS4xtV9F8nsu1P7iEBWwFo7TTU0duxNsr5NLMtqebrpvN1lWnRXlVnFOGuodWEZ5VTp4IxQbmDc2puBHO35TOubsivJlLa7zpD7nOgfLVpSdoU3DK0/lBqpZI75P6VjyXviGWvmp/n8dBKLvE4cOhCvTvm4wvEJOpMhgz3YGzqTf/6u1Kv7A9Kxv3STVHx4cBF5hpjLsiRG/lfeG+56CFTvLdXMzRFX0Y9M="
    local seed_key2_name="zRHyUR2Op7fIprORODg24A=="
    local seed_key2_val="rbojo9jt6ZB24ppIimQBtBmKg228sphoRBryhZRnnpztuo5B0UqERnXyrKnEDFaaU1hUrjYaSgm8T2uGta23A0fdAgy15Rg7dzW1Du+TJqkzBnQzljo2tMOge1NHpJZ55ijGar+VxsqV4oDkWWKgNV3xz2rW1YyoiskDuk9pcCJcc2Q87RoG331t6HOdyhAJf8hCZRoALn/PaLu9g9puCMpDHUDwb1O9KhXjHkB0WuOpKOZyBeVXM9xJWXRwzHlKSOIwBXov3Cy1QMeb4Q3bnd8G1cpK76lqwzNavRycSVP1oxHZJJAPCZF2xk4kutYxKAtzV8pMkoYb5wqeo4lm73ee8hH6VDhZg+EWE+ll6gAAtONOltqkYiwYvkCkqtlOYKOM2YAMWwmknxRjkzh1tnyoWY2aeSDFzkj8SqasPkIZdVK8OBcd3vcRIBaGI47evaSkjA/d1cFClq2Oi/erkVN/zA75zZbfWt96rRIKhirMC2mVBQnyIXLt4VBsGgEjtZU5RvcYbhOf/zp4eNZOjAgB1kQrgoVHsb6PA8dfpoJ13zuuRn4Nwz1JH1uOdsM6CVSoZY9OnnD8ffAMWftJJ6tzLfa31yHLYwD/VzrfE3GaEd1Yh/3RTAy0y/ni9OzR0oGzy7FwDtC3j8UVnjeQqSN6fLL8Tnz57Neg5jWuyyKng6Npc0EW6s6u4S+l4nNMoNNNdaFWhSfo5xDRr6WOjdt+v6RGZevaa2fog50ImWDnmr6wsW0VTbyLf+Bg9V569QFpnTPBfRiFGDj36n5yNMn/GP+CqLDmGAVnVXmKoGjbwEq2HYbb9XNUPcpf+CyuXTzVkJrzWhS62kVOlaq6MgG7+XIDBl4g"

    echo "Configuring Burp Suite Professional license and preferences..."
    merge_pref_entry "$prefs_file" "burp.eula" "13"
    merge_pref_entry "$prefs_file" "use_community_edition" "false"
    merge_pref_entry "$prefs_file" "suite.alertsdisabledforjre-1115054815" "true"
    merge_pref_entry "$prefs_file" "suite.alertsdisabledforjre-3189538875" "true"
    merge_pref_entry "$prefs_file" "$seed_license_key" "$seed_license_val"
    merge_pref_entry "$prefs_file" "$seed_key2_name" "$seed_key2_val"

    # 6. Jython & JRuby Standalone Extensions & User Config
    local extension_warnings=()

    echo "Configuring Jython Standalone 2.7.4..."
    local min_jython_size=20971520 # 20MB
    if [[ -f "$JYTHON_FILE" ]] && is_valid_jar "$JYTHON_FILE" "$min_jython_size" && [[ "$force_download" == false ]]; then
        local jython_size
        jython_size="$(get_file_size "$JYTHON_FILE")"
        echo "Existing Jython standalone verified ($((jython_size / 1024 / 1024))MB)."
    else
        echo "Downloading Jython Standalone 2.7.4..."
        local download_ok=false
        if command -v aria2c &>/dev/null; then
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$JYTHON_JAR.tmp" "$JYTHON_URL" 2>/dev/null; then
                if is_valid_jar "$JYTHON_FILE.tmp" "$min_jython_size"; then
                    download_ok=true
                fi
            fi
            rm -f "$JYTHON_FILE.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$download_ok" == false ]] && command -v curl &>/dev/null; then
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$JYTHON_FILE.tmp" "$JYTHON_URL"; then
                if is_valid_jar "$JYTHON_FILE.tmp" "$min_jython_size"; then
                    download_ok=true
                fi
            fi
        fi
        if [[ "$download_ok" == false ]] && command -v wget &>/dev/null; then
            if wget -O "$JYTHON_FILE.tmp" --quiet --show-progress "$JYTHON_URL"; then
                if is_valid_jar "$JYTHON_FILE.tmp" "$min_jython_size"; then
                    download_ok=true
                fi
            fi
        fi

        if [[ "$download_ok" == true && -f "$JYTHON_FILE.tmp" ]] && is_valid_jar "$JYTHON_FILE.tmp" "$min_jython_size"; then
            mv -f "$JYTHON_FILE.tmp" "$JYTHON_FILE"
            echo "Successfully downloaded $JYTHON_JAR."
        else
            echo "WARNING: Failed to download valid Jython standalone jar ($JYTHON_URL)." >&2
            rm -f "$JYTHON_FILE.tmp" 2>/dev/null || true
            extension_warnings+=("Jython Standalone 2.7.4 (Python extensions unavailable)")
        fi
    fi

    echo "Configuring JRuby Standalone $JRUBY_VERSION..."
    local min_jruby_size=31457280 # 30MB
    if [[ -f "$JRUBY_FILE" ]] && is_valid_jar "$JRUBY_FILE" "$min_jruby_size" && [[ "$force_download" == false ]]; then
        local jruby_size
        jruby_size="$(get_file_size "$JRUBY_FILE")"
        echo "Existing JRuby standalone verified ($((jruby_size / 1024 / 1024))MB)."
    else
        echo "Downloading JRuby Standalone $JRUBY_VERSION..."
        local jruby_download_ok=false
        if command -v aria2c &>/dev/null; then
            if aria2c -x 16 -s 16 -j 16 -k 1M -c --file-allocation=none -d "$REPO_DIR" -o "$JRUBY_JAR.tmp" "$JRUBY_URL" 2>/dev/null; then
                if is_valid_jar "$JRUBY_FILE.tmp" "$min_jruby_size"; then
                    jruby_download_ok=true
                fi
            fi
            rm -f "$JRUBY_FILE.tmp.aria2" 2>/dev/null || true
        fi
        if [[ "$jruby_download_ok" == false ]] && command -v curl &>/dev/null; then
            if curl -fLC - --connect-timeout 10 --retry 3 --retry-delay 2 --progress-bar -o "$JRUBY_FILE.tmp" "$JRUBY_URL"; then
                if is_valid_jar "$JRUBY_FILE.tmp" "$min_jruby_size"; then
                    jruby_download_ok=true
                fi
            fi
        fi
        if [[ "$jruby_download_ok" == false ]] && command -v wget &>/dev/null; then
            if wget -O "$JRUBY_FILE.tmp" --quiet --show-progress "$JRUBY_URL"; then
                if is_valid_jar "$JRUBY_FILE.tmp" "$min_jruby_size"; then
                    jruby_download_ok=true
                fi
            fi
        fi

        if [[ "$jruby_download_ok" == true && -f "$JRUBY_FILE.tmp" ]] && is_valid_jar "$JRUBY_FILE.tmp" "$min_jruby_size"; then
            mv -f "$JRUBY_FILE.tmp" "$JRUBY_FILE"
            echo "Successfully downloaded $JRUBY_JAR."
        else
            echo "WARNING: Failed to download valid JRuby standalone jar ($JRUBY_URL)." >&2
            rm -f "$JRUBY_FILE.tmp" 2>/dev/null || true
            extension_warnings+=("JRuby Standalone $JRUBY_VERSION (Ruby extensions unavailable)")
        fi
    fi

    if [[ (-f "$JYTHON_FILE" && $(get_file_size "$JYTHON_FILE") -gt $min_jython_size) || (-f "$JRUBY_FILE" && $(get_file_size "$JRUBY_FILE") -gt $min_jruby_size) ]]; then
        echo "Configuring Burp Suite User Config for Jython & JRuby..."
        python3 - "$JYTHON_FILE" "$JRUBY_FILE" <<'PYEOF'
import json, os, sys
jython_path = sys.argv[1]
jruby_path = sys.argv[2]
config_dir = os.path.expanduser("~/.BurpSuite")
os.makedirs(config_dir, exist_ok=True)
for cfg in ("UserConfigPro.json", "UserConfig.json"):
    cf = os.path.join(config_dir, cfg)
    data = {}
    if os.path.isfile(cf):
        try:
            with open(cf, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}
    if not isinstance(data, dict): data = {}
    uo = data.setdefault("user_options", {})
    if not isinstance(uo, dict): uo = {}; data["user_options"] = uo
    ext = uo.setdefault("extender", {})
    if not isinstance(ext, dict): ext = {}; uo["extender"] = ext
    py = ext.setdefault("python", {})
    if not isinstance(py, dict): py = {}; ext["python"] = py
    if os.path.isfile(jython_path):
        py["location_of_jython_standalone_jar_file"] = jython_path
    ruby = ext.setdefault("ruby", {})
    if not isinstance(ruby, dict): ruby = {}; ext["ruby"] = ruby
    if os.path.isfile(jruby_path):
        ruby["location_of_jruby_jar_file"] = jruby_path
    tmp = cf + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, cf)
PYEOF
        echo "Jython 2.7.4 and JRuby 9.4.9.0 configured."
    fi

    # 7. Create desktop shortcut
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"
    local desktop_file="$desktop_dir/burpsuitepro.desktop"

    echo "Creating desktop entry at $desktop_file..."
    cat <<EOF >"$desktop_file"
[Desktop Entry]
Name=Burp Suite Professional
Comment=Burp Suite Professional - Web Application Security Testing
Exec=$launcher_path %F
Icon=burpsuitepro
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=burp-StartBurp
MimeType=application/x-burp-project;
Categories=Network;Security;Development;WebDevelopment;
Keywords=burp;suite;pro;web;security;scanner;
Path=$REPO_DIR
Actions=Keygen;TrustCA;

[Desktop Action Keygen]
Name=Burp Suite Pro Keygen / Loader
Exec=$launcher_path -k
Icon=burpsuitepro

[Desktop Action TrustCA]
Name=Trust Burp CA Certificate
Exec=$launcher_path --trust-ca
Icon=burpsuitepro
Terminal=true
EOF

    update-desktop-database "$desktop_dir" 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || kbuildsycoca6 2>/dev/null || kbuildsycoca5 2>/dev/null || true

    # System desktop shortcut only when explicitly running as root
    if [[ $EUID -eq 0 ]]; then
        local sys_desktop_dir="/usr/local/share/applications"
        mkdir -p "$sys_desktop_dir" 2>/dev/null || true
        cp -f "$desktop_file" "$sys_desktop_dir/burpsuitepro.desktop" 2>/dev/null || true
        update-desktop-database "$sys_desktop_dir" 2>/dev/null || true
    fi

    # 8. Start Key Loader & Burp Suite Pro if not skipped
    if [[ "$skip_launch" == false ]]; then
        # Verify active display for background launch
        if [ -z "${DISPLAY:-}" ]; then
            for sock in /tmp/.X11-unix/X*; do
                if [ -S "$sock" ] || [ -e "$sock" ]; then
                    disp_num="${sock##*/X}"
                    if [[ "$disp_num" =~ ^[0-9]+$ ]]; then
                        export DISPLAY=":${disp_num}"
                        break
                    fi
                fi
            done
            if [ -z "${DISPLAY:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
                export DISPLAY=:0
            fi
        fi

        local active_java
        active_java="$(find_java_bin)"

        if [ -f "$REPO_DIR/loader.jar" ]; then
            echo "Starting Key loader.jar in background..."
            nohup "$active_java" -jar "$REPO_DIR/loader.jar" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi

        echo "Starting Burp Suite Professional..."
        nohup "$launcher_path" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    else
        echo "Skipping application launch (--skip-launch specified)."
    fi

    if [[ ${#extension_warnings[@]} -gt 0 ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  ⚠  WARNING: Installation completed with extension errors:  ║"
        for w in "${extension_warnings[@]}"; do
            printf "║   - %-57s║\n" "$w"
        done
        echo "║  Burp Suite Pro is ready, but missing extensions will need   ║"
        echo "║  to be re-downloaded when network connectivity is restored.  ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo "=== Burp Suite Professional ($distro_label) installation completed with warnings ==="
    else
        echo "=== Burp Suite Professional ($distro_label) installation completed! ==="
    fi

    # Offer CA trust if active or standalone interactive
    if [[ "$skip_launch" == false ]]; then
        local cert_url="http://127.0.0.1:8080/cert"
        local cert_active=false
        local tmp_probe
        tmp_probe="$(mktemp "${TMPDIR:-/tmp}/burp-cert-check-XXXXXX.tmp" 2>/dev/null || mktemp /tmp/burp-cert-check-XXXXXX.tmp)"

        is_burp_cert() {
            if curl -sSL -f -m 2 "$cert_url" -o "$tmp_probe" 2>/dev/null && [ -s "$tmp_probe" ]; then
                if command -v openssl &>/dev/null; then
                    if openssl x509 -inform DER -in "$tmp_probe" -noout 2>/dev/null ||
                        openssl x509 -inform PEM -in "$tmp_probe" -noout 2>/dev/null; then
                        return 0
                    fi
                elif head -c 2 "$tmp_probe" 2>/dev/null | cmp -s <(printf "\x30\x82") - ||
                    grep -q "^-----BEGIN CERTIFICATE-----" "$tmp_probe" 2>/dev/null; then
                    return 0
                fi
            fi
            return 1
        }

        if is_burp_cert; then
            cert_active=true
        else
            echo "Waiting for Burp Suite proxy listener and CA certificate (up to 30s)..."
            for ((att = 1; att <= 10; att++)); do
                sleep 3
                if is_burp_cert; then
                    cert_active=true
                    break
                fi
                echo "  Waiting for proxy listener... ($((att * 3))/30s)"
            done
        fi
        rm -f "$tmp_probe"

        if [[ "$cert_active" == true ]]; then
            echo "Active Burp Suite proxy and valid CA certificate detected. Launching CA certificate trust..."
            "$launcher_path" --trust-ca || true
        else
            echo ""
            echo "To trust Burp CA certificate across browsers once Burp is running:"
            echo "  Run: burpsuitepro --trust-ca"
        fi
    fi
}
