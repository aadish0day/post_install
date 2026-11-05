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

CERT_URL="http://127.0.0.1:8080/cert"
TRUST_ALL=false

# Helper for finding burp launcher
find_burp_bin() {
    if [ -n "${BURP_BIN:-}" ] && [ "$BURP_BIN" != "none" ] && [ -x "$BURP_BIN" ]; then
        echo "$BURP_BIN"
        return 0
    fi
    local b
    for b in "$HOME/.local/bin/burpsuitepro" "/usr/local/bin/burpsuitepro" "$HOME/Documents/Crack/Burpsuite-Professional/burpsuitepro"; do
        if [ -x "$b" ]; then
            echo "$b"
            return 0
        fi
    done
    return 1
}

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

if [ ! -t 0 ] && [ ! -c /dev/tty ]; then
    TRUST_ALL=true
fi

echo "=================================================="
echo "    Burp Suite CA Certificate Trust Utility      "
echo "=================================================="

# 1. Verify proxy listener is active
echo "Checking for running Burp Suite proxy at $CERT_URL..."
if ! curl -s -f -m 3 "$CERT_URL" -o /dev/null 2>/dev/null; then
    burp_bin="$(find_burp_bin 2>/dev/null || true)"
    if ! pgrep -f 'burpsuite_pro|burpsuite.*\.jar|net\.portswigger' >/dev/null 2>&1; then
        if [ -n "$burp_bin" ]; then
            echo "Burp Suite process not detected. Launching in background..."
            nohup "$burp_bin" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        else
            echo "ERROR: Burp Suite proxy is not running, and burpsuitepro launcher was not found." >&2
            echo "Please start Burp Suite with proxy listener on 127.0.0.1:8080 first." >&2
            exit 1
        fi
    else
        echo "Burp Suite process detected. Waiting for proxy listener..."
    fi

    echo "Waiting for Burp Suite proxy to become active at $CERT_URL (up to 90s)..."
    burp_ready=false
    for ((attempt = 1; attempt <= 18; attempt++)); do
        sleep 5
        if curl -s -f -m 3 "$CERT_URL" -o /dev/null 2>/dev/null; then
            burp_ready=true
            echo "  [✓] Burp Suite proxy is active and ready (attempt $attempt)."
            break
        fi
        echo "  Waiting for proxy... ($((attempt * 5))/90s)"
    done

    if [ "$burp_ready" = false ]; then
        echo "ERROR: Burp Suite proxy did not become active at $CERT_URL after 90 seconds." >&2
        echo "Please ensure Burp Suite is running with proxy listener enabled on 127.0.0.1:8080." >&2
        exit 1
    fi
else
    echo "[✓] Burp Suite proxy is active and ready."
fi

# 2. Download and convert certificate
tmp_der="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.der")"
tmp_crt="$(mktemp "${TMPDIR:-/tmp}/burp-ca-XXXXXX.crt")"
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
if ! openssl x509 -inform DER -in "$tmp_der" -out "$tmp_crt" 2>/dev/null; then
    echo "ERROR: Failed to convert Burp CA certificate." >&2
    exit 1
fi

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
        elif [ -c /dev/tty ] && (command -v dialog &>/dev/null || command -v whiptail &>/dev/null); then
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

        for sel_idx in "${unique_indices[@]}"; do
            b_name="${B_NAMES[sel_idx]}"
            echo "Installing Burp CA certificate into $b_name..."
            IFS=: read -r -a paths <<<"${B_PATHS[sel_idx]}"
            for p in "${paths[@]}"; do
                if [ -d "$p" ]; then
                    if certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "sql:$p" 2>/dev/null; then
                        echo "  [✓] Imported into profile: $p"
                    elif certutil -A -n "PortSwigger CA" -t "TCu,Cu,Tu" -i "$tmp_crt" -d "dbm:$p" 2>/dev/null; then
                        echo "  [✓] Imported into profile (dbm): $p"
                    else
                        echo "  [!] Warning: Failed to import into profile: $p (browser may be locking cert9.db)" >&2
                    fi
                fi
            done
        done
    else
        echo "No supported browser profiles detected."
    fi
else
    echo "Note: certutil (nss / libnss3-tools) is not installed. Skipping direct profile injection."
fi

# 4. Install to OS System Trust Store
echo "Installing CA certificate to system trust store (requires sudo)..."
if [ -d /etc/ca-certificates/trust-source/anchors ] || command -v trust &>/dev/null; then
    # Arch Linux
    sys_anchor_dir="/etc/ca-certificates/trust-source/anchors"
    sys_cert="$sys_anchor_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_anchor_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo trust extract-compat; then
        echo "[✓] System trust store updated via trust extract-compat ($sys_cert)."
    else
        echo "[!] Warning: Failed to update Arch system trust store." >&2
    fi
elif [ -d /etc/pki/ca-trust/source/anchors ] || command -v update-ca-trust &>/dev/null; then
    # Fedora / RHEL
    sys_cert_dir="/etc/pki/ca-trust/source/anchors"
    sys_cert="$sys_cert_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo update-ca-trust; then
        echo "[✓] System trust store updated via update-ca-trust ($sys_cert)."
    else
        echo "[!] Warning: Failed to update Fedora system trust store." >&2
    fi
else
    # Debian / Ubuntu / Kali
    sys_cert_dir="/usr/local/share/ca-certificates"
    sys_cert="$sys_cert_dir/burpsuite-ca.crt"
    sudo mkdir -p "$sys_cert_dir" 2>/dev/null || true
    if sudo cp "$tmp_crt" "$sys_cert" && sudo chmod 644 "$sys_cert" && sudo update-ca-certificates; then
        echo "[✓] System trust store updated via update-ca-certificates ($sys_cert)."
    else
        echo "[!] Warning: Failed to update Debian/Kali system trust store." >&2
    fi
fi

# 5. Enterprise Roots policy for Mozilla family
echo "Configuring browser Enterprise Roots policy..."
update_enterprise_roots() {
    local pdir="$1"
    local pfile="$pdir/policies.json"
    sudo mkdir -p "$pdir" 2>/dev/null || true
    if [ -d "$pdir" ]; then
        local tmp_pol
        tmp_pol="$(mktemp "${TMPDIR:-/tmp}/burp-pol-XXXXXX.json")"
        if [ -f "$pfile" ]; then
            python3 -c "
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src, 'r', encoding='utf-8') as f:
        d = json.load(f)
except Exception:
    d = {}
if not isinstance(d, dict): d = {}
p = d.setdefault('policies', {})
if isinstance(p, dict): p['ImportEnterpriseRoots'] = True
with open(dst, 'w', encoding='utf-8') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "$pfile" "$tmp_pol" 2>/dev/null || printf '{\n  "policies": {\n    "ImportEnterpriseRoots": true\n  }\n}\n' >"$tmp_pol"
        else
            printf '{\n  "policies": {\n    "ImportEnterpriseRoots": true\n  }\n}\n' >"$tmp_pol"
        fi
        sudo cp "$tmp_pol" "$pfile" 2>/dev/null || true
        sudo chmod 644 "$pfile" 2>/dev/null || true
        rm -f "$tmp_pol"
    fi
}

for pdir in /etc/firefox/policies /etc/librewolf/policies /etc/floorp/policies /etc/waterfox/policies /etc/zen/policies; do
    update_enterprise_roots "$pdir"
done

echo ""
echo "[✓] Burp Suite CA certificate configuration complete!"
