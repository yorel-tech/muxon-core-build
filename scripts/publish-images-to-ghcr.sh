#!/usr/bin/env bash
# Build Muxon images locally and push them to GitHub Container Registry.
# Usage:
#   ./scripts/publish-images-to-ghcr.sh [oss|enterprise]
# Env:
#   GITHUB_OWNER   - GHCR owner/org (default: from `gh api user -q .login` or `scal`)
#   VERSION        - image tag (default: main.local)
#   REGISTRY_NAMESPACE - default scal
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-oss}"
OWNER="${GITHUB_OWNER:-}"
if [[ -z "$OWNER" ]]; then
  if command -v gh >/dev/null 2>&1; then
    OWNER="$(gh api user -q .login 2>/dev/null || true)"
  fi
fi
OWNER="${OWNER:-scal}"
export REGISTRY="${REGISTRY:-ghcr.io/${OWNER}}"
export VERSION="${VERSION:-main.local}"
export VARIANT
export REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-scal}"

echo "=== Publish images to GHCR ==="
echo "Registry: $REGISTRY"
echo "Version:  $VERSION"
echo "Variant:  $VARIANT"

if ! docker login ghcr.io >/dev/null 2>&1; then
  if command -v gh >/dev/null 2>&1; then
    echo "Logging into ghcr.io via gh auth token..."
    echo "$(gh auth token)" | docker login ghcr.io -u "$(gh api user -q .login)" --password-stdin
  else
    echo "ERROR: docker not logged into ghcr.io. Run: echo \$GH_TOKEN | docker login ghcr.io -u USERNAME --password-stdin"
    exit 1
  fi
fi

"$SCRIPT_DIR/build-images.sh"
"$SCRIPT_DIR/push-images.sh"

SHA_SHORT="$(git -C "$SCRIPT_DIR/../.." rev-parse --short HEAD 2>/dev/null || echo local)"
PREFIX="${REGISTRY}/${REGISTRY_NAMESPACE}"
SERVICES=(core-services orchestrator console-proxy muxon-initializer web)
if [[ "$VARIANT" == "enterprise" ]]; then
  SERVICES+=(api-gateway director net-advanced audit-export)
fi

echo "Tagging main aliases..."
for svc in "${SERVICES[@]}"; do
  docker tag "${PREFIX}/${svc}:${VERSION}" "${PREFIX}/${svc}:main" || true
  docker tag "${PREFIX}/${svc}:${VERSION}" "${PREFIX}/${svc}:main-${SHA_SHORT}" || true
  docker push "${PREFIX}/${svc}:main" || true
  docker push "${PREFIX}/${svc}:main-${SHA_SHORT}" || true
done

echo "=== Publish complete ==="
echo "Images under ${PREFIX}/ with tags: ${VERSION}, main, main-${SHA_SHORT}"
