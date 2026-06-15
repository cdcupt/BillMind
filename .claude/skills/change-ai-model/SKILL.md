---
name: change-ai-model
description: Change BillMind's live AI model on the production server — the Gemini model used for capture + the agent, or the OpenAI moderation model. Use when asked to switch, upgrade, downgrade, A/B, or roll back the model.
---

# Change BillMind's AI model

BillMind's AI models are **configuration, not code** — each is named in `server/Sources/App/ModelConfig.swift` and overridden by an environment variable on the production box. **Changing a model is an env edit + container recreate — no rebuild, ~10 seconds.**

| Env var | Controls | Current default |
|---|---|---|
| `GEMINI_MODEL` | all live AI: typed + photo capture, and the chat agent | `gemini-3-flash-preview` |
| `OPENAI_MODERATION_MODEL` | the safety gate on every user input | `omni-moderation-latest` |

> OpenAI is used **only** for moderation (+ image assets at build time). All live in-app AI is Gemini. Changing `GEMINI_MODEL` changes capture **and** the agent together.

## Where things live (no memory needed)

- **Box:** `ssh 9relay` (BandwagonHost VPS, `root@67.230.179.139`). If the `9relay` SSH alias isn't set up, see the `bwh-vps-access` notes or use `root@67.230.179.139`.
- **Env file (source of truth):** `/root/billmind.env` on the box (chmod 600 — holds secrets + the model vars). Mirror of local `~/.billmind/deploy.env`.
- **Container:** `billmind-server` (image `ghcr.io/cdcupt/billmind-server:latest`, bound to `127.0.0.1:8099`, on network `9relay_default`).
- **Public:** https://billmind.daichenlab.com (health: `/healthz`).

## Which models can I use?

**Verified working (safe picks):**
- `gemini-3-flash-preview` — Gemini 3, smartest, **preview** (Google may change/retire it). *Current.*
- `gemini-2.5-flash` — GA/stable, fast, cheap. **The reliable fallback** — use this if the preview ever breaks.
- `gemini-2.5-pro` — GA, more capable, slower + pricier (verify before relying on it for high volume).

**Do NOT use** (listed in the catalog but return 404 on actual use, like the retired `gemini-2.0-flash`): `gemini-3.5-flash`, `gemini-3-pro-preview`. **"Listed ≠ usable"** — always confirm with the probe below before switching.

For moderation, `omni-moderation-latest` is the newest (auto-updating alias) — no need to change it.

### Probe the live catalog + confirm a model actually serves requests

```bash
# 1) list the gemini models the key can see
ssh 9relay 'KEY=$(grep "^GEMINI_API_KEY=" /root/billmind.env | cut -d= -f2-); \
  curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$KEY" \
  | grep -oE "models/gemini-[a-z0-9.-]+" | sort -u'

# 2) CONFIRM a candidate actually answers generateContent (catalog can lie):
ssh 9relay 'KEY=$(grep "^GEMINI_API_KEY=" /root/billmind.env | cut -d= -f2-); \
  curl -s -o /dev/null -w "%{http_code}\n" \
  "https://generativelanguage.googleapis.com/v1beta/models/<MODEL>:generateContent?key=$KEY" \
  -H "Content-Type: application/json" -d "{\"contents\":[{\"parts\":[{\"text\":\"ok\"}]}]}"'
# 200 = usable. 404 = not available, do not switch to it.
```

## How to change the model (two ways)

### A. One command (preferred)

```bash
./server/deploy/set-model.sh gemini-2.5-flash
```
It edits `GEMINI_MODEL` in `/root/billmind.env`, recreates the container, prints the boot log, and verifies `/healthz`. Override the SSH target with `BILLMIND_SSH=...` if needed.

### B. By hand (if the script isn't handy)

```bash
ssh 9relay
# edit the env file — change the GEMINI_MODEL line (or OPENAI_MODERATION_MODEL):
sed -i 's|^GEMINI_MODEL=.*|GEMINI_MODEL=gemini-2.5-flash|' /root/billmind.env
# recreate the container (env file is authoritative — no -e GEMINI_MODEL needed):
docker stop billmind-server && docker rm billmind-server
docker run -d --name billmind-server --network 9relay_default --restart unless-stopped \
  --env-file /root/billmind.env -e LOG_LEVEL=info \
  -p 127.0.0.1:8099:8080 ghcr.io/cdcupt/billmind-server:latest
```

## Verify

```bash
ssh 9relay 'docker logs billmind-server 2>&1 | grep -i "AI models" | tail -1'
# → AI models — gemini=<your model>, moderation=omni-moderation-latest
curl -s -o /dev/null -w "%{http_code}\n" https://billmind.daichenlab.com/healthz   # → 200
```

## Roll back

If a model misbehaves or gets retired, switch back to the stable GA model:
```bash
./server/deploy/set-model.sh gemini-2.5-flash
```

## Notes

- Keep local `~/.billmind/deploy.env` in sync with the box's `/root/billmind.env` for parity.
- Never put the key in the repo, chat, or this skill — it lives only in `/root/billmind.env` (box) and `~/.billmind/deploy.env` (local).
- To change the **code default** (used only if the env var is unset), edit `ModelConfig.fromEnvironment()` in `server/Sources/App/ModelConfig.swift` — that *does* need a CI rebuild + image pull.
