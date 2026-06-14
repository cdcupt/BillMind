# BillMind 2.0 — web client (Voyage)

Minimal React + Vite + TypeScript client for the BillMind API. Shares the
contract in [`../contract/openapi.yaml`](../contract/openapi.yaml): API types are
generated from it, so the client and server can never silently drift.

## Develop

```bash
npm install
npm run gen:api        # regenerate src/api/schema.ts from the contract
npm run dev            # http://localhost:5173 (proxies /v1 → :8080)
npm run build          # tsc -b && vite build → dist/
npm run preview        # serve the production build
```

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

Scaffold + Landing + shell are live and verified (desktop + mobile, no overflow).
Sign-in (Google Identity Services) and the Record/Stats data screens light up in
the following slices; the API + ledger they call are already green.
