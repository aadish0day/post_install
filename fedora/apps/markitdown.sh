#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA MARKITDOWN (Microsoft)
# Python CLI utility for converting various file formats (PDF, PowerPoint,
# Word, Excel, Images, Audio, HTML, CSV, JSON, XML, ZIP, YouTube) to Markdown
# for text analysis and LLM pipelines. Includes OCR plugin (markitdown-ocr)
# and OpenAI / Azure integrations.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

log "Ensuring system dependencies for MarkItDown..."
dnf_install python3 python3-pip ffmpeg
swap_ffmpeg

log "Installing MarkItDown with all format extras and OCR plugin via uv tool..."
uv_tool_install --with markitdown-ocr --with openai "markitdown[all]"

if command -v markitdown &>/dev/null; then
    log "MarkItDown installed: $(markitdown --version 2>/dev/null || echo 'ready')"
    if ! is_simulate; then
        log "Active plugins:"
        markitdown --list-plugins 2>/dev/null || true
    fi
else
    is_simulate || warn "markitdown binary not found in PATH (~/.local/bin)."
fi

log "MarkItDown setup complete."
log "Usage examples:"
log "  markitdown document.pdf > document.md"
log "  markitdown document.pdf -o document.md"
log "  markitdown --use-plugins document_with_images.pdf"
