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

rocm_packages=(
    rocminfo rocm-smi rocm-hip rocm-hip-devel rocm-opencl rocm-runtime rocm-clinfo
    rocm-rpm-macros hipcc rocblas miopen ocl-icd opencl-headers clang python3-devel
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
    "$VENV/bin/pip" install torch torchvision torchaudio --index-url "$ROCM_INDEX"
    "$VENV/bin/python" -c 'import torch; print("PyTorch", torch.__version__, "ROCm/GPU available:", torch.cuda.is_available())' || true
fi

log "AI/ML stack ready. Activate PyTorch with: source $VENV/bin/activate"
