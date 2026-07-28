.PHONY: help build-oss images-oss images-oss-push helm-oss publish-ghcr-oss registry-up registry-down

VERSION := $(shell cat VERSION)
REGISTRY ?= localhost:5000
REGISTRY_NAMESPACE ?= yorel

help:
	@echo "Muxon Core Build (OSS images + Helm)"
	@echo ""
	@echo "Prerequisites: sibling checkouts ../muxon-core and ../muxon-web"
	@echo "  Your user must be in the docker group (see README)."
	@echo ""
	@echo "  make build-oss          Build JARs needed by core-services image"
	@echo "  make images-oss         Build OSS Docker images (no push)"
	@echo "  make images-oss-push    Build + push OSS images to \$$REGISTRY"
	@echo "  make helm-oss           Package muxon-core Helm chart"
	@echo "  make publish-ghcr-oss   Publish OSS images to GHCR"
	@echo "  make registry-up        Start local registry + ChartMuseum"
	@echo "  make registry-down      Stop local registries"
	@echo ""
	@echo "Current: VERSION=$(VERSION) REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE)"

registry-up:
	docker compose -f registry-compose.yml up -d

registry-down:
	docker compose -f registry-compose.yml down

# Service Dockerfiles copy prebuilt JARs from the host.
build-oss:
	@echo "Building OSS JARs required for Docker images (version $(VERSION))..."
	cd ../muxon-core && ./gradlew \
		:services:core-services:bootJar \
		:services:muxon-initializer:bootJar \
		:services:orchestrator:bootJar \
		:services:console-proxy:bootJar \
		-x test \
		--no-daemon

images-oss: build-oss
	@echo "Building OSS Docker images..."
	REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE) VERSION=$(VERSION) ./scripts/build-images.sh

images-oss-push: images-oss
	@echo "Pushing OSS Docker images to $(REGISTRY)..."
	REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE) VERSION=$(VERSION) ./scripts/push-images.sh

helm-oss: images-oss
	VARIANT=oss REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE) VERSION=$(VERSION) ./scripts/package-helm.sh

publish-ghcr-oss:
	./scripts/publish-images-to-ghcr.sh oss
