#!/bin/bash
set -e

REGISTRY=${REGISTRY:-localhost:5000}
# Default to scal when unset; set REGISTRY_NAMESPACE= for flat names (REGISTRY/<service> only).
: "${REGISTRY_NAMESPACE:=scal}"
if [ -n "$REGISTRY_NAMESPACE" ]; then
  IMAGE_PREFIX="${REGISTRY}/${REGISTRY_NAMESPACE}"
else
  IMAGE_PREFIX="${REGISTRY}"
fi
VERSION=${VERSION:-0.1.0}
VARIANT=${VARIANT:-oss}

echo "=== Building Docker Images ==="
echo "Registry: $REGISTRY"
echo "Image prefix: $IMAGE_PREFIX"
echo "Version: $VERSION"
echo "Variant: $VARIANT"

# Core services (common to both OSS and Enterprise)
CORE_SERVICES=(
    "core-services"
    "orchestrator"
    "console-proxy"
    "muxon-initializer"
)

# Enterprise-only services
ENTERPRISE_SERVICES=(
    "api-gateway"
    "director"
    "net-advanced"
    "audit-export"
)

# Build core services
echo ""
echo "Building core services..."
for service in "${CORE_SERVICES[@]}"; do
    echo "Building $service..."

    DOCKERFILE_SERVICE="$service"
    BUILD_CONTEXT="../muxon-core"
    DOCKERFILE_PATH="$BUILD_CONTEXT/services/$DOCKERFILE_SERVICE/Dockerfile"
    if [ "$service" = "usage-billing" ]; then
        # usage-billing was moved to muxon-enterprise; Dockerfile expects repo root context.
        DOCKERFILE_SERVICE="usage-billing"
        # Build context must include both muxon-enterprise and muxon-core.
        BUILD_CONTEXT=".."
        DOCKERFILE_PATH="../muxon-enterprise/services/$DOCKERFILE_SERVICE/Dockerfile"
    fi

    docker build \
        --load \
        -t $IMAGE_PREFIX/$service:$VERSION \
        -t $IMAGE_PREFIX/$service:latest \
        -f "$DOCKERFILE_PATH" \
        $BUILD_CONTEXT
done

# Build web frontend
echo ""
echo "Building web frontend..."
docker build \
    --load \
    -t $IMAGE_PREFIX/web:$VERSION \
    -t $IMAGE_PREFIX/web:latest \
    ../muxon-web/

# Build enterprise services if variant is enterprise
if [ "$VARIANT" = "enterprise" ]; then
    echo ""
    echo "Building enterprise services..."
    for service in "${ENTERPRISE_SERVICES[@]}"; do
        echo "Building $service..."
        docker build \
                --load \
            -t $IMAGE_PREFIX/$service:$VERSION \
            -t $IMAGE_PREFIX/$service:latest \
            -f ../muxon-enterprise/services/$service/Dockerfile \
            ../muxon-enterprise/
    done
fi

echo ""
echo "=== Build complete (images under ${IMAGE_PREFIX}/) ==="
docker images | grep -F "$IMAGE_PREFIX/" | head -30
