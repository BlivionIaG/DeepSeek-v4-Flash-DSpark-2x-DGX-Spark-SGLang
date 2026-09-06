#!/usr/bin/env bash
# recipe/scripts/start-tp2.sh — bring up the SGLang TP=2 cluster.
#
# Idempotent: re-runs detect the running containers and exit 0 without
# restarting them. Safe to invoke at every boot.
#
# Usage:
#   recipe/scripts/start-tp2.sh worker   # run on the WORKER host
#   recipe/scripts/start-tp2.sh head     # run on the HEAD host
#
# The HEAD rank binds 0.0.0.0:8888; the WORKER runs headless (rank-1,
# no public port). Both must share /root/.cache/huggingface AND the
# published docker image docker.io/blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001
# (upstream lmsysorg/sglang:dev-v4f-2dgx-v2 + 2 source-level patches — see README.md).
#
# Pre-conditions:
#   - 10.0.22.x/24 bound on enp1s0f1np1 on both hosts (MTU 9000)
#   - 10.0.23.x/24 bound on enP2p1s0f1np1 on both hosts (MTU 9000) — this
#     script auto-binds if missing (idempotent NetworkManager touch on
#     the auto-created profile)
#   - 100 GB NVMe swap at /swapfile_sgl priority 10 (see tasks/swap.yml
#     in the talos-infra ansible role)
#   - /root/.cache/huggingface populated on both hosts
#   - docker.io/blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001
#     pulled via `docker pull` (the recipe auto-pulls if missing —
#     see ensure_image below). Image is PRIVATE — one-time
#     `sudo docker login docker.io -u blivioniag` per host required.
#
# Env (.env.dspark in the same directory as this script, or sourced
# separately by the operator) controls the connection params; defaults
# here match the par1 deployment.

set -euo pipefail

ROLE="${1:-}"
case "$ROLE" in
  head|worker) ;;
  *)
    echo "usage: $0 head|worker" >&2
    echo "" >&2
    echo "  Run start-tp2.sh worker on the WORKER host first." >&2
    echo "  Then run start-tp2.sh head on the HEAD host." >&2
    echo "  The head's NCCL handshake retries against the worker for up to" >&2
    echo "  --dist-timeout (default 1800s); bring the worker up first." >&2
    exit 1
    ;;
esac

# Load operator env (optional — script also has working defaults)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../env/.env.dspark" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/../env/.env.dspark"
  set +a
fi

# Defaults (override via .env.dspark)
IMAGE="${SGLANG_IMAGE:-docker.io/blivioniag/sglang:dev-v4f-2dgx-v2-patched-v3_patch001}"
MODEL_PATH="${SGLANG_MODEL_PATH:-/root/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-V4-Flash-Vision-Exp/snapshots/86f746b36186f0e567729a5c06a8c918caba82a9}"
DIST_INIT_ADDR="${SGLANG_DIST_INIT_ADDR:-10.0.22.1:29500}"
DIST_TIMEOUT="${SGLANG_DIST_TIMEOUT:-1800}"
MEM_FRACTION_STATIC="${SGLANG_MEM_FRACTION_STATIC:-0.85}"
MAX_RUNNING_REQUESTS="${SGLANG_MAX_RUNNING_REQUESTS:-8}"
CONTEXT_LENGTH="${SGLANG_CONTEXT_LENGTH:-4096}"
SERVING_PORT="${SGLANG_SERVING_PORT:-8888}"
# DeepSeek V4 chat-template features. All three required for opencode-style
# agent loops. Set any to "" to disable.
# SGLang CLI: tool-call uses deepseekv4, reasoning uses deepseek-v4.
TOOL_CALL_PARSER="${SGLANG_TOOL_CALL_PARSER:-deepseekv4}"
REASONING_PARSER="${SGLANG_REASONING_PARSER:-deepseek-v4}"
SPECULATIVE_ALGORITHM="${SGLANG_SPECULATIVE_ALGORITHM:-DSPARK}"
CONTAINER_NAME="sglang-${ROLE}"

# NCCL envs (ConnectX RoCE on both enp1s0f1np1 + enP2p1s0f1np1, dual HCA;
# ADR 0063 follow-up #2 closed 2026-09-05 by binding 10.0.23.0/24 on the
# P-prefixed controller — see ensure_dual_hca_subnet below)
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=rocep1s0f1,roceP2p1s0f1
export NCCL_IB_GID_INDEX=3
export NCCL_SOCKET_IFNAME=enp1s0f1np1
export GLOO_SOCKET_IFNAME=enp1s0f1np1
export TP_SOCKET_IFNAME=enp1s0f1np1
export NCCL_IGNORE_CPU_AFFINITY=1

# SGLang-specific
export SGLANG_SM120_FLASHMLA_BACKEND=b12x
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

# Node-rank derivation
case "$ROLE" in
  head)
    NODE_RANK=0
    EXTRA_FLAGS=(--host 0.0.0.0 --port "$SERVING_PORT")
    ;;
  worker)
    NODE_RANK=1
    EXTRA_FLAGS=()
    ;;
esac

# Sanity checks
docker image inspect "$IMAGE" >/dev/null 2>&1 || {
  echo ">>> image '$IMAGE' not loaded locally; pulling from registry..."
  sudo docker pull "$IMAGE" || {
    echo "ERROR: docker pull failed for '$IMAGE'" >&2
    echo "  The image is private — one-time: sudo docker login docker.io -u blivioniag" >&2
    echo "  Tarball fallback (air-gapped): sudo docker load -i /path/to/image.tar" >&2
    exit 1
  }
}
[ -d "$(dirname "$MODEL_PATH")" ] || {
  echo "ERROR: MODEL_PATH directory does not exist: $MODEL_PATH" >&2
  exit 1
}

# ─────────────────────────────────────────────────────────────────
# Dual-HCA prerequisite: bind 10.0.23.0/24 on enP2p1s0f1np1 (the
# P-prefixed controller). NCCL_RDMAV2 GID validation rejects an HCA
# without an IP-bound GID, so without this bind the roceP2p1s0f1
# member of NCCL_IB_HCA cannot be used. Idempotent: re-runs detect
# the existing bind and no-op.
# ─────────────────────────────────────────────────────────────────
ensure_dual_hca_subnet() {
  local iface=enP2p1s0f1np1
  if ! ip link show "$iface" >/dev/null 2>&1; then
    echo "  [skip] $iface not present on this host (single-HCA topology?)"
    return 0
  fi
  if ip -o addr show "$iface" 2>/dev/null | awk '{print $4}' | grep -q "^10\.0\.23\."; then
    echo "  [ok]   $iface already has 10.0.23.x/24"
    return 0
  fi
  local ip
  case "$ROLE" in
    head)   ip="10.0.23.1/24" ;;
    worker) ip="10.0.23.2/24" ;;
  esac
  local conn
  conn=$(nmcli -t -f NAME,DEVICE con show | awk -F: -v dev="$iface" '$2 == dev {print $1; exit}')
  if [ -z "$conn" ]; then
    echo "ERROR: no NetworkManager connection found for $iface; bind $ip manually" >&2
    return 1
  fi
  echo "  [bind] adding $ip to $iface (MTU 9000) via NM connection '$conn'"
  sudo nmcli con modify "$conn" \
    ipv4.method manual ipv4.addresses "$ip" \
    802-3-ethernet.mtu 9000 connection.autoconnect yes
  sudo nmcli con up "$conn"
}
ensure_dual_hca_subnet

# Start the container (idempotent: --restart unless-stopped keeps it up)
echo ">>> launching $CONTAINER_NAME (rank $NODE_RANK) on $(hostname)"
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  --network host \
  --ulimit memlock=-1:-1 \
  --cap-add IPC_LOCK \
  --device /dev/infiniband \
  --shm-size=4g \
  --restart unless-stopped \
  -v /root/.cache/huggingface:/root/.cache/huggingface \
  -e HF_HUB_OFFLINE=1 \
  -e TRANSFORMERS_OFFLINE=1 \
  -e NCCL_IB_DISABLE=0 \
  -e NCCL_IB_HCA="$NCCL_IB_HCA" \
  -e NCCL_IB_GID_INDEX="$NCCL_IB_GID_INDEX" \
  -e NCCL_SOCKET_IFNAME="$NCCL_SOCKET_IFNAME" \
  -e GLOO_SOCKET_IFNAME="$GLOO_SOCKET_IFNAME" \
  -e TP_SOCKET_IFNAME="$TP_SOCKET_IFNAME" \
  -e NCCL_IGNORE_CPU_AFFINITY=1 \
  -e SGLANG_SM120_FLASHMLA_BACKEND=b12x \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  "$IMAGE" \
  sglang serve \
    --model-path "$MODEL_PATH" \
    --nnodes 2 \
    --node-rank "$NODE_RANK" \
    --tp-size 2 \
    --dist-init-addr "$DIST_INIT_ADDR" \
    --dist-timeout "$DIST_TIMEOUT" \
    --mem-fraction-static "$MEM_FRACTION_STATIC" \
    --max-running-requests "$MAX_RUNNING_REQUESTS" \
    --context-length "$CONTEXT_LENGTH" \
    --disable-cuda-graph \
    --disable-radix-cache \
    --weight-loader-drop-cache-after-load \
    --trust-remote-code \
    $([ -n "$TOOL_CALL_PARSER" ]      && echo "--tool-call-parser $TOOL_CALL_PARSER") \
    $([ -n "$REASONING_PARSER" ]     && echo "--reasoning-parser $REASONING_PARSER") \
    $([ -n "$SPECULATIVE_ALGORITHM" ] && echo "--speculative-algorithm $SPECULATIVE_ALGORITHM") \
    "${EXTRA_FLAGS[@]}"

echo ">>> $CONTAINER_NAME started. Tail logs with:"
echo "    docker logs -f $CONTAINER_NAME"
if [ "$ROLE" = "head" ]; then
  echo ">>> Then verify with: curl -sS http://$(hostname):$SERVING_PORT/v1/models"
fi
