# Deploying BillMind 2.0

The stack is three containers — Postgres, the Vapor server, and Caddy
(auto-HTTPS + static web) — orchestrated by `docker-compose.yml` at the repo
root. Target host: the BWH VPS.

## Prerequisites

- Docker + Docker Compose on the host.
- DNS A/AAAA records for `API_DOMAIN` and `WEB_DOMAIN` pointing at the host
  (Caddy needs them resolvable to issue Let's Encrypt certs).
- Secrets ready: a `JWT_SIGNING_KEY` (`openssl rand -hex 48`), the Apple/Google
  client IDs, the Gemini key, and the OpenAI moderation key.

## One-time setup

```bash
git clone <repo> billmind && cd billmind
cp .env.example .env
$EDITOR .env            # fill in domains + every secret

# Build the web client (its dist/ is mounted into Caddy).
cd web && npm ci && npm run build && cd ..
```

## Bring it up

```bash
docker compose up -d --build
docker compose ps                       # all healthy?
curl -fsS https://$API_DOMAIN/healthz   # {"status":"ok",...}
```

On boot the server applies pending migrations automatically
(`CreateInitialSchema`) because `DATABASE_URL` is set.

## Updating

```bash
git pull
cd web && npm run build && cd ..        # if the web changed
docker compose up -d --build server caddy
```

## Operations

```bash
docker compose logs -f server           # app logs
docker compose exec db psql -U $POSTGRES_USER $POSTGRES_DB   # DB shell

# Backup / restore Postgres
docker compose exec -T db pg_dump -U $POSTGRES_USER $POSTGRES_DB > backup.sql
cat backup.sql | docker compose exec -T db psql -U $POSTGRES_USER $POSTGRES_DB
```

## Notes & gotchas

- **Build context is the repo root**, not `server/` — the package depends on
  `../shared/BillMindCore` via a local path. The Dockerfile and compose already
  account for this; don't `docker build` from inside `server/`.
- The first `--build` compiles Swift in release with the static stdlib; expect
  several minutes and ~2 GB RAM. A low-RAM VPS may need swap enabled.
- `web/dist` must exist before `docker compose up` (Caddy mounts it read-only).
  If you don't want the web site, remove the `web` block from `Caddyfile` and
  the `./web/dist` mount from `docker-compose.yml`.
- SSE (agent chat streaming) works through Caddy via `flush_interval -1`.
- Secrets live only in `.env` (gitignored). Rotate `JWT_SIGNING_KEY` by
  redeploying — existing access tokens are invalidated, clients refresh.
