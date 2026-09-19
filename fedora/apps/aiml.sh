#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA AI / ML (AMD ROCm)
# ROCm runtime, development tools, compilers, and OpenCL from Fedora repos.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

rocm_packages=(
    rocminfo rocm-smi rocm-hip rocm-hip-devel rocm-opencl rocm-runtime rocm-clinfo
    rocm-rpm-macros hipcc rocblas miopen ocl-icd ocl-icd-devel opencl-headers clang python3-devel
)

log "Installing ROCm packages..."
dnf_install --allowerasing "${rocm_packages[@]}"

add_user_group render video

log "AMD ROCm runtime and GPU acceleration stack installed successfully."
