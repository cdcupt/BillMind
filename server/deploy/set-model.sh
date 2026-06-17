#!/usr/bin/env bash
#
# set-model.sh — change BillMind's live Gemini model on the production box.
#
# Usage:   ./server/deploy/set-model.sh <gemini-model>
# Example: ./server/deploy/set-model.sh gemini-2.5-flash
#
# It edits GEMINI_MODEL in /root/billmind.env on the BWH box and recreates the
# container (the env file is the single source of truth — no rebuild needed).
# The SSH target defaults to the `9relay` alias; override with BILLMIND_SSH.
#
set -euo pipefail

MODEL="${1:-}"
if [[ -z "$MODEL" ]]; then
  echo "usage: $0 <gemini-model>   e.g. $0 gemini-2.5-flash" >&2
  exit 1
fi
SSH_TARGET="${BILLMIND_SSH:-9relay}"

echo "→ setting GEMINI_MODEL=$MODEL on $SSH_TARGET and recreating the container…"
ssh "$SSH_TARGET" bash -s -- "$MODEL" <<'REMOTE'
set -euo pipefail
MODEL="$1"
ENV_FILE=/root/billmind.env
if grep -q '^GEMINI_MODEL=' "$ENV_FILE"; then
  sed -i "s|^GEMINI_MODEL=.*|GEMINI_MODEL=$MODEL|" "$ENV_FILE"
else
  echo "GEMINI_MODEL=$MODEL" >> "$ENV_FILE"
fi
docker stop billmind-server >/dev/null && docker rm billmind-server >/dev/null
docker run -d --name billmind-server --network 9relay_default --restart unless-stopped \
  --env-file "$ENV_FILE" -e LOG_LEVEL=info \
  -p 127.0.0.1:8099:8080 ghcr.io/cdcupt/billmind-server:latest >/dev/null
sleep 6
echo -n "   boot log → "; docker logs billmind-server 2>&1 | grep -i "AI models" | tail -1
REMOTE

echo "→ verifying public health…"
code=$(curl -s -o /dev/null -w "%{http_code}" https://billmind.daichenlab.com/healthz --max-time 20 || true)
echo "   healthz: $code"
[[ "$code" == "200" ]] && echo "✓ done — $MODEL is live." || echo "✗ healthz not 200 — check 'ssh $SSH_TARGET docker logs billmind-server'."
