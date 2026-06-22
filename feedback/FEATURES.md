# BillOwl — Full Feature List (beta coverage checklist)

Compiled by the Coordinator for the feature-coverage beta pass. Each row gets a PASS / FAIL / BLOCKED verdict.

## Auth
- Sign in with Google
- Sign in with Apple (known stub)
- Sign out

## Trips
- Create a trip (name, currency, cover animal)
- Trip list / home dashboard
- Rename a trip (F1)
- Delete a trip
- Switch active trip (Record tab "switch")

## Capture (Record tab)
- Text → AI bill card
- Photo → AI bill card
- Voice dictation → bill card (device-only)
- Compose: photo + caption → one bill (NEW)
- Multi-input → "Done adding" → untangle
- Fuse proposal: Combine / Split
- Duplicate group: Keep both / Keep one
- Clarify a card (fix-it chips for missing fields)
- Edit a card field; amount editor pre-fills current value
- Save (per-card + "Save all"); Record resets to fresh after save
- Save-all blocked-until-resolved hint
- Degrade notice when untangle can't run (unsynced/offline)

## Bills
- View a trip's bills (detail)
- Edit a saved bill (EditBillView)
- Delete a bill

## Other tabs
- Stats (charts/dashboard)
- Minds (AI timeline infographic)
- Settings (model/provider, privacy/consent, version, sign out)

## Cross-cutting
- Sync (bills/trips across devices)
- Multi-currency money-safety (never invent/merge an amount across currencies)
- First-launch welcome notice (no clipped background mascot)
