# BillMind 2.0 — API contract

`openapi.yaml` (OpenAPI 3.1) is the **single source of truth** for the HTTP API
shared by three consumers:

- **`/server`** — the Vapor implementation. The spec is hand-kept in sync with
  `server/Sources/App` and verified against `server/Tests/AppTests`.
- **iOS client** — re-points at this API (replaces the on-device-only flow).
- **`/web`** — the minimal web client; generate its API types from this file.

## Conventions

- **Money is a decimal string** (`NUMERIC(16,2)`), never a float.
- **Timestamps** are RFC 3339, except `cursor`/`since` (epoch seconds, sync paging).
- Every `/v1` path except `/v1/auth/*` needs a **bearer access token**.
- **Tenant isolation:** cross-user access returns **404** (not 403).
- **Money is never guessed:** a draft without an amount has `canSave=false`, and
  `POST /v1/bills/confirm` returns **422** when the amount is missing.

## Validate / generate

```bash
# validate (any OpenAPI linter)
npx @redocly/cli lint contract/openapi.yaml

# generate web TS types
npx openapi-typescript contract/openapi.yaml -o web/src/api/schema.ts
```
