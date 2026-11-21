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

# shellcheck source=lib/arch-multilib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/arch-multilib.sh"

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
        libva-mesa-driver lib32-libva-mesa-driver \
        mesa-vdpau lib32-mesa-vdpau \
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

    # Rembrandt (Radeon 680M) is GFX1035. ROCm requires HSA_OVERRIDE_GFX_VERSION=10.3.0
    # to enable OpenCL compute for DaVinci Resolve, Ollama ROCm, and Blender.
    local override_val="10.3.0"
    local env_file="/etc/environment"
    local profile_file="/etc/profile.d/rocm-gfx.sh"

    echo "Setting HSA_OVERRIDE_GFX_VERSION=$override_val in $env_file..."
    if [ -f "$env_file" ]; then
        if grep -q "^HSA_OVERRIDE_GFX_VERSION=" "$env_file"; then
            sed -i "s/^HSA_OVERRIDE_GFX_VERSION=.*/HSA_OVERRIDE_GFX_VERSION=$override_val/" "$env_file"
        else
            echo "HSA_OVERRIDE_GFX_VERSION=$override_val" >> "$env_file"
        fi
    else
        echo "HSA_OVERRIDE_GFX_VERSION=$override_val" > "$env_file"
    fi

    # Also export in /etc/profile.d for shell logins
    cat <<EOF > "$profile_file"
# Exported by post_install for AMD Radeon 680M (Rembrandt GFX1035) ROCm OpenCL
export HSA_OVERRIDE_GFX_VERSION=$override_val
EOF
    chmod +x "$profile_file"

    # Add invoking user to video and render groups for GPU acceleration access
    local target_user="${SUDO_USER:-$USER}"
    if [ -n "$target_user" ] && [ "$target_user" != "root" ]; then
        echo "Adding user '$target_user' to 'video' and 'render' groups..."
        usermod -aG video,render "$target_user" 2>/dev/null || true
    fi
}

# ------------------------- GTT Memory & GRUB Tuning -------------------------
tune_grub() {
    local file="/etc/default/grub"
    if [ ! -f "$file" ]; then
        echo "GRUB config (/etc/default/grub) not found - skipping GRUB tuning."
        return 0
    fi

    # 1. Base AMD CPU kernel parameters
    local params=("amd_pstate=active" "amd_prefcore=enable")
    [ "${AMD_USB_AUTOSUSPEND_OFF:-0}" = 1 ] && params+=("usbcore.autosuspend=-1")

    # 2. Dynamic GTT VRAM Cap Calculation for 16GB RAM:
    # Kernel default limits GPU buffer mapping (GTT) to 50% of RAM (~7.4 GiB).
    # On this machine (MemTotal: ~15.56 GiB), reserving 4 GiB for the system
    # allows ~11.5 GiB for GPU buffers (crucial for DaVinci Resolve, Ollama ROCm, and gaming).
    local total_kib page_kib pages reserve_kib
    total_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    total_kib="${total_kib//[^0-9]/}"
    [ -z "$total_kib" ] && total_kib=0

    if [ "$total_kib" -gt 0 ]; then
        # Reserve 4 GiB (4 * 1024 * 1024 KiB) for the system
        reserve_kib=$(( 4 * 1024 * 1024 ))
        page_kib=$(( $(getconf PAGESIZE 2>/dev/null || echo 4096) / 1024 ))
        [ "${page_kib:-0}" -le 0 ] && page_kib=4

        if [ "$total_kib" -gt "$reserve_kib" ]; then
            pages=$(( (total_kib - reserve_kib) / page_kib ))
            local alloc_gib=$(( (pages * page_kib) / 1024 / 1024 ))
            local total_gib=$(( total_kib / 1024 / 1024 ))
            echo "Configuring AMD GPU memory limit: ttm.pages_limit=$pages (~${alloc_gib} GiB allocatable, 4 GiB reserved for system out of ~${total_gib} GiB RAM)..."
            params+=("ttm.pages_limit=$pages")
        fi
    fi

    # 3. Update GRUB_CMDLINE_LINUX_DEFAULT
    local cmdline param
    cmdline="$(sed -nE "s/^GRUB_CMDLINE_LINUX_DEFAULT=[\"'](.*)[\"']\s*\$/\1/p" "$file" | head -n1)"

    # Strip existing ttm.pages_limit if present to prevent stale duplicates
    cmdline="$(echo "$cmdline" | sed -E 's/(^|[[:space:]])ttm\.pages_limit=[^[:space:]]*/ /g' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^ //; s/ $//')"

    for param in "${params[@]}"; do
        [[ " $cmdline " == *" $param "* ]] || cmdline="${cmdline:+$cmdline }$param"
    done

    # Escape sed replacement characters
    local esc="${cmdline//\\/\\\\}"
    esc="${esc//&/\\&}"
    esc="${esc//|/\\|}"

    echo "Updating GRUB_CMDLINE_LINUX_DEFAULT in $file..."
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$file"; then
        sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$esc\"|" "$file"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"" >> "$file"
    fi

    refresh_bootloader
}

# ------------------------- Summary ------------------------------------------
print_summary() {
    echo "============================================================"
    echo " AMD Ryzen 7 6800HS + Radeon 680M Summary"
    echo "============================================================"
    echo "  CPU:          $(detect_cpu_model)"
    echo "  GPU(s):"
    gpu_description | sed 's/^/                /'
    echo "  ROCm GFX:     HSA_OVERRIDE_GFX_VERSION=10.3.0 (Rembrandt GFX1035)"
    echo "  Vulkan:       vulkan-radeon (RADV) + 32-bit lib32-vulkan-radeon"
    echo "  VA-API:       libva-mesa-driver + 32-bit lib32-libva-mesa-driver"
    echo "  Kernel:       $(uname -r)"
    echo "============================================================"
}

# ------------------------- Main ---------------------------------------------
require_root "$@"

if ! has_amd_cpu || ! has_amd_gpu; then
    echo "ERROR: AMD CPU and AMD GPU were not detected on this system." >&2
    echo "This script is tailored specifically for AMD Ryzen + Radeon hardware." >&2
    exit 1
fi

install_cpu
install_gpu
configure_rocm_opencl
tune_grub
print_summary

echo "AMD hardware setup completed successfully."
