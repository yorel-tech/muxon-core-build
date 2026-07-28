#!/bin/bash
set -e

REGISTRY=${REGISTRY:-localhost:5000}
: "${REGISTRY_NAMESPACE:=yorel}"
if [ -n "$REGISTRY_NAMESPACE" ]; then
  IMAGE_PREFIX="${REGISTRY}/${REGISTRY_NAMESPACE}"
else
  IMAGE_PREFIX="${REGISTRY}"
fi
VERSION=${VERSION:-0.1.0}
HELM_REPO=${HELM_REPO:-http://localhost:8080}
VARIANT=${VARIANT:-oss}

echo "=== Packaging Helm Charts ==="
echo "Registry: $REGISTRY"
echo "Image prefix: $IMAGE_PREFIX"
echo "Version: $VERSION"
echo "Helm Repo: $HELM_REPO"
echo "Variant: $VARIANT"

# Create dist/helm directory if it doesn't exist
mkdir -p ../dist/helm

if [ "$VARIANT" = "oss" ]; then
    echo ""
    echo "Packaging muxon-core chart..."
    
    # Update image tags in values.yaml
    CHART_DIR="../muxon-core/deploy/helm/muxon-core"
    
    # Update version and appVersion in Chart.yaml
    sed -i.bak "s/^version:.*/version: $VERSION/" $CHART_DIR/Chart.yaml
    sed -i.bak "s/^appVersion:.*/appVersion: $VERSION/" $CHART_DIR/Chart.yaml
    
    # Update image registry and tag in values.yaml
    sed -i.bak "s|repository:.*|repository: ${IMAGE_PREFIX}/core-services|g" $CHART_DIR/values.yaml
    sed -i.bak "s|tag:.*|tag: $VERSION|g" $CHART_DIR/values.yaml
    
    # Package the chart
    helm package $CHART_DIR -d ../dist/helm/
    
    # Cleanup backup files
    rm -f $CHART_DIR/*.bak
    
    CHART_FILE="muxon-core-$VERSION.tgz"
    
elif [ "$VARIANT" = "enterprise" ]; then
    echo "ERROR: enterprise Helm packaging lives in muxon-enterprise-build (VARIANT=enterprise)."
    echo "From ../muxon-enterprise-build run: make helm-enterprise"
    exit 1
fi

# Push to ChartMuseum if it's localhost (local dev)
if [[ "$HELM_REPO" == http://localhost:* ]]; then
    echo ""
    echo "Pushing chart to ChartMuseum at $HELM_REPO..."
    
    for chart in ../dist/helm/*.tgz; do
        if [ -f "$chart" ]; then
            echo "Uploading $(basename $chart)..."
            curl -X POST \
                --data-binary "@$chart" \
                "$HELM_REPO/api/charts" || echo "Warning: Failed to upload $chart"
        fi
    done
fi

# Generate Helm repo index for GA releases
if [[ "$REGISTRY" != localhost:* ]]; then
    echo ""
    echo "Generating Helm repo index..."
    helm repo index ../dist/helm/ --url https://github.com/yorel/muxon/releases/download/v$VERSION/
fi

echo ""
echo "=== Packaging complete ==="
ls -lh ../dist/helm/
