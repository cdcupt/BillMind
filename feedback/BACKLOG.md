# BillOwl — Feedback Backlog

Source: beta-user feedback Google Doc (`1nPe1ds7W4y7bRFwGXBKGTfrAB_gShMrCzwXDSgsUCe8`).
Raw text + 14 evidence images mirrored to `feedback/raw/` (gitignored — real users' financial screenshots, kept local only).
Triaged via the `feedback_triage` skill. Status legend: new / routed / in-progress / shipped / closed.

## ⚠️ Clarifications needed before executing

- **F2 scope:** "delete the old add-bill page, keep only the AI agent" — confirm whether *manual editing/correction of a recognized bill card* stays. The AI can misread money, so users likely still need to fix amount/category on a card. Removing the **separate old per-trip add-bill page** is clear; removing **all manual correction** would be risky. Which do you mean?
- **F4 root cause:** the "No API key configured" failure (img-02) looks like a **build/deploy/key-wiring** problem, not necessarily app code. Is the beta build supposed to call your server backend (per billmind2_deploy), and is that backend's AI key configured for the build the testers have? This decides whether F4 is a code fix or a config/deploy fix.

## Prioritized items

| id | title | severity | type | route | status | evidence |
|----|-------|----------|------|-------|--------|----------|
| **F4** | AI recognition dead — "No API key configured" / recognition failed | **broken (P0)** | bug/config | bpl | ✅ **shipped** (PR #5; was a free consequence of F2 — BillImportFlowView was the only caller of the local recognizer) | img-02 |
| **F3** | Image upload fails — `Server error 413: Payload Too Large` | **broken (P0)** | bug | bpl | ✅ **shipped + deployed** (PR #7; 10mb recognition route + client 2048px downscale; server redeployed) | img-03 |
| **F5** | Smart multi-input capture (fuse partials + dedup + batch review) — re-scoped from dedup-only | friction / data-integrity | feature | sdd_pipeline | 🟡 **in design** — PRD+DESIGN+TECH done (design/dedup/), awaiting PM checkpoint before build | text #10 + partial-photo case |
| **F1** | Rename a trip ("journey") | friction | feature (small) | bpl | ✅ **shipped + deployed** (PR #6; UI + sync push + server PATCH route, IDOR-guarded, tested) | img-01 |
| **F2** | Remove legacy per-trip "add bill" page; AI-capture-only | friction / tech-debt | ux/refactor | bpl | ✅ **shipped** (PR #5; kept card editing per PM) | img-01, img-02 |

### Notes per item
- **F4** — core product (AI capture) is failing for testers. Two distinct failure modes seen: "No API key configured" (img-02) and the 413 below (img-03). Top priority. Money must never be guessed (billmind2_ai_first) — a hard-fail is correct, but the feature must actually work.
- **F3** — payload exceeds server/proxy body limit. Fix = client-side downscale/compress before upload **and** raise the app/Caddy max body size (Caddy is shared on BWH — raise per-app, carefully; see bwh_multitenant_deploy).
- **F5** — dedup across multiple images/sentences submitted in one session, before the agent writes bills; touches the multi-input agent pipeline (billmind2_agent_pipeline). Substantial + money-sensitive → pipeline.
- **F1** — add a rename affordance to a trip (edit name). Quick win.
- **F2** — pending the clarification above.

## Test-data fixtures (from the doc — for QA, not backlog items)

Real example bills the user supplied to test recognition. Exercise: multi-currency (GBP/RMB), multi-record-from-one-image, refunds/negatives, foreign-merchant names.

| fixture | image | what it tests |
|---------|-------|---------------|
| TD1 | img-04 | single bill, London theatre merchandise, **238.40 GBP** |
| TD2 | img-05 | one wide screenshot → **3 records** (WIFI 282.00 / SIM 99.80 / W London Hotel 10906.42 RMB) |
| TD3 | img-06 | one wide screenshot → **2 records** (Airline 26177.00 / Visa 380.00 RMB) |
| TD4 | img-07 | single bill, third-party store, **373.00 RMB** |
| TD5 | img-08–14 | bank/credit-card statement, **many records**, incl. a **refund −112.24**, RMB statement of GBP spend |
