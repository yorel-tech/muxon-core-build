#!/bin/bash
set -euo pipefail

export DOCKER_BUILDKIT=1

REGISTRY=${REGISTRY:-localhost:5000}
# Default to yorel when unset; set REGISTRY_NAMESPACE= for flat names (REGISTRY/<service> only).
: "${REGISTRY_NAMESPACE:=yorel}"
if [ -n "$REGISTRY_NAMESPACE" ]; then
  IMAGE_PREFIX="${REGISTRY}/${REGISTRY_NAMESPACE}"
else
  IMAGE_PREFIX="${REGISTRY}"
fi
VERSION=${VERSION:-0.1.0}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
CORE_DIR="${MUXON_CORE_DIR:-$BUILD_ROOT/../muxon-core}"
WEB_DIR="${MUXON_WEB_DIR:-$BUILD_ROOT/../muxon-web}"

echo "=== Building OSS Docker Images ==="
echo "Registry: $REGISTRY"
echo "Image prefix: $IMAGE_PREFIX"
echo "Version: $VERSION"
echo "Core dir: $CORE_DIR"
echo "Web dir: $WEB_DIR"

if [ ! -f "$CORE_DIR/settings.gradle.kts" ] && [ ! -f "$CORE_DIR/settings.gradle" ]; then
  echo "ERROR: muxon-core not found at $CORE_DIR (set MUXON_CORE_DIR or clone sibling ../muxon-core)"
  exit 1
fi
if [ ! -f "$WEB_DIR/Dockerfile" ]; then
  echo "ERROR: muxon-web not found at $WEB_DIR (set MUXON_WEB_DIR or clone sibling ../muxon-web)"
  exit 1
fi

# Service images copy prebuilt JARs (see Dockerfiles).
require_jar() {
  local dir=$1
  local label=$2
  local jar
  jar=$(ls "$dir"/build/libs/*.jar 2>/dev/null | grep -v -- '-plain\.jar$' | head -n 1 || true)
  if [ -z "$jar" ]; then
    echo "ERROR: missing prebuilt JAR for $label ($dir/build/libs)."
    echo "Run first: make build-oss"
    exit 1
  fi
}

require_jar "$CORE_DIR/services/core-services" "core-services"
require_jar "$CORE_DIR/services/muxon-initializer" "muxon-initializer"
require_jar "$CORE_DIR/services/orchestrator" "orchestrator"
require_jar "$CORE_DIR/services/console-proxy" "console-proxy"

CORE_SERVICES=(
  "core-services"
  "orchestrator"
  "console-proxy"
  "muxon-initializer"
)

echo ""
echo "Building core services..."
for service in "${CORE_SERVICES[@]}"; do
  echo "Building $service..."
  docker build \
    -t "$IMAGE_PREFIX/$service:$VERSION" \
    -t "$IMAGE_PREFIX/$service:latest" \
    -f "$CORE_DIR/services/$service/Dockerfile" \
    "$CORE_DIR"
done

echo ""
echo "Building web frontend..."
docker build \
  -t "$IMAGE_PREFIX/web:$VERSION" \
  -t "$IMAGE_PREFIX/web:latest" \
  "$WEB_DIR"

echo ""
echo "=== Build complete (images under ${IMAGE_PREFIX}/) ==="
docker images | grep -F "$IMAGE_PREFIX/" | head -30
