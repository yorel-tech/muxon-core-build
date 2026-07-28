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
    echo ""
    echo "Packaging muxon-core chart (dependency)..."
    
    # Package core chart first
    CORE_CHART_DIR="../muxon-core/deploy/helm/muxon-core"
    sed -i.bak "s/^version:.*/version: $VERSION/" $CORE_CHART_DIR/Chart.yaml
    sed -i.bak "s/^appVersion:.*/appVersion: $VERSION/" $CORE_CHART_DIR/Chart.yaml
    sed -i.bak "s|repository:.*|repository: ${IMAGE_PREFIX}/core-services|g" $CORE_CHART_DIR/values.yaml
    sed -i.bak "s|tag:.*|tag: $VERSION|g" $CORE_CHART_DIR/values.yaml
    helm package $CORE_CHART_DIR -d ../dist/helm/
    rm -f $CORE_CHART_DIR/*.bak
    
    echo ""
    echo "Packaging muxon-nexus chart..."
    
    # Package nexus chart
    NEXUS_CHART_DIR="../muxon-nexus/deploy/helm/muxon-nexus"
    sed -i.bak "s/^version:.*/version: $VERSION/" $NEXUS_CHART_DIR/Chart.yaml
    sed -i.bak "s/^appVersion:.*/appVersion: $VERSION/" $NEXUS_CHART_DIR/Chart.yaml
    sed -i.bak "s|repository:.*|repository: ${IMAGE_PREFIX}/core-services|g" $NEXUS_CHART_DIR/values.yaml
    sed -i.bak "s|tag:.*|tag: $VERSION|g" $NEXUS_CHART_DIR/values.yaml
    
    # Update dependency
    helm dependency update $NEXUS_CHART_DIR
    
    # Package the chart
    helm package $NEXUS_CHART_DIR -d ../dist/helm/
    
    # Cleanup backup files
    rm -f $NEXUS_CHART_DIR/*.bak
    
    CHART_FILE="muxon-nexus-$VERSION.tgz"
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
    helm repo index ../dist/helm/ --url https://github.com/scal/muxon/releases/download/v$VERSION/
fi

echo ""
echo "=== Packaging complete ==="
ls -lh ../dist/helm/
