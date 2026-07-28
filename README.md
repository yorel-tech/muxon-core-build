# muxon-core-build

OSS Docker image and Helm packaging helpers for Muxon Core and shared web assets.

Enterprise/appliance packaging lives in [`muxon-enterprise-build`](../muxon-enterprise-build).

## Layout

Clone as siblings under one parent (for example `development/`):

```text
development/
  muxon-core/
  muxon-core-build/   ← you are here
  muxon-web/
```

Override paths with `MUXON_CORE_DIR` / `MUXON_WEB_DIR` if needed.

## Prerequisites

- Docker with BuildKit (`DOCKER_BUILDKIT=1` is default on modern Docker)
- Your user in the `docker` group:

  ```bash
  sudo usermod -aG docker "$USER"
  # then log out/in, or: newgrp docker
  ```

- Java 25 + the Gradle wrapper in `muxon-core` (used to pre-build JARs for `core-services`)

Optional: `sudo ./scripts/install-prerequisites.sh --minimal`

## Build OSS Docker images

```bash
cd muxon-core-build
make images-oss
```

This:

1. Builds service JARs in `../muxon-core` (`core-services`, `muxon-initializer`, `orchestrator`, `console-proxy`)
2. Builds images from those JARs plus `web` from `../muxon-web`

Push to a local registry (default `localhost:5000/yorel/...`):

```bash
make registry-up
make images-oss-push
```

Publish to GHCR:

```bash
make publish-ghcr-oss
```

## Useful variables

| Variable | Default | Meaning |
|---|---|---|
| `VERSION` | contents of `VERSION` | Image tag |
| `REGISTRY` | `localhost:5000` | Registry host |
| `REGISTRY_NAMESPACE` | `yorel` | Path under registry |
