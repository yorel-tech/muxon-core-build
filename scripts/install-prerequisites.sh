#!/usr/bin/env bash
# Install host prerequisites for the Muxon / muxon-build system.
# Mirrors muxon-core/dev-docs/build/README.md (Prerequisites) and quick-start.md (First-Time Setup + appliance tools).
#
# Usage:
#   ./scripts/install-prerequisites.sh              # full install (Docker, Helm, Node 20 via nvm, QEMU/KVM, Packer, skopeo)
#   ./scripts/install-prerequisites.sh --minimal    # Docker, docker compose plugin, Helm, Node 20 via nvm only
#   ./scripts/install-prerequisites.sh --help
#
# Run from the muxon-build directory, or any path (script locates repo root).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUXON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PACKER_VERSION="${PACKER_VERSION:-1.11.0}"
NVM_VERSION="${NVM_VERSION:-v0.39.7}"
NODE_VERSION="${NODE_VERSION:-20}"

MINIMAL=false
SKIP_DOCKER=false
SKIP_NVM=false

usage() {
  sed -n '1,15p' "$0" | tail -n +2
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --minimal) MINIMAL=true ;;
    --skip-docker) SKIP_DOCKER=true ;;
    --skip-nvm) SKIP_NVM=true ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

TARGET_USER="${SUDO_USER:-$USER}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  TARGET_USER="$(id -un)"
fi

log() { echo "[install-prerequisites] $*"; }
die() { echo "[install-prerequisites] ERROR: $*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run with sudo (apt, Docker installer, /usr/local/bin). Example: sudo ./scripts/install-prerequisites.sh"
fi

if ! command -v apt-get >/dev/null 2>&1; then
  die "This installer expects apt-get (Debian/Ubuntu). See README for manual steps on other distributions."
fi

export DEBIAN_FRONTEND=noninteractive

log "muxon-core-build root: $MUXON_ROOT"
log "Configuring user: $TARGET_USER (docker/kvm groups)"

apt_update() {
  apt-get update -qq
}

install_apt_base() {
  apt_update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    unzip \
    gnupg \
    lsb-release
}

install_qemu_skopeo() {
  log "Installing QEMU/KVM, cloud-image-utils, and skopeo (build README + quick-start)..."
  apt-get install -y --no-install-recommends \
    qemu-kvm \
    qemu-system-x86 \
    qemu-utils \
    cloud-image-utils \
    skopeo
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
    return 0
  fi
  log "Installing Docker (quick-start: get.docker.com)..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "docker compose: $(docker compose version)"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    log "docker-compose: $(docker-compose --version)"
    return 0
  fi
  log "Installing docker-compose-plugin (verify-setup expects compose)..."
  apt-get install -y --no-install-recommends docker-compose-plugin
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log "Helm already installed: $(helm version --short 2>/dev/null || helm version)"
    return 0
  fi
  log "Installing Helm 3 (build README / quick-start)..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_packer() {
  if command -v packer >/dev/null 2>&1; then
    log "Packer already installed: $(packer version)"
  else
    local url="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"
    local zip="/tmp/packer_${PACKER_VERSION}_linux_amd64.zip"
    log "Downloading Packer ${PACKER_VERSION}..."
    wget -q -O "$zip" "$url"
    unzip -o -q "$zip" -d /usr/local/bin
    rm -f "$zip"
    chmod +x /usr/local/bin/packer
    log "Installed packer to /usr/local/bin/packer"
  fi

  log "Installing Packer QEMU plugin (README)..."
  # Plugins install under invoking user's home; use target user for consistency.
  if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
    local home
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [[ -n "$home" ]]; then
      sudo -u "$TARGET_USER" -H env HOME="$home" packer plugins install github.com/hashicorp/qemu || true
    fi
  else
    packer plugins install github.com/hashicorp/qemu || true
  fi
}

install_nvm_node() {
  local home
  home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$home" ]] || die "Cannot resolve home for $TARGET_USER"

  export NVM_DIR="${home}/.nvm"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    log "Installing nvm ${NVM_VERSION} for $TARGET_USER (README)..."
    sudo -u "$TARGET_USER" bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
  else
    log "nvm already present for $TARGET_USER"
  fi

  log "Installing Node.js ${NODE_VERSION} via nvm..."
  sudo -u "$TARGET_USER" bash -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    # shellcheck disable=SC1090
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    nvm install ${NODE_VERSION}
    nvm alias default ${NODE_VERSION}
  "
}

append_buildkit_hint() {
  local home profile
  home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$home" ]] || return 0
  profile="${home}/.profile"
  local line='export DOCKER_BUILDKIT=1'
  if [[ -f "$profile" ]] && grep -qF 'DOCKER_BUILDKIT=1' "$profile" 2>/dev/null; then
    return 0
  fi
  log "Appending DOCKER_BUILDKIT=1 to ${profile} (README)"
  sudo -u "$TARGET_USER" bash -c "echo '' >> \"${profile}\"; echo '# muxon-build (README): BuildKit' >> \"${profile}\"; echo '${line}' >> \"${profile}\""
}

add_user_groups() {
  usermod -aG docker "$TARGET_USER" 2>/dev/null || true
  usermod -aG kvm "$TARGET_USER" 2>/dev/null || true
  log "Added $TARGET_USER to groups: docker, kvm (log out and back in for group changes to apply)"
}

# --- main ---

install_apt_base

if [[ "$SKIP_DOCKER" != true ]]; then
  install_docker
  ensure_docker_compose
else
  log "Skipping Docker (--skip-docker)"
fi

install_helm

if [[ "$MINIMAL" != true ]]; then
  install_qemu_skopeo
  install_packer
else
  log "Skipping QEMU/KVM, skopeo, and Packer (--minimal)"
fi

if [[ "$SKIP_NVM" != true ]]; then
  install_nvm_node
else
  log "Skipping nvm / Node (--skip-nvm)"
fi

add_user_groups
append_buildkit_hint

log "Done."
log "Next: log out and back in (or newgrp docker; newgrp kvm), then from muxon-core-build run: ./verify-setup.sh"
log "Optional: chmod +x ../muxon-core/gradlew ../muxon-enterprise/gradlew if verify-setup reports non-executable gradlew."
