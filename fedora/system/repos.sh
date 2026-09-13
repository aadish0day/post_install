#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA REPOSITORIES
# RPM Fusion (free + nonfree), dnf5 plugins, COPRs used by other scripts,
# and the RPM Fusion ffmpeg / multimedia codec swap.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

ensure_dnf_plugins
rpmfusion_enable

# COPRs used by base.sh (starship, yazi) and desktop/tiling.sh (i3lock-color)
for copr in atim/starship lihaohong/yazi tokariew/i3lock-color; do
    copr_enable "$copr"
done

# Multimedia codecs: full RPM Fusion ffmpeg instead of ffmpeg-free
swap_ffmpeg

log "Updating repository metadata..."
$SUDO dnf makecache -q

log "Repositories configured."
