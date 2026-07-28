#!/bin/bash
# Allow plain-HTTP access to a local dev registry (registry:2 on :5000).
# Docker Engine uses daemon.json; Podman/Buildah use registries.conf.d.
# Usage: source this file or: REGISTRY=host:port ./ensure-insecure-local-registry.sh
set -e

REG="${REGISTRY:-localhost:5000}"
# Strip a tag path if someone passed host:port/foo
REG="${REG%%/*}"
REG="${REG#http://}"
REG="${REG#https://}"

case "$REG" in
  localhost:5000 | 127.0.0.1:5000 | "[::1]:5000")
    ;;
  *)
    exit 0
    ;;
esac

if ! curl -sf --connect-timeout 3 "http://${REG}/v2/" >/dev/null 2>&1; then
  # Registry not up or not HTTP; let docker push report the real error.
  exit 0
fi

if docker version 2>&1 | grep -qF "Podman Engine"; then
  d="${XDG_CONFIG_HOME:-$HOME/.config}/containers/registries.conf.d"
  f="${d}/99-muxon-local-insecure.conf"
  mkdir -p "$d"
  if ! test -f "$f" || ! grep -qF "location = \"${REG}\"" "$f" 2>/dev/null; then
    {
      echo "# Muxon local dev registry (http://$REG) — allow plain HTTP for push/pull (added by muxon-build)"
      echo "[[registry]]"
      echo "location = \"${REG}\""
      echo "insecure = true"
    } >> "$f"
    echo "Wrote $f so Podman can use the HTTP registry at ${REG}." >&2
  fi
  exit 0
fi

# Docker Engine: must list this host explicitly; loopback CIDRs do not always apply to hostname "localhost".
di="$(docker system info 2>&1 || true)"
case "$REG" in
  localhost:5000)
    if echo "$di" | grep -F "localhost:5000" >/dev/null; then
      exit 0
    fi
    ;;
  127.0.0.1:5000 | "[::1]:5000")
    if echo "$di" | grep -E '127\.0\.0\.0/8|127\.0\.0\.1:5000' >/dev/null; then
      exit 0
    fi
    ;;
esac

cat <<EOF >&2
ERROR: Pushing to ${REG} requires the engine to allow this plain-HTTP (insecure) registry.

For Docker Engine, add to /etc/docker/daemon.json (merge with existing keys):
  { "insecure-registries": ["${REG}"] }
Then: sudo systemctl restart docker
(Rootless Docker: ~/.config/docker/daemon.json and restart the rootless service.)

For Podman, the helper should have created ~/.config/containers/registries.conf.d/
If you use a remote Docker context, run this on the machine where the engine runs.
EOF
exit 1
