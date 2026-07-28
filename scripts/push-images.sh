#!/bin/bash
set -e

REGISTRY=${REGISTRY:-localhost:5000}
: "${REGISTRY_NAMESPACE:=scal}"
if [ -n "$REGISTRY_NAMESPACE" ]; then
  IMAGE_PREFIX="${REGISTRY}/${REGISTRY_NAMESPACE}"
else
  IMAGE_PREFIX="${REGISTRY}"
fi
VERSION=${VERSION:-0.1.0}
VARIANT=${VARIANT:-oss}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Local registry:2 is plain HTTP; Podman/Buildah need registries.conf, Docker needs daemon.json.
REGISTRY=$REGISTRY "$SCRIPT_DIR/ensure-insecure-local-registry.sh"

# Docker CLI + Podman socket: `docker push` still probes registries with Docker logic and ignores
# Podman registries.conf; use `podman push` when the engine is Podman.
PUSH_CLI=docker
if docker version 2>&1 | grep -qF "Podman Engine" && command -v podman >/dev/null 2>&1; then
  PUSH_CLI=podman
fi

echo "=== Pushing Docker Images ==="
echo "Pushing with: $PUSH_CLI (registry ${REGISTRY}, namespace ${REGISTRY_NAMESPACE})"
echo "Registry: $REGISTRY"
echo "Image prefix: $IMAGE_PREFIX"
echo "Version: $VERSION"
echo "Variant: $VARIANT"

# Core services
CORE_SERVICES=(
    "core-services"
    "orchestrator"
    "console-proxy"
    "muxon-initializer"
    "web"
)

# Enterprise-only services
ENTERPRISE_SERVICES=(
    "api-gateway"
    "director"
    "net-advanced"
    "audit-export"
)

# Push core services
echo ""
echo "Pushing core services..."
for service in "${CORE_SERVICES[@]}"; do
    echo "Pushing $service:$VERSION..."
    $PUSH_CLI push $IMAGE_PREFIX/$service:$VERSION
    $PUSH_CLI push $IMAGE_PREFIX/$service:latest
done

# Push enterprise services if variant is enterprise
if [ "$VARIANT" = "enterprise" ]; then
    echo ""
    echo "Pushing enterprise services..."
    for service in "${ENTERPRISE_SERVICES[@]}"; do
        echo "Pushing $service:$VERSION..."
        $PUSH_CLI push $IMAGE_PREFIX/$service:$VERSION
        $PUSH_CLI push $IMAGE_PREFIX/$service:latest
    done
fi

echo ""
echo "=== Push complete ==="
