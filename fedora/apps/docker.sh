#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FEDORA DOCKER CE
# Official Docker CE repo (dnf5-compatible), Compose + Buildx plugins,
# service enablement and docker group membership.
# ============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

log "Installing Docker CE on Fedora..."

# Remove distro Docker/Podman shims that conflict with docker-ce
conflicts=(docker docker-client docker-client-latest docker-common docker-latest
    docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux
    docker-engine podman-docker moby-engine)
installed=()
for pkg in "${conflicts[@]}"; do
    rpm -q "$pkg" &>/dev/null && installed+=("$pkg")
done
if [ ${#installed[@]} -gt 0 ]; then
    log "Removing conflicting packages: ${installed[*]}"
    if is_simulate; then
        log "[simulate] would remove ${installed[*]}"
    else
        $SUDO dnf remove -y "${installed[@]}"
    fi
fi

add_repo_file https://download.docker.com/linux/fedora/docker-ce.repo docker-ce.repo

dnf_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
    docker-compose-plugin docker-ce-rootless-extras

enable_service docker.service --now
add_user_group docker

log "Docker installation complete. Log out and back in for group changes to take effect."
