#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# AMD Hardware Setup Script (Arch Linux)
# Tailored specifically for AMD Ryzen 7 6800HS + Radeon 680M (Rembrandt / RDNA 2)
# Laptop: ASUS ROG Zephyrus G14 (GA402RJ / GA402 Series)
#
# Configures:
#   - AMD microcode (amd-ucode) and linux-firmware
#   - AMD P-State EPP driver & Preferred Core (amd_pstate=active, amd_prefcore=enable)
#   - Mesa + RADV Vulkan stack with 32-bit multilib support
#   - Hardware video acceleration (VA-API & VDPAU)
#   - ROCm OpenCL runtime with Radeon 680M GFX1035 override (HSA_OVERRIDE_GFX_VERSION=10.3.0)
#   - Dynamic GTT VRAM memory cap (ttm.pages_limit) for 16GB RAM
#   - Video & render group permissions for GPU compute
#
# Usage: amd.sh
# ============================================================================

# ------------------------- Detection ----------------------------------------
detect_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | sed -E 's/.*: //'
}

gpu_description() {
    lspci 2>/dev/null | grep -Ei "vga|3d controller" | sed -E 's/^[0-9a-f:.]+\s+//' | sort -u
}

has_amd_cpu() {
    grep -q "AuthenticAMD" /proc/cpuinfo
}

has_amd_gpu() {
    lspci 2>/dev/null | grep -qiE "\[amd/ati\]|radeon|rembrandt|navi"
}

# Rembrandt / Radeon 680M (and 660M) = PCI 1002:1681 = gfx1035
is_gfx1035() {
    lspci -nn 2>/dev/null | grep -qi '1002:1681'
}

# shellcheck source=lib/arch-multilib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/arch-multilib.sh"

# ------------------------- Args ---------------------------------------------
# --pro is passed by the installer but AMD Pro packages are not implemented yet.
for _arg in "$@"; do
    case "$_arg" in
    --pro) echo "WARN: --pro (AMD Pro AUR packages) is not implemented; ignoring." >&2 ;;
    esac
done

# ------------------------- Root Check ---------------------------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script needs root privileges. Re-running with sudo..."
        exec sudo bash "$(readlink -f "$0")" "$@"
    fi
}

# ------------------------- CPU Configuration --------------------------------
install_cpu() {
    echo "Installing AMD microcode and linux-firmware..."
    pacman -S --noconfirm --needed linux-firmware amd-ucode
}

# ------------------------- GPU / Mesa / Vulkan ------------------------------
install_gpu() {
    ensure_multilib

    echo "Installing Mesa, RADV Vulkan, and Hardware Video Acceleration..."
    pacman -S --noconfirm --needed \
        linux-firmware \
        mesa lib32-mesa \
        vulkan-radeon lib32-vulkan-radeon \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        vulkan-mesa-layers lib32-vulkan-mesa-layers \
        libva-utils \
        mesa-utils lib32-mesa-utils \
        radeontop
}

# ------------------------- ROCm & OpenCL (Radeon 680M) ---------------------
configure_rocm_opencl() {
    echo "Configuring ROCm OpenCL compute stack for Radeon 680M (Rembrandt GFX1035)..."

    # Install official Arch ROCm OpenCL runtime and diagnostic tools
    pacman -S --noconfirm --needed \
        rocm-opencl-runtime \
        clinfo \
        opencl-headers

    local override_val="10.3.0"
    local env_file="/etc/environment"
    local profile_file="/etc/profile.d/rocm-gfx.sh"

    if is_gfx1035; then
        # Rembrandt (Radeon 680M) is GFX1035; ROCm needs HSA_OVERRIDE_GFX_VERSION=10.3.0.
        # NOTE: systemd services (e.g. ollama.service) do not read these files; see ai-agents.sh.
        echo "gfx1035 detected: setting HSA_OVERRIDE_GFX_VERSION=$override_val in $env_file..."
        if [ -f "$env_file" ]; then
            if grep -q "^HSA_OVERRIDE_GFX_VERSION=" "$env_file"; then
                sed -i "s/^HSA_OVERRIDE_GFX_VERSION=.*/HSA_OVERRIDE_GFX_VERSION=$override_val/" "$env_file"
            else
                echo "HSA_OVERRIDE_GFX_VERSION=$override_val" >>"$env_file"
            fi
        else
            echo "HSA_OVERRIDE_GFX_VERSION=$override_val" >"$env_file"
        fi
        cat <<EOF >"$profile_file"
# Exported by post_install for AMD Radeon 680M (Rembrandt GFX1035) ROCm OpenCL
export HSA_OVERRIDE_GFX_VERSION=$override_val
EOF
        chmod 644 "$profile_file"
    else
        echo "GPU is not gfx1035 (Radeon 680M/660M): not setting HSA_OVERRIDE_GFX_VERSION."
        # Remove an override left by an earlier run of this script; a wrong ISA override breaks ROCm.
        if [ -f "$profile_file" ] && grep -q "post_install" "$profile_file"; then
            rm -f "$profile_file"
            sed -i '/^HSA_OVERRIDE_GFX_VERSION=/d' "$env_file" 2>/dev/null || true
            echo "Removed stale HSA override from earlier run."
        fi
    fi

    # Add invoking user to video and render groups for GPU acceleration access
    local target_user="${SUDO_USER:-$USER}"
    if [ -n "$target_user" ] && [ "$target_user" != "root" ]; then
        echo "Adding user '$target_user' to 'video' and 'render' groups..."
        usermod -aG video,render "$target_user" 2>/dev/null || true
    fi
}

# ------------------------- Kernel cmdline tuning ----------------------------
CMDLINE_STATUS="NOT applied (unknown bootloader)"

# merge_cmdline "<existing cmdline>" param...  -> prints cmdline with each param's key replaced
merge_cmdline() {
    local cmdline="$1"
    shift
    local -a toks=() out=()
    local tok p skip
    read -ra toks <<<"$cmdline"
    for tok in "${toks[@]}"; do
        skip=false
        for p in "$@"; do
            [ "${tok%%=*}" = "${p%%=*}" ] && skip=true
        done
        [ "$skip" = true ] || out+=("$tok")
    done
    out+=("$@")
    echo "${out[*]}"
}

sed_escape_repl() {
    local e="${1//\\/\\\\}"
    e="${e//&/\\&}"
    e="${e//|/\\|}"
    printf '%s' "$e"
}

build_params() {
    PARAMS=("amd_pstate=active" "amd_prefcore=enable")
    [ "${AMD_USB_AUTOSUSPEND_OFF:-0}" = 1 ] && PARAMS+=("usbcore.autosuspend=-1")

    # GTT cap: kernel default is 50% of RAM. Reserve max(4 GiB, 25% of RAM) for the system.
    local total_kib page_kib reserve_kib pages
    total_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    total_kib="${total_kib//[^0-9]/}"
    [ -z "$total_kib" ] && total_kib=0
    if [ "$total_kib" -gt 0 ]; then
        reserve_kib=$((4 * 1024 * 1024))
        [ $((total_kib / 4)) -gt "$reserve_kib" ] && reserve_kib=$((total_kib / 4))
        page_kib=$(($(getconf PAGESIZE 2>/dev/null || echo 4096) / 1024))
        [ "${page_kib:-0}" -le 0 ] && page_kib=4
        if [ "$total_kib" -gt "$reserve_kib" ]; then
            pages=$(((total_kib - reserve_kib) / page_kib))
            echo "GPU memory limit: ttm.pages_limit=$pages (~$((pages * page_kib / 1024 / 1024)) GiB of ~$((total_kib / 1024 / 1024)) GiB RAM)."
            PARAMS+=("ttm.pages_limit=$pages")
        fi
    fi
}

tune_kernel_cmdline() {
    local -a PARAMS=()
    build_params

    if [ -f /etc/default/grub ]; then
        local file=/etc/default/grub cmdline new
        cmdline="$(sed -nE "s/^GRUB_CMDLINE_LINUX_DEFAULT=[\"'](.*)[\"']\s*\$/\1/p" "$file" | head -n1)"
        new="$(merge_cmdline "$cmdline" "${PARAMS[@]}")"
        echo "Updating GRUB_CMDLINE_LINUX_DEFAULT in $file..."
        if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file"; then
            sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$(sed_escape_repl "$new")\"|" "$file"
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$new\"" >>"$file"
        fi
        refresh_bootloader
        CMDLINE_STATUS="applied (GRUB)"
    elif [ -f /etc/kernel/cmdline ]; then
        local cur new
        cur="$(cat /etc/kernel/cmdline)"
        new="$(merge_cmdline "$cur" "${PARAMS[@]}")"
        echo "$new" >/etc/kernel/cmdline
        CMDLINE_STATUS="applied to /etc/kernel/cmdline (rebuild UKI: mkinitcpio -P)"
    elif compgen -G "/boot/loader/entries/*.conf" >/dev/null; then
        local f cur new n=0
        for f in /boot/loader/entries/*.conf; do
            grep -q '^options[[:space:]]' "$f" || continue
            cur="$(sed -nE 's/^options[[:space:]]+(.*)$/\1/p' "$f" | head -n1)"
            new="$(merge_cmdline "$cur" "${PARAMS[@]}")"
            sed -i -E "s|^options[[:space:]].*|options $(sed_escape_repl "$new")|" "$f"
            n=$((n + 1))
        done
        CMDLINE_STATUS="applied to $n systemd-boot entries"
    else
        echo "WARN: no supported bootloader config found. Add manually: ${PARAMS[*]}" >&2
        CMDLINE_STATUS="NOT applied; add manually: ${PARAMS[*]}"
    fi
}

# ------------------------- Summary ------------------------------------------
print_summary() {
    echo "============================================================"
    echo " AMD Ryzen 7 6800HS + Radeon 680M Summary"
    echo "============================================================"
    echo "  CPU:          $(detect_cpu_model)"
    echo "  GPU(s):"
    gpu_description | sed 's/^/                /'
    if is_gfx1035; then
        echo "  ROCm GFX:     HSA_OVERRIDE_GFX_VERSION=10.3.0 (Rembrandt GFX1035)"
    else
        echo "  ROCm GFX:     native (no override)"
    fi
    echo "  Kernel args:  $CMDLINE_STATUS"
    echo "  Vulkan:       vulkan-radeon (RADV) + 32-bit lib32-vulkan-radeon"
    echo "  VA-API:       provided by mesa (libva-utils for vainfo)"
    echo "  Kernel:       $(uname -r)"
    echo "============================================================"
}

# ------------------------- Main ---------------------------------------------
require_root "$@"

if ! has_amd_cpu || ! has_amd_gpu; then
    echo "SKIP: AMD CPU + AMD GPU not both detected; nothing to do (script targets Ryzen + Radeon)." >&2
    exit 0
fi

install_cpu
install_gpu
configure_rocm_opencl
tune_kernel_cmdline
print_summary

echo "AMD hardware setup completed successfully."
