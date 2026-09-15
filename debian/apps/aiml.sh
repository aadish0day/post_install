#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# AI / ML ACCELERATION (AMD ROCm)
# ROCm runtime from Debian repos, PyTorch ROCm wheels in ~/.venvs/rocm.
# ============================================================================

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

ROCM_INDEX="${ROCM_INDEX:-https://download.pytorch.org/whl/rocm6.4}"
VENV="$HOME/.venvs/rocm"

log "Installing ROCm runtime packages..."
apt_install rocminfo rocm-smi hipcc libamdhip64-dev rocm-opencl-icd clinfo ocl-icd-libopencl1 \
    opencl-headers python3-venv python3-pip

add_user_group render
add_user_group video

if is_simulate; then
    url_ok "$ROCM_INDEX/torch/" >/dev/null || die "PyTorch ROCm index not reachable: $ROCM_INDEX"
    log "[simulate] would create $VENV with torch/torchvision/torchaudio from $ROCM_INDEX"
    exit 0
fi

if [ ! -x "$VENV/bin/python" ]; then
    log "Creating Python virtual environment at $VENV..."
    python3 -m venv "$VENV"
fi

log "Installing PyTorch (ROCm) into $VENV (several GB)..."
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install torch torchvision torchaudio --index-url "$ROCM_INDEX"

log "AI/ML setup complete. Activate with: source $VENV/bin/activate"
log "Check the GPU with: python -c 'import torch; print(torch.cuda.is_available())'"
