#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA DNF / DNF5 TUNING
# Merges the options from fedora/config/dnf.conf into the system config
# without wiping existing settings (a .bak copy is kept once).
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

CONFIG_SOURCE="$FEDORA_DIR/config/dnf.conf"

mapfile -t options < <(grep -E '^[a-z_]+=' "$CONFIG_SOURCE")

for target in /etc/dnf/dnf.conf /etc/dnf/dnf5.conf; do
    [ -f "$target" ] || continue
    log "Tuning $target..."
    [ -f "$target.bak" ] || $SUDO cp "$target" "$target.bak"

    if ! grep -q '^\[main\]' "$target"; then
        echo "[main]" | $SUDO tee -a "$target" >/dev/null
    fi

    for opt in "${options[@]}"; do
        key="${opt%%=*}"
        if grep -q "^${key}=" "$target"; then
            $SUDO sed -i "s|^${key}=.*|${opt}|" "$target"
        else
            # Insert right after [main] so the option lands in the right section
            $SUDO sed -i "/^\[main\]/a ${opt}" "$target"
        fi
    done
done

log "DNF configuration tuned."
