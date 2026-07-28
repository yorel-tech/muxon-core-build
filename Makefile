.PHONY: help images-oss helm-oss publish-ghcr-oss

VERSION := $(shell cat VERSION)
REGISTRY ?= localhost:5000
REGISTRY_NAMESPACE ?= scal

help:
	@echo "Muxon Core Build"
	@echo "  make images-oss         Build + push OSS Docker images"
	@echo "  make helm-oss           Package muxon-core Helm chart"
	@echo "  make publish-ghcr-oss   Publish OSS images to GHCR"

images-oss:
	REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE) VERSION=$(VERSION) VARIANT=oss ./scripts/build-images.sh
	REGISTRY=$(REGISTRY) REGISTRY_NAMESPACE=$(REGISTRY_NAMESPACE) VERSION=$(VERSION) VARIANT=oss ./scripts/push-images.sh

helm-oss:
	VARIANT=oss ./scripts/package-helm.sh

publish-ghcr-oss:
	./scripts/publish-images-to-ghcr.sh oss
