# BillMind 2.0 — web client (Voyage)

Minimal React + Vite + TypeScript client for the BillMind API. Shares the
contract in [`../contract/openapi.yaml`](../contract/openapi.yaml): API types are
generated from it, so the client and server can never silently drift.

## Develop

```bash
npm install
cp .env.example .env.local   # set VITE_GOOGLE_CLIENT_ID for sign-in
npm run gen:api        # regenerate src/api/schema.ts from the contract
npm run dev            # http://localhost:5173 (proxies /v1 → :8080)
npm run build          # tsc -b && vite build → dist/
npm run preview        # serve the production build
```

### Sign-in config

`VITE_GOOGLE_CLIENT_ID` is the Google OAuth **web** client ID (Google Cloud
Console → Credentials). It must match the server's `GOOGLE_CLIENT_ID` audience.
Without it the landing renders a "not configured" note instead of a dead button.
Sessions are bearer tokens in `localStorage` (the API is mobile-first / bearer
by design, shared with iOS — not cookie/BFF based).

Run the Vapor server (`cd ../server && swift run`) alongside `npm run dev`; the
Vite proxy forwards `/v1` and `/healthz` to `127.0.0.1:8080`.

## Layout

```
src/
├── api/
│   ├── schema.ts      # generated from contract/openapi.yaml (do not edit)
│   ├── client.ts      # typed fetch wrapper: bearer + one-shot refresh + api.*
│   └── session.ts     # token storage + change pub/sub
├── hooks/useSession.ts
├── components/AppShell.tsx     # authed frame: header + 4-section nav
├── screens/                    # Landing + Record / Stats / Minds / Settings
└── styles/                     # tokens.css (Voyage), buttons, global
```

## Design

"Voyage" — a warm travel ledger: cream paper with grain, ink text, a vermilion
stamp accent, passport-teal for figures. Caveat (handwriting) for headings,
Noto Serif (latin subset) for the ledger body. Tokens live in
`src/styles/tokens.css`.

## Status

Live and verified (desktop + mobile, no overflow): Landing + Google sign-in,
the 4-section shell, Record (capture → card → gap-resolution → confirm), Stats
(totals + category bars), and Settings (account + sign-out). Apple web sign-in
is a documented placeholder (needs a Services ID + domain verification).
