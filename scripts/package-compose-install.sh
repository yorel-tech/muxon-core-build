#!/usr/bin/env bash
# Assemble the versioned Docker Compose install kit.
#
# Usage (from muxon-core-build, or anywhere):
#   VERSION=1.2.3 ./scripts/package-compose-install.sh
#
# Writes:
#   dist/compose-install/muxon-compose-install-<version>.tar.gz
#   dist/compose-install/muxon-compose-install-<version>.zip
#
# The archive contains pristine templates only. Runtime files
# (secrets/, initial-config.yaml, realm-muxon-dev.runtime.json) are not packed.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CORE_DIR="${MUXON_CORE_DIR:-$BUILD_ROOT/../muxon-core}"

if [[ -z "${VERSION:-}" && -f "$BUILD_ROOT/VERSION" ]]; then
  VERSION=$(tr -d '[:space:]' <"$BUILD_ROOT/VERSION")
fi
if [[ -z "${VERSION:-}" && -f "$CORE_DIR/VERSION" ]]; then
  VERSION=$(tr -d '[:space:]' <"$CORE_DIR/VERSION")
fi
if [[ -z "${VERSION:-}" ]]; then
  echo "ERROR: set VERSION (release image tag, without a leading v)" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[A-Za-z0-9._+-]+$ ]]; then
  echo "ERROR: VERSION contains unsupported characters: $VERSION" >&2
  exit 1
fi

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: missing kit source $1" >&2
    exit 1
  fi
}

require_file "$CORE_DIR/INSTALL.md"
require_file "$CORE_DIR/install.sh"
require_file "$CORE_DIR/compose/muxon.yml"
require_file "$CORE_DIR/compose/initial-config.yaml.template"
require_file "$CORE_DIR/compose/keycloak/realm-muxon-dev.json"
require_file "$CORE_DIR/scripts/create-secrets.sh"

KIT_NAME="muxon-compose-install-${VERSION}"
OUT_DIR="$BUILD_ROOT/dist/compose-install"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
KIT="$STAGE/$KIT_NAME"

mkdir -p "$KIT/compose/keycloak" "$KIT/scripts"
install -m 0644 "$CORE_DIR/INSTALL.md" "$KIT/INSTALL.md"
install -m 0755 "$CORE_DIR/install.sh" "$KIT/install.sh"
printf '%s\n' "$VERSION" >"$KIT/VERSION"
install -m 0644 "$CORE_DIR/compose/muxon.yml" "$KIT/compose/muxon.yml"
install -m 0644 "$CORE_DIR/compose/initial-config.yaml.template" "$KIT/compose/initial-config.yaml.template"
install -m 0644 "$CORE_DIR/compose/keycloak/realm-muxon-dev.json" "$KIT/compose/keycloak/realm-muxon-dev.json"
install -m 0755 "$CORE_DIR/scripts/create-secrets.sh" "$KIT/scripts/create-secrets.sh"

if ! grep -q '__SYSTEM_ADMIN_USERNAME__' "$KIT/compose/initial-config.yaml.template"; then
  echo "ERROR: initial-config template is missing __SYSTEM_ADMIN_USERNAME__" >&2
  exit 1
fi
if ! grep -q '${MUXON_API_CLIENT_SECRET}' "$KIT/compose/keycloak/realm-muxon-dev.json"; then
  echo "ERROR: realm template is missing \${MUXON_API_CLIENT_SECRET}" >&2
  exit 1
fi
if [[ -e "$KIT/secrets" || -e "$KIT/initial-config.yaml" || -e "$KIT/compose/keycloak/realm-muxon-dev.runtime.json" ]]; then
  echo "ERROR: staging directory contains runtime files" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TAR="$OUT_DIR/${KIT_NAME}.tar.gz"
ZIP="$OUT_DIR/${KIT_NAME}.zip"
rm -f "$TAR" "$ZIP"
tar -C "$STAGE" -czf "$TAR" "$KIT_NAME"
if ! command -v zip >/dev/null 2>&1; then
  echo "ERROR: zip is required to write ${ZIP}" >&2
  exit 1
fi
(cd "$STAGE" && zip -qr "$ZIP" "$KIT_NAME")

echo "Wrote $TAR"
echo "Wrote $ZIP"
