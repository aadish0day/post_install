#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA AI / ML (AMD ROCm)
# ROCm runtime + tools from the Fedora repos, PyTorch ROCm wheels from
# download.pytorch.org into a venv at ~/.venvs/rocm.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

ROCM_INDEX="${ROCM_INDEX:-https://download.pytorch.org/whl/rocm6.4}"
VENV="$HOME/.venvs/rocm"
# Optional local wheel cache (torch*-any-rocm*.whl) to avoid re-downloading
# the large torch wheel from a flaky CDN. Populate via:
#   pip download torch torchvision torchaudio --index-url "$ROCM_INDEX" -d ~/rocm-wheels
WHEEL_DIR="${WHEEL_DIR:-$HOME/rocm-wheels}"

rocm_packages=(
    rocminfo rocm-smi rocm-hip rocm-hip-devel rocm-opencl rocm-runtime rocm-clinfo
    rocm-rpm-macros hipcc rocblas miopen OpenCL-ICD-Loader opencl-headers clang python3-devel
)

log "Installing ROCm packages..."
dnf_install "${rocm_packages[@]}"

add_user_group render video

if is_simulate; then
    url_check "$ROCM_INDEX/torch/"
    log "[simulate] would create $VENV and pip install torch torchvision torchaudio from $ROCM_INDEX"
else
    [ -d "$VENV" ] || python3 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip
    if [ -d "$WHEEL_DIR" ] && ls "$WHEEL_DIR"/torch-*.whl >/dev/null 2>&1; then
        log "Installing PyTorch from local wheels in $WHEEL_DIR"
        local_tmp="$HOME/.tmp/pip"
        mkdir -p "$local_tmp"
        TMPDIR="$local_tmp" "$VENV/bin/pip" install \
            --find-links "$WHEEL_DIR" --index-url https://pypi.org/simple \
            torch==2.9.1+rocm6.4 torchvision==0.24.1+rocm6.4 torchaudio==2.9.1+rocm6.4 \
            pytorch-triton-rocm==3.5.1
    else
        "$VENV/bin/pip" install torch torchvision torchaudio --index-url "$ROCM_INDEX"
    fi
    "$VENV/bin/python" -c 'import torch; print("PyTorch", torch.__version__, "ROCm/GPU available:", torch.cuda.is_available())' || true
fi

log "AI/ML stack ready. Activate PyTorch with: source $VENV/bin/activate"
