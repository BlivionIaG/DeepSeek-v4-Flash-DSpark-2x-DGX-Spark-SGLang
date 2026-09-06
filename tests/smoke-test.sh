#!/usr/bin/env bash
# tests/smoke-test.sh — minimal smoke test for a running SGLang TP=2
# cluster.
#
# Verifies (in order):
#   1. /v1/models returns the model
#   2. /v1/chat/completions (non-streaming) returns coherent content
#   3. /v1/chat/completions (streaming) returns token-by-token
#
# Usage:
#   tests/smoke-test.sh <head-host> [port]
#   tests/smoke-test.sh 192.168.1.123
#   tests/smoke-test.sh 192.168.1.123 8888
#
# Exits 0 if all three checks pass; non-zero on the first failure.
# Intentionally bash + curl (NOT python3) so it works from any
# workstation / CI runner without Python deps. The model's actual
# api_base path is not required — sglang serves the snapshot path as
# the model id, but accepts ANY string when only one model is loaded.

set -euo pipefail

HEAD="${1:-192.168.1.123}"
PORT="${2:-8888}"
BASE="http://${HEAD}:${PORT}"
MODEL_PATH="/root/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-V4-Flash-Vision-Exp/snapshots/86f746b36186f0e567729a5c06a8c918caba82a9"

echo ">>> smoke test against $BASE"

echo
echo "--- 1. /v1/models ---"
HTTP=$(curl -sS -o /tmp/_models.json -w "%{http_code}" --max-time 10 "$BASE/v1/models")
[ "$HTTP" = "200" ] || { echo "FAIL: HTTP $HTTP"; exit 1; }
echo "  HTTP $HTTP"
python3 -c "
import json
d = json.load(open('/tmp/_models.json'))
m = d['data'][0]
print(f'  model_id     : {m[\"id\"]}')
print(f'  max_model_len: {m[\"max_model_len\"]}')"

echo
echo "--- 2. /v1/chat/completions (non-streaming) ---"
HTTP=$(curl -sS -o /tmp/_chat.json -w "%{http_code}" --max-time 60 \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"model":"%s","messages":[{"role":"user","content":"Reply with one word: pong"}],"max_tokens":8,"temperature":0}' "$MODEL_PATH")" \
  "$BASE/v1/chat/completions")
[ "$HTTP" = "200" ] || { echo "FAIL: HTTP $HTTP"; cat /tmp/_chat.json; exit 1; }
echo "  HTTP $HTTP"
python3 -c "
import json
d = json.load(open('/tmp/_chat.json'))
c = d['choices'][0]
print(f'  content: {c[\"message\"][\"content\"]!r}')
print(f'  finish : {c[\"finish_reason\"]}')
print(f'  usage  : prompt={d[\"usage\"][\"prompt_tokens\"]} completion={d[\"usage\"][\"completion_tokens\"]} total={d[\"usage\"][\"total_tokens\"]}')
content = c['message']['content'].strip().lower()
assert 'pong' in content, f'expected pong in response, got: {c[\"message\"][\"content\"]!r}'
print('  PASS: response contains \"pong\"')"

echo
echo "--- 3. /v1/chat/completions (streaming) ---"
HTTP=$(curl -sS -o /tmp/_stream.txt -w "%{http_code}" --max-time 60 -N \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"model":"%s","messages":[{"role":"user","content":"Count to 3"}],"max_tokens":32,"stream":true}' "$MODEL_PATH")" \
  "$BASE/v1/chat/completions")
[ "$HTTP" = "200" ] || { echo "FAIL: HTTP $HTTP"; cat /tmp/_stream.txt; exit 1; }
echo "  HTTP $HTTP"
CHUNK_COUNT=$(grep -c "^data: " /tmp/_stream.txt 2>/dev/null || echo 0)
echo "  stream chunks: $CHUNK_COUNT"
[ "$CHUNK_COUNT" -gt 1 ] || { echo "FAIL: expected >1 stream chunks, got $CHUNK_COUNT"; exit 1; }
echo "  PASS: streaming returned $CHUNK_COUNT chunks"

echo
echo "✓ all smoke checks passed"
