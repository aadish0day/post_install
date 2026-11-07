#!/usr/bin/env bash
# ============================================================================
# Universal Burp Suite CA Certificate Trust Utility
# Automatically extracts Burp Suite CA certificate from the active proxy
# and imports it into:
#   1. System trust store (Arch / Debian / Kali / Fedora)
#   2. Detected browser profiles via certutil (Firefox, Zen, LibreWolf, Floorp, Waterfox)
#   3. Enterprise Roots policy (/etc/{browser}/policies/policies.json)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/burp-common.sh" ]; then
    # shellcheck source=lib/burp-common.sh
    source "$SCRIPT_DIR/burp-common.sh"
elif [ -f "$SCRIPT_DIR/../lib/burp-common.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/../lib/burp-common.sh"
fi

REPO_DIR="${REPO_DIR:-$HOME/Documents/Crack/Burpsuite-Professional}"
CERT_URL="${CERT_URL:-http://127.0.0.1:8080/cert}"
TRUST_ALL=false

# Helper for finding burp launcher if not already provided by burp-common.sh
if ! declare -F find_burp_bin >/dev/null; then
    find_burp_bin() {
        if [ -n "${BURP_BIN:-}" ] && [ "$BURP_BIN" != "none" ] && [ -x "$BURP_BIN" ]; then
            echo "$BURP_BIN"
            return 0
        fi
        local b
        for b in "$HOME/.local/bin/burpsuitepro" "/usr/local/bin/burpsuitepro" "$REPO_DIR/burpsuitepro"; do
            if [ -x "$b" ]; then
                echo "$b"
                return 0
            fi
        done
        return 1
    }
fi

show_help() {
    cat <<EOF
Universal Burp Suite CA Certificate Trust Utility

Usage: $(basename "$0") [OPTIONS]

Options:
  -a, --all, -y, --yes   Auto-trust certificate across all detected browsers without prompting
  -h, --help             Show this help message

EOF
}

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
    -a | --all | -y | --yes)
        TRUST_ALL=true
        shift
        ;;
    -h | --help)
        show_help
        exit 0
        ;;
    *)
        shift
        ;;
    esac
done

# Ensure required crypto utilities exist
if ! command -v openssl &>/dev/null; then
    echo "ERROR: 'openssl' command is required to parse, verify, and convert the Burp CA certificate." >&2
    exit 1
fi

IS_NON_INTERACTIVE=false
if [ ! -t 0 ] || [ ! -c /dev/tty ]; then
    IS_NON_INTERACTIVE=true
    TRUST_ALL=true
fi

echo "=================================================="
echo "    Burp Suite CA Certificate Trust Utility      "
echo "=================================================="

# Initialize tracking metrics
SYS_TRUST_STATUS="NOT_ATTEMPTED"
PROFILES_SUCCEEDED=()
PROFILES_FAILED=()
PROFILES_SKIPPED=()
POLICIES_SUCCEEDED=()
POLICIES_FAILED=()
POLICIES_SKIPPED=()

# Determine sudo availability
HAS_SUDO=false
if sudo -n true 2>/dev/null; then
    HAS_SUDO=true
elif [ "$IS_NON_INTERACTIVE" = true ] || [ ! -c /dev/tty ]; then
    HAS_SUDO=false
elif [ "$TRUST_ALL" = true ]; then
    if sudo -v 2>/dev/null; then
        HAS_SUDO=true
    fi
else
    if sudo -v 2>/dev/null; then
        HAS_SUDO=true
    fi
fi

if [ "$HAS_SUDO" = false ]; then
    if [ "$IS_NON_INTERACTIVE" = true ] || [ ! -c /dev/tty ]; then
        echo "[i] Running in non-interactive environment without passwordless sudo."
        echo "    System-level trust store and enterprise roots updates will be safely skipped."
    fi
fi

# 1. Verify proxy listener is active and serving a valid certificate
echo "Checking for running Burp Suite proxy at $CERT_URL..."

verify_burp_cert_endpoint() {
    local chk_tmp
    chk_tmp="$(mktemp "${TMPDIR:-/tmp}/burp-ca-chk-XXXXXX.tmp" 2>/dev/null || mktemp /tmp/burp-ca-chk-XXXXXX.tmp)"
    if curl -sSL -f -m 3 "$CERT_URL" -o "$chk_tmp" 2>/dev/null && [ -s "$chk_tmp" ]; then
        local cert_subj
        cert_subj="$(openssl x509 -inform DER -in "$chk_tmp" -noout -subject -issuer 2>/dev/null || \
                     openssl x509 -inform PEM -in "$chk_tmp" -noout -subject -issuer 2>/dev/null || true)"
        if [ -n "$cert_subj" ] && echo "$cert_subj" | grep -qi "PortSwigger"; then
            rm -f "$chk_tmp"
            return 0
        fi
    fi
    rm -f "$chk_tmp"
    return 1
}

if ! verify_burp_cert_endpoint; then
    if [ "$IS_NON_INTERACTIVE" = true ]; then
        echo "ERROR: Burp Suite proxy is not active at $CERT_URL (or not serving a valid PortSwigger certificate)." >&2
        echo "In non-interactive mode, auto-launching Burp Suite GUI is disabled to prevent process hangs." >&2
        echo "Please start Burp Suite first, then re-run with: burpsuitepro --trust-ca" >&2
        exit 1
    fi

    burp_bin="$(find_burp_bin 2>/dev/null || true)"
    if ! pgrep -f 'burpsuite_pro|burpsuite.*\.jar|net\.portswigger' >/dev/null 2>&1; then
        if [ -n "$burp_bin" ]; then
            echo "Burp Suite process not detected. Launching in background..."
            nohup "$burp_bin" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        else
            echo "ERROR: Burp Suite proxy is not running or not serving a valid certificate at $CERT_URL, and burpsuitepro launcher was not found." >&2
            echo "Please start Burp Suite with proxy listener on 127.0.0.1:8080 first." >&2
            exit 1
        fi
    else
        echo "Burp Suite process detected. Waiting for proxy listener..."
    fi

    echo "Waiting for Burp Suite proxy to become active at $CERT_URL (up to 45s)..."
    burp_ready=false
    for ((attempt = 1; attempt <= 15; attempt++)); do
        sleep 3
        if verify_burp_cert_endpoint; then
            burp_ready=true
            echo "  [✓] Burp Suite proxy is active and serving PortSwigger CA certificate (detected after $((attempt * 3))s)."
            break
        fi
        echo "  Waiting for proxy... ($((attempt * 3))/45s)"
    done

    if [ "$burp_ready" = false ]; then
        echo "ERROR: Burp Suite proxy did not serve a valid PortSwigger CA certificate at $CERT_URL within 45 seconds." >&2
        echo "Please ensure Burp Suite is running with proxy listener enabled on 127.0.0.1:8080 (or check if another service occupies port 8080)." >&2
        exit 1
    fi
else
    echo "[✓] Burp Suite proxy is active and ready."
fi

# 2. Download and convert certificate
tmp_der="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.der")"
tmp_crt="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.crt")"
# shellcheck disable=SC2317
cleanup() {
    rm -f "${tmp_der:-}" "${tmp_crt:-}"
}
trap cleanup EXIT INT TERM

echo "Downloading CA certificate from Burp Suite proxy..."
if ! curl -sSL --connect-timeout 5 --max-time 15 "$CERT_URL" -o "$tmp_der" || [ ! -s "$tmp_der" ]; then
    echo "ERROR: Failed to download CA certificate from $CERT_URL." >&2
    exit 1
fi

echo "Converting CA certificate from DER to CRT..."
if openssl x509 -inform DER -in "$tmp_der" -out "$tmp_crt" 2>/dev/null; then
    :
elif openssl x509 -inform PEM -in "$tmp_der" -out "$tmp_crt" 2>/dev/null; then
    :
else
    echo "ERROR: Failed to convert Burp CA certificate (downloaded payload is not a valid X.509 certificate)." >&2
    exit 1
fi

echo "Verifying certificate authenticity..."
cert_subj_issuer="$(openssl x509 -in "$tmp_crt" -noout -subject -issuer 2>/dev/null || true)"
if ! echo "$cert_subj_issuer" | grep -qi "PortSwigger"; then
    echo "ERROR: Certificate authenticity check failed!" >&2
    echo "Expected Subject or Issuer containing 'PortSwigger', but got:" >&2
    echo "$cert_subj_issuer" >&2
    echo "Aborting: Untrusted certificate will not be imported into system roots or browsers." >&2
    exit 1
fi

FINGERPRINT="$(openssl x509 -in "$tmp_crt" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)"
echo "  [✓] Verified PortSwigger CA certificate authenticity."
echo "      Subject/Issuer: $(echo "$cert_subj_issuer" | tr '\n' ' ')"
echo "      SHA256 Fingerprint: $FINGERPRINT"

# 3. Detect browser profiles
B_NAMES=()
B_DETAILS=()
B_PATHS=()

detect_browser() {
    local bname="$1"
    shift
    local search_dirs=()
    for d in "$@"; do
        [ -d "$d" ] && search_dirs+=("$d")
    done
    [ ${#search_dirs[@]} -eq 0 ] && return

    local profiles=()
    while IFS= read -r db; do
        [ -n "$db" ] && profiles+=("$(dirname "$db")")
    done < <(find "${search_dirs[@]}" -name "cert9.db" 2>/dev/null)

    if [ ${#profiles[@]} -gt 0 ]; then
        B_NAMES+=("$bname")
        local count=${#profiles[@]}
        [ "$count" -eq 1 ] && B_DETAILS+=("found 1 profile") || B_DETAILS+=("found $count profiles")
        local joined
        joined="$(
            IFS=:
            echo "${profiles[*]}"
        )"
        B_PATHS+=("$joined")
    fi
}

check_running_browsers() {
    local running=()
    local b_proc
    for b_proc in firefox firefox-esr firefox-bin librewolf librewolf-bin floorp floorp-bin waterfox waterfox-bin zen zen-bin; do
        if pgrep -x "$b_proc" >/dev/null 2>&1 || pgrep -f "(^|/)$b_proc(\s|$)" >/dev/null 2>&1; then
            local seen=false
            for r in "${running[@]}"; do
                if [ "$r" = "$b_proc" ]; then
                    seen=true
                    break
                fi
            done
            [ "$seen" = false ] && running+=("$b_proc")
        fi
    done
    if [ ${#running[@]} -gt 0 ]; then
        echo ""
        echo "=================================================="
        echo "[!] WARNING: Detected running browser process(es): ${running[*]}" >&2
        echo "    Open browsers lock their NSS database (cert9.db), which will cause" >&2
        echo "    certificate injection to fail." >&2
        echo "    Please close your browser(s) before proceeding." >&2
        echo "=================================================="
        if [ "$IS_NON_INTERACTIVE" = false ] && [ -c /dev/tty ]; then
            read -r -t 15 -p "Press ENTER once browser(s) are closed (or wait 15s to proceed)... " _ || true
            echo ""
        fi
    fi
}

if command -v certutil &>/dev/null; then
    detect_browser "Firefox" "$HOME/.mozilla" "$HOME/.config/mozilla" "$HOME/.var/app/org.mozilla.firefox"
    detect_browser "Zen Browser" "$HOME/.zen" "$HOME/.config/zen" "$HOME/.var/app/io.github.zen_browser.zen" "$HOME/.var/app/app.zen_browser.zen"
    detect_browser "LibreWolf" "$HOME/.librewolf" "$HOME/.config/librewolf" "$HOME/.var/app/io.gitlab.librewolf-community"
    detect_browser "Floorp" "$HOME/.floorp" "$HOME/.config/floorp" "$HOME/.var/app/one.ablaze.floorp"
    detect_browser "Waterfox" "$HOME/.waterfox" "$HOME/.config/waterfox" "$HOME/.var/app/net.waterfox.waterfox"

    selected_indices=()
    if [ ${#B_NAMES[@]} -gt 0 ]; then
        if [ "$TRUST_ALL" = true ]; then
            echo "Auto-selecting all detected browsers (${#B_NAMES[@]} found)."
            for ((idx = 0; idx < ${#B_NAMES[@]}; idx++)); do
                selected_indices+=("$idx")
            done
        elif [ "$IS_NON_INTERACTIVE" = false ] && [ -c /dev/tty ] && (command -v dialog &>/dev/null || command -v whiptail &>/dev/null); then
            tui_items=("ALL" "--> All detected browsers (Recommended)" "ON")
            for i in "${!B_NAMES[@]}"; do
                tui_items+=("$((i + 1))" "${B_NAMES[i]} (${B_DETAILS[i]})" "OFF")
            done
            tui_items+=("NONE" "--> None (OS System Store & Enterprise Roots only)" "OFF")

            term_lines=$(tput lines 2>/dev/null || echo 24)
            term_cols=$(tput cols 2>/dev/null || echo 80)
            [[ "$term_lines" =~ ^[0-9]+$ ]] || term_lines=24
            [[ "$term_cols" =~ ^[0-9]+$ ]] || term_cols=80

            box_width=72
            [ "$term_cols" -lt 78 ] && box_width=$((term_cols - 6))
            [ "$box_width" -lt 40 ] && box_width=40

            total_items=$((${#tui_items[@]} / 3))
            box_height=$((total_items + 9))
            [ "$box_height" -gt $((term_lines - 4)) ] && box_height=$((term_lines - 4))
            [ "$box_height" -lt 14 ] && box_height=14
            list_height=$total_items
            [ "$list_height" -gt $((box_height - 7)) ] && list_height=$((box_height - 7))
            [ "$list_height" -lt 4 ] && list_height=4

            tui_raw=""
            tui_rc=0
            if command -v dialog &>/dev/null; then
                tui_raw=$(dialog --no-hot-list --stdout \
                    --title "Burp Suite CA Certificate - Browser Trust" \
                    --checklist "Select browsers to trust the Burp CA certificate:\n(Use SPACE to toggle, ENTER to confirm)" \
                    "$box_height" "$box_width" "$list_height" "${tui_items[@]}" </dev/tty) || tui_rc=$?
            elif command -v whiptail &>/dev/null; then
                tui_raw=$(whiptail \
                    --title "Burp Suite CA Certificate - Browser Trust" \
                    --checklist "Select browsers to trust the Burp CA certificate:\n(Use SPACE to toggle, ENTER to confirm)" \
                    "$box_height" "$box_width" "$list_height" "${tui_items[@]}" 3>&1 1>&2 2>&3 </dev/tty) || tui_rc=$?
            fi

            if [ "$tui_rc" -eq 1 ] || [ "$tui_rc" -eq 255 ]; then
                echo "Certificate trust cancelled by user."
                exit 0
            fi

            parsed_tags=()
            for token in $(echo "$tui_raw" | tr -d '",'); do
                [ -n "$token" ] && parsed_tags+=("$token")
            done

            has_all=false
            has_none=false
            numeric_tags=()

            for tag in "${parsed_tags[@]}"; do
                if [ "$tag" = "ALL" ]; then
                    has_all=true
                elif [ "$tag" = "NONE" ]; then
                    has_none=true
                elif [[ "$tag" =~ ^[0-9]+$ ]] && [ "$tag" -ge 1 ] && [ "$tag" -le "${#B_NAMES[@]}" ]; then
                    numeric_tags+=("$((tag - 1))")
                fi
            done

            if [ "$has_none" = true ]; then
                echo "Skipping browser profile injection (NONE selected)."
                PROFILES_SKIPPED+=("Direct profile injection skipped (user selected NONE)")
            elif [ "$has_all" = true ]; then
                echo "Selecting all detected browsers."
                for ((idx = 0; idx < ${#B_NAMES[@]}; idx++)); do
                    selected_indices+=("$idx")
                done
            elif [ ${#numeric_tags[@]} -gt 0 ]; then
                selected_indices=("${numeric_tags[@]}")
            fi
        else
            # Default fallback when non-TUI terminal: trust all detected browsers
            for ((idx = 0; idx < ${#B_NAMES[@]}; idx++)); do
                selected_indices+=("$idx")
            done
        fi

        # Deduplicate and inject certificate
        unique_indices=()
        for idx in "${selected_indices[@]}"; do
            already=false
            for u in "${unique_indices[@]}"; do
                if [ "$u" -eq "$idx" ]; then
                    already=true
                    break
                fi
            done
            [ "$already" = false ] && unique_indices+=("$idx")
        done

        if [ ${#unique_indices[@]} -gt 0 ]; then
            check_running_browsers

            for sel_idx in "${unique_indices[@]}"; do
                b_name="${B_NAMES[sel_idx]}"
                echo "Installing Burp CA certificate into $b_name profiles..."
                IFS=: read -r -a paths <<<"${B_PATHS[sel_idx]}"
                for p in "${paths[@]}"; do
                    if [ -d "$p" ]; then
                        if certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "sql:$p" 2>/dev/null; then
                            echo "  [✓] Imported into profile (sql): $p"
                            PROFILES_SUCCEEDED+=("$b_name: $p (sql)")
                        elif certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "dbm:$p" 2>/dev/null; then
                            echo "  [✓] Imported into profile (dbm): $p"
                            PROFILES_SUCCEEDED+=("$b_name: $p (dbm)")
                        else
                            echo "  [✗] Failed to import into profile: $p (browser database locked by running process or write error)" >&2
                            PROFILES_FAILED+=("$b_name: $p (database locked/error)")
                        fi
                    fi
                done
            done
        fi
    else
        echo "No supported browser profiles detected."
        PROFILES_SKIPPED+=("Direct profile injection skipped (no browser profiles found)")
    fi
else
    echo "Note: certutil (nss / libnss3-tools) is not installed. Skipping direct profile injection."
    PROFILES_SKIPPED+=("Direct profile injection skipped (certutil not installed)")
fi

# 4. Install to OS System Trust Store
echo ""
echo "Installing CA certificate to system trust store (requires sudo)..."
if [ "$HAS_SUDO" = false ]; then
    if [ "$IS_NON_INTERACTIVE" = true ] || [ ! -c /dev/tty ]; then
        echo "[!] System CA trust store update skipped due to missing sudo credentials in non-interactive environment."
        SYS_TRUST_STATUS="SKIPPED (missing sudo credentials in non-interactive environment)"
    else
        echo "[!] System CA trust store update skipped (sudo authentication unavailable)."
        SYS_TRUST_STATUS="SKIPPED (sudo authentication unavailable)"
    fi
elif [ -f /etc/debian_version ] || command -v update-ca-certificates &>/dev/null; then
    # Debian / Ubuntu / Kali
    sys_cert_dir="/usr/local/share/ca-certificates"
    sys_cert="$sys_cert_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo update-ca-certificates; then
        echo "[✓] System trust store updated via update-ca-certificates ($sys_cert)."
        SYS_TRUST_STATUS="SUCCESS (update-ca-certificates: $sys_cert)"
    else
        echo "[!] Warning: Failed to update Debian/Kali system trust store." >&2
        SYS_TRUST_STATUS="FAILED (update-ca-certificates failed)"
    fi
elif [ -d /etc/pki/ca-trust/source/anchors ] || command -v update-ca-trust &>/dev/null; then
    # Fedora / RHEL
    sys_cert_dir="/etc/pki/ca-trust/source/anchors"
    sys_cert="$sys_cert_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo update-ca-trust; then
        echo "[✓] System trust store updated via update-ca-trust ($sys_cert)."
        SYS_TRUST_STATUS="SUCCESS (update-ca-trust: $sys_cert)"
    else
        echo "[!] Warning: Failed to update Fedora system trust store." >&2
        SYS_TRUST_STATUS="FAILED (update-ca-trust failed)"
    fi
elif [ -d /etc/ca-certificates/trust-source/anchors ] || [ -f /etc/arch-release ]; then
    # Arch Linux
    sys_anchor_dir="/etc/ca-certificates/trust-source/anchors"
    sys_cert="$sys_anchor_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_anchor_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo trust extract-compat; then
        echo "[✓] System trust store updated via trust extract-compat ($sys_cert)."
        SYS_TRUST_STATUS="SUCCESS (trust extract-compat: $sys_cert)"
    else
        echo "[!] Warning: Failed to update Arch system trust store." >&2
        SYS_TRUST_STATUS="FAILED (trust extract-compat failed)"
    fi
else
    # Fallback
    sys_cert_dir="/usr/local/share/ca-certificates"
    sys_cert="$sys_cert_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" 2>/dev/null && sudo chmod 644 "$sys_cert" 2>/dev/null && sudo update-ca-certificates 2>/dev/null; then
        echo "[✓] System trust store updated ($sys_cert)."
        SYS_TRUST_STATUS="SUCCESS (update-ca-certificates fallback: $sys_cert)"
    else
        echo "[!] Warning: Could not detect system CA trust store command." >&2
        SYS_TRUST_STATUS="FAILED (unrecognized system trust store architecture)"
    fi
fi

echo ""
echo "Note regarding Chromium-based browsers:"
echo "  Chromium-based browsers (Google Chrome, Chromium, Brave, Microsoft Edge, Vivaldi, Opera, Thorium)"
echo "  rely directly on the operating system system trust store. Once the system trust store is updated,"
echo "  these browsers will automatically trust the Burp Suite CA certificate without requiring"
echo "  profile-level database modifications. If system trust store installation is skipped or fails,"
echo "  Chromium-based browsers will not trust the Burp CA."

# 5. Enterprise Roots policy for Mozilla family
echo ""
echo "Configuring browser Enterprise Roots policies..."

is_browser_installed() {
    local b_id="$1"
    case "$b_id" in
    firefox)
        command -v firefox &>/dev/null || command -v firefox-esr &>/dev/null || \
        command -v firefox-bin &>/dev/null || command -v firefox-developer-edition &>/dev/null || \
        (command -v pacman &>/dev/null && (pacman -Qi firefox &>/dev/null || pacman -Qi firefox-esr-bin &>/dev/null || pacman -Qi firefox-developer-edition &>/dev/null)) || \
        (command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' firefox 2>/dev/null | grep -q "ok installed") || \
        (command -v rpm &>/dev/null && rpm -q firefox &>/dev/null) || \
        (command -v flatpak &>/dev/null && flatpak info org.mozilla.firefox &>/dev/null) || \
        (command -v snap &>/dev/null && snap list firefox &>/dev/null) || \
        [ -x /usr/lib/firefox/firefox ] || [ -x /usr/lib/firefox-esr/firefox-esr ] || [ -x /opt/firefox/firefox ]
        ;;
    librewolf)
        command -v librewolf &>/dev/null || command -v librewolf-bin &>/dev/null || \
        (command -v pacman &>/dev/null && (pacman -Qi librewolf &>/dev/null || pacman -Qi librewolf-bin &>/dev/null)) || \
        (command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' librewolf 2>/dev/null | grep -q "ok installed") || \
        (command -v rpm &>/dev/null && rpm -q librewolf &>/dev/null) || \
        (command -v flatpak &>/dev/null && flatpak info io.gitlab.librewolf-community &>/dev/null) || \
        [ -x /usr/lib/librewolf/librewolf ] || [ -x /opt/librewolf/librewolf ]
        ;;
    floorp)
        command -v floorp &>/dev/null || command -v floorp-bin &>/dev/null || \
        (command -v pacman &>/dev/null && (pacman -Qi floorp &>/dev/null || pacman -Qi floorp-bin &>/dev/null)) || \
        (command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' floorp 2>/dev/null | grep -q "ok installed") || \
        (command -v rpm &>/dev/null && rpm -q floorp &>/dev/null) || \
        (command -v flatpak &>/dev/null && flatpak info one.ablaze.floorp &>/dev/null) || \
        [ -x /usr/lib/floorp/floorp ] || [ -x /opt/floorp/floorp ]
        ;;
    waterfox)
        command -v waterfox &>/dev/null || command -v waterfox-bin &>/dev/null || command -v waterfox-g &>/dev/null || \
        (command -v pacman &>/dev/null && (pacman -Qi waterfox-bin &>/dev/null || pacman -Qi waterfox-g-bin &>/dev/null)) || \
        (command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' waterfox 2>/dev/null | grep -q "ok installed") || \
        (command -v rpm &>/dev/null && rpm -q waterfox &>/dev/null) || \
        (command -v flatpak &>/dev/null && flatpak info net.waterfox.waterfox &>/dev/null) || \
        [ -x /usr/lib/waterfox/waterfox ] || [ -x /opt/waterfox/waterfox ]
        ;;
    zen)
        command -v zen &>/dev/null || command -v zen-bin &>/dev/null || command -v zen-browser &>/dev/null || \
        (command -v pacman &>/dev/null && (pacman -Qi zen-browser-bin &>/dev/null || pacman -Qi zen-browser &>/dev/null)) || \
        (command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' zen-browser 2>/dev/null | grep -q "ok installed") || \
        (command -v rpm &>/dev/null && rpm -q zen-browser &>/dev/null) || \
        (command -v flatpak &>/dev/null && (flatpak info io.github.zen_browser.zen &>/dev/null || flatpak info app.zen_browser.zen &>/dev/null)) || \
        [ -x /usr/lib/zen/zen ] || [ -x /opt/zen/zen ] || [ -x /opt/zen-browser/zen ]
        ;;
    *)
        return 1
        ;;
    esac
}

update_enterprise_roots() {
    local bname="$1"
    local pdir="$2"
    local pfile="$pdir/policies.json"

    if [ "$HAS_SUDO" = false ]; then
        if [ "$IS_NON_INTERACTIVE" = true ] || [ ! -c /dev/tty ]; then
            echo "  [!] Skipped $bname enterprise roots policy ($pfile): missing sudo credentials in non-interactive environment."
            POLICIES_SKIPPED+=("$bname ($pfile: missing sudo credentials)")
        else
            echo "  [!] Skipped $bname enterprise roots policy ($pfile): sudo unavailable."
            POLICIES_SKIPPED+=("$bname ($pfile: sudo unavailable)")
        fi
        return 0
    fi

    if ! sudo mkdir -p "$pdir" 2>/dev/null; then
        echo "  [✗] Error: Failed to create policy directory $pdir" >&2
        POLICIES_FAILED+=("$bname ($pdir: mkdir failed)")
        return 1
    fi

    local tmp_pol
    tmp_pol="$(mktemp "${TMPDIR:-/tmp}/burp-pol-XXXXXX.json")"

    if [ -f "$pfile" ]; then
        # Back up existing policies.json before modifying
        if ! sudo cp -p "$pfile" "$pfile.bak" 2>/dev/null; then
            echo "  [!] Warning: Failed to create backup of $pfile ($pfile.bak)" >&2
        else
            echo "  [i] Backed up existing policy to $pfile.bak"
        fi

        if ! command -v python3 &>/dev/null; then
            echo "  [✗] ERROR: python3 is required to safely merge existing $pfile." >&2
            echo "      Preserving existing configuration; skipping policy update for $bname." >&2
            rm -f "$tmp_pol"
            POLICIES_FAILED+=("$bname ($pfile: python3 unavailable)")
            return 1
        fi

        local py_err
        py_err="$(mktemp "${TMPDIR:-/tmp}/burp-pol-err-XXXXXX.tmp")"
        if python3 -c '
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception as e:
    sys.stderr.write("Invalid JSON in %s: %s\n" % (src, e))
    sys.exit(1)

if not isinstance(d, dict):
    sys.stderr.write("Top-level JSON in %s is not an object (got %s)\n" % (src, type(d).__name__))
    sys.exit(1)

if "policies" in d and not isinstance(d["policies"], dict):
    sys.stderr.write("\"policies\" property in %s is not an object (got %s)\n" % (src, type(d["policies"]).__name__))
    sys.exit(1)

if "policies" not in d:
    d["policies"] = {}

d["policies"]["ImportEnterpriseRoots"] = True

with open(dst, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
' "$pfile" "$tmp_pol" 2>"$py_err"; then
            rm -f "$py_err"
        else
            echo "  [✗] ERROR: Existing policy file $pfile contains invalid or corrupt JSON structure." >&2
            if [ -s "$py_err" ]; then
                echo "      $(cat "$py_err")" >&2
            fi
            echo "      Preserving original file without modification; skipping policy update for $bname." >&2
            rm -f "$py_err" "$tmp_pol"
            POLICIES_FAILED+=("$bname ($pfile: invalid/corrupt JSON structure)")
            return 1
        fi
    else
        printf '{\n  "policies": {\n    "ImportEnterpriseRoots": true\n  }\n}\n' >"$tmp_pol"
    fi

    if sudo cp "$tmp_pol" "$pfile" 2>/dev/null && sudo chmod 644 "$pfile" 2>/dev/null; then
        echo "  [✓] Updated $bname Enterprise Roots policy ($pfile)."
        POLICIES_SUCCEEDED+=("$bname ($pfile)")
        rm -f "$tmp_pol"
        return 0
    else
        echo "  [✗] Error: Failed to write policy file $pfile with sudo." >&2
        POLICIES_FAILED+=("$bname ($pfile: write failed)")
        rm -f "$tmp_pol"
        return 1
    fi
}

candidate_browsers=(
    "Firefox:/etc/firefox/policies:firefox"
    "LibreWolf:/etc/librewolf/policies:librewolf"
    "Floorp:/etc/floorp/policies:floorp"
    "Waterfox:/etc/waterfox/policies:waterfox"
    "Zen Browser:/etc/zen/policies:zen"
)

for entry in "${candidate_browsers[@]}"; do
    IFS=: read -r bname pdir b_id <<<"$entry"
    if ! is_browser_installed "$b_id"; then
        echo "  [-] Skipped $bname Enterprise Roots policy (browser not installed)."
        POLICIES_SKIPPED+=("$bname (browser not installed)")
        continue
    fi
    update_enterprise_roots "$bname" "$pdir"
done

# 6. Trust Configuration Summary & Exit Status
echo ""
echo "=================================================="
echo "          Trust Configuration Summary             "
echo "=================================================="

echo "1. System CA Trust Store:"
case "$SYS_TRUST_STATUS" in
    SUCCESS*)
        echo "   [✓] $SYS_TRUST_STATUS"
        ;;
    SKIPPED*)
        echo "   [-] $SYS_TRUST_STATUS"
        ;;
    FAILED*|*)
        echo "   [✗] $SYS_TRUST_STATUS"
        ;;
esac
echo "   Note: Chromium-based browsers (Chrome, Chromium, Brave, Edge, Vivaldi, Thorium)"
if [[ "$SYS_TRUST_STATUS" == SUCCESS* ]]; then
    echo "   will automatically trust Burp CA via the updated system trust store."
else
    echo "   will NOT trust Burp CA until the system trust store is updated with sudo privileges."
fi

echo ""
echo "2. Browser Profiles (certutil / cert9.db):"
if [ ${#PROFILES_SUCCEEDED[@]} -gt 0 ]; then
    for item in "${PROFILES_SUCCEEDED[@]}"; do
        echo "   [✓] $item"
    done
fi
if [ ${#PROFILES_FAILED[@]} -gt 0 ]; then
    for item in "${PROFILES_FAILED[@]}"; do
        echo "   [✗] $item"
    done
fi
if [ ${#PROFILES_SKIPPED[@]} -gt 0 ]; then
    for item in "${PROFILES_SKIPPED[@]}"; do
        echo "   [-] $item"
    done
fi

echo ""
echo "3. Browser Enterprise Roots Policies (/etc/.../policies.json):"
if [ ${#POLICIES_SUCCEEDED[@]} -gt 0 ]; then
    for item in "${POLICIES_SUCCEEDED[@]}"; do
        echo "   [✓] $item"
    done
fi
if [ ${#POLICIES_FAILED[@]} -gt 0 ]; then
    for item in "${POLICIES_FAILED[@]}"; do
        echo "   [✗] $item"
    done
fi
if [ ${#POLICIES_SKIPPED[@]} -gt 0 ]; then
    for item in "${POLICIES_SKIPPED[@]}"; do
        echo "   [-] $item"
    done
fi

echo "=================================================="

TOTAL_SUCCESSES=0
TOTAL_FAILURES=0

case "$SYS_TRUST_STATUS" in
    SUCCESS*) TOTAL_SUCCESSES=$((TOTAL_SUCCESSES + 1)) ;;
    FAILED*) TOTAL_FAILURES=$((TOTAL_FAILURES + 1)) ;;
esac

TOTAL_SUCCESSES=$((TOTAL_SUCCESSES + ${#PROFILES_SUCCEEDED[@]} + ${#POLICIES_SUCCEEDED[@]}))
TOTAL_FAILURES=$((TOTAL_FAILURES + ${#PROFILES_FAILED[@]} + ${#POLICIES_FAILED[@]}))

if [ "$TOTAL_FAILURES" -gt 0 ]; then
    echo "[✗] ERROR: Burp Suite CA certificate configuration completed with $TOTAL_FAILURES failure(s)." >&2
    exit 1
elif [ "$TOTAL_SUCCESSES" -gt 0 ]; then
    echo "[✓] Burp Suite CA certificate configuration completed successfully!"
    exit 0
else
    echo "[!] Note: Burp Suite CA certificate configuration skipped across all targets (missing permissions or no targets detected)."
    exit 0
fi
