#!/usr/bin/env bash
# examples/api-call.sh — minimal invocation examples for the
# SGLang TP=2 service.
#
# Usage:
#   examples/api-call.sh chat "What is the capital of France?" 192.168.1.123 8888
#   examples/api-call.sh stream "Count from 1 to 5" 192.168.1.123 8888
#   examples/api-call.sh models 192.168.1.123 8888

set -euo pipefail

CMD="${1:-chat}"
HEAD="${3:-192.168.1.123}"
PORT="${4:-8888}"
BASE="http://${HEAD}:${PORT}"
MODEL_PATH="/root/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-V4-Flash-Vision-Exp/snapshots/86f746b36186f0e567729a5c06a8c918caba82a9"

case "$CMD" in
  chat)
    MSG="${2:-Reply with one word: pong}"
    curl -sS --max-time 60 \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c "import json,sys; print(json.dumps({'model':sys.argv[1],'messages':[{'role':'user','content':sys.argv[2]}],'max_tokens':64,'temperature':0}))" "$MODEL_PATH" "$MSG")" \
      "$BASE/v1/chat/completions" | python3 -m json.tool
    ;;

  stream)
    MSG="${2:-Count to 5}"
    curl -sS --max-time 60 -N \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c "import json,sys; print(json.dumps({'model':sys.argv[1],'messages':[{'role':'user','content':sys.argv[2]}],'max_tokens':32,'stream':True}))" "$MODEL_PATH" "$MSG")" \
      "$BASE/v1/chat/completions"
    ;;

  models)
    curl -sS --max-time 10 "$BASE/v1/models" | python3 -m json.tool
    ;;

  health)
    curl -sS --max-time 10 "$BASE/health" 2>/dev/null || echo "no /health endpoint"
    ;;

  *)
    echo "usage: $0 {chat|stream|models|health} [message] [host] [port]" >&2
    exit 1
    ;;
esac
