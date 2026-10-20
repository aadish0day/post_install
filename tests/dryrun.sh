#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STUB_DIR="$(mktemp -d -t post_install_dryrun_stubs.XXXXXX)"
trap 'rm -rf "$STUB_DIR"' EXIT

FORBIDDEN_CMDS=(sudo pacman apt apt-get nala dnf git curl wget rm systemctl)
for cmd in "${FORBIDDEN_CMDS[@]}"; do
    cat <<STUB > "$STUB_DIR/$cmd"
#!/usr/bin/env bash
echo "FORBIDDEN: $cmd called with: \$*" >&2
exit 99
STUB
    chmod +x "$STUB_DIR/$cmd"
done

DISTROS=(arch debian fedora kali termux)
FAILED=0

for d in "${DISTROS[@]}"; do
    echo "[TEST] Running dry-run for distro: $d"
    OUTPUT_FILE="$(mktemp)"
    if ! PATH="$STUB_DIR:$PATH" ./install.sh --dry-run --distro "$d" > "$OUTPUT_FILE" 2>&1; then
        echo "[FAIL] Distro $d failed with non-zero exit code"
        cat "$OUTPUT_FILE"
        FAILED=1
    elif grep -q "FORBIDDEN:" "$OUTPUT_FILE"; then
        echo "[FAIL] Distro $d executed forbidden command!"
        grep "FORBIDDEN:" "$OUTPUT_FILE"
        FAILED=1
    else
        echo "[PASS] Distro $d dry-run completed cleanly without forbidden calls."
    fi
    rm -f "$OUTPUT_FILE"
done

if [ "$FAILED" -ne 0 ]; then
    echo "Dry-run safety test FAILED."
    exit 1
fi

echo "All dry-run tests PASSED."
exit 0
