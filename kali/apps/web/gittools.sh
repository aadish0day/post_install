#!/usr/bin/env bash
set -euo pipefail

# GitTools: gitdumper / gitextractor / gitfinder (https://github.com/internetwache/GitTools)
# Pinned commit, user-owned launchers.

# shellcheck source=kali/apps/web/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
web_init
GITTOOLS_REF="${GITTOOLS_REF:-8fa09eb2412f76a017624b917643dad598964e7e}"
INSTALL_DIR="$TOOL_BASE/GitTools"

echo "=== Installing GitTools Suite on Kali Linux ==="
apt_install git bash curl python3
git_checkout_ref "https://github.com/internetwache/GitTools.git" "$INSTALL_DIR" "$GITTOOLS_REF"

for n in gitdumper gitextractor gitfinder; do remove_legacy_wrapper "$n"; done

install_user_wrapper gitdumper <<WRAP
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/Dumper/gitdumper.sh" "\$@"
WRAP
install_user_wrapper gitextractor <<WRAP
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/Extractor/extractor.sh" "\$@"
WRAP
install_user_wrapper gitfinder <<WRAP
#!/usr/bin/env bash
exec python3 "$INSTALL_DIR/Finder/gitfinder.py" "\$@"
WRAP
path_hint

log "GitTools installation complete!"
log "  gitdumper <URL> <dest-dir>       (download exposed .git folder)"
log "  gitextractor <git-dir> <out-dir> (extract source from .git)"
log "  gitfinder -i <targets.txt>       (find exposed .git repositories)"
