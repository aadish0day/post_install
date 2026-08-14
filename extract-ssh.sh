#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <archive.zip> [destination]"
  echo "  destination defaults to the home directory (~/)"
  echo "  extracts, fixes permissions, and restarts the ssh-agent with the key"
  exit 1
}

[ "$#" -ge 1 ] || usage

ARCHIVE="$1"
DEST="${2:-$HOME}"

[ -f "$ARCHIVE" ] || { echo "error: $ARCHIVE not found"; exit 1; }

mkdir -p "$DEST"
unzip -o "$ARCHIVE" -d "$DEST"

if [ -d "$DEST/.ssh" ]; then
  chmod 700 "$DEST/.ssh"
  chmod 600 "$DEST/.ssh/id_ed25519" 2>/dev/null || true
  chmod 644 "$DEST/.ssh/id_ed25519.pub" 2>/dev/null || true
  echo "extracted to $DEST/.ssh with correct permissions"
else
  echo "extracted to $DEST"
fi
