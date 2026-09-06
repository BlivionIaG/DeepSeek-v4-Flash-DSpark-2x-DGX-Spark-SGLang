#!/usr/bin/env bash
# recipe/scripts/stop-tp2.sh — bring down the SGLang TP=2 cluster.
#
# Idempotent. Removes the sglang-head and sglang-worker containers on
# the LOCAL host. Run on each host separately (does NOT cross SSH).
#
# Usage:
#   recipe/scripts/stop-tp2.sh            # remove containers on this host
#   recipe/scripts/stop-tp2.sh --keep-image  # also keep the docker image

set -euo pipefail

KEEP_IMAGE=0
[ "${1:-}" = "--keep-image" ] && KEEP_IMAGE=1

for name in sglang-head sglang-worker; do
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    echo ">>> removing container: $name"
    docker rm -f "$name"
  else
    echo ">>> container $name not present, skipping"
  fi
done

if [ "$KEEP_IMAGE" = "0" ]; then
  IMAGE="${SGLANG_IMAGE:-docker.io/blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001}"
  if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE}$"; then
    echo ">>> removing image: $IMAGE"
    docker rmi "$IMAGE" || echo "  (image in use elsewhere or already gone)"
  fi
fi

echo "done"
