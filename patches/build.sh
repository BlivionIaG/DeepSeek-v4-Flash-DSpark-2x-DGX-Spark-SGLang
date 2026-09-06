#!/usr/bin/env bash
# patches/build.sh — rebuild the patched SGLang image from a clean checkout.
#
# Idempotent. Re-runs detect the existing build dir and re-apply the patches.
#
# Usage:
#   ./build.sh                              # uses defaults below
#   ./build.sh myuser/sglang:dev-v4f-2dgx-v2-patched-v3_patch002
#
# Requirements: docker (with buildx or classic builder), git, patch, GNU tar.
# Does NOT require sudo (uses the current user's docker context).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINNED_COMMIT="452239a74f5b31798290f57aeac2645d98a52f44"
IMAGE_TAG="${1:-blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001}"
BUILD_DIR="$(/usr/bin/mktemp -d /tmp/sglang-v4f-build.XXXXXX)"
TARBALL="/tmp/${IMAGE_TAG//[:\/]/_}.tar"

trap 'rm -rf "$BUILD_DIR"' EXIT

log() { printf '\033[1;36m[patches/build]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[patches/build]\033[0m %s\n' "$*" >&2; exit 1; }

# 1. clone sglang at the pinned commit
log "cloning sgl-project/sglang at $PINNED_COMMIT"
git clone --quiet https://github.com/sgl-project/sglang.git "$BUILD_DIR"
( cd "$BUILD_DIR" && git checkout --quiet "$PINNED_COMMIT" )

# 2. apply both patches (fail fast if either doesn't apply cleanly)
log "applying patches"
for p in deepseek_v4.py offloader.py; do
  log "  patch -p1 < $p.py.patch"
  ( cd "$BUILD_DIR" && patch -p1 < "$SCRIPT_DIR/$p.py.patch" ) \
    || fail "$p.py.patch failed to apply — upstream has drifted, rebase required"
done

# 3. build the image
#    Dockerfile overlay: FROM the upstream *patched* image, COPY the
#    two modified files into /sgl-workspace/sglang (where the upstream
#    image's WORKDIR lives).
log "building image: $IMAGE_TAG"
cp "$SCRIPT_DIR/Dockerfile" "$BUILD_DIR/Dockerfile"
docker build --tag "$IMAGE_TAG" "$BUILD_DIR"

# 4. save to a tarball for offline distribution
log "saving tarball: $TARBALL"
docker save --output "$TARBALL" "$IMAGE_TAG"
/usr/bin/ls -la "$TARBALL"

log "done."
log "  image:  $IMAGE_TAG"
log "  tarball: $TARBALL"
log "  load on a new host:  sudo docker load -i $TARBALL"
