# Recording Agent

The recording agent turns photos, voice, or text into confirmed bills through a
rigorous, budgeted pipeline. This folder holds the **Foundation-only core** — the
state machine, validator, and DTOs — with no SwiftData, SwiftUI, or UIKit
dependencies, so the logic compiles and unit-tests without the iOS SDK and stays
decoupled from persistence and presentation.

## Pipeline

```
INTAKE → EXTRACT → VALIDATE → [gaps?] → CLARIFY ⇄ user → REVIEW → CONFIRM → recorded
         1 LLM call  pure Swift  ≤2 questions/turn,        complete   the only
         strict JSON rules        ≤2 rounds/card,          card       SwiftData
         null≠guess  (math/date)  chips patch directly                write
```

- **Validate** (`Validation.swift`) is deterministic and AI-free: it reconciles
  amount vs. Σ(line items), parses dates, checks currency against the journal, and
  maps categories. Flags come from arithmetic, never model confidence.
- **Clarify** asks only chip-answerable questions; an answer **pins** the field so
  re-validation cannot re-ask it, which bounds the loop. Budgets: ≤2 questions per
  turn, ≤2 rounds per card.
- **Skip** carries unresolved gaps to review **without backfilling any value**
  (honoring "never guess"); confirmation then requires explicit acknowledgment.
- **Confirm** is the single writer. It refuses unless the card is in `review`, has
  an amount (missing amount can never be confirmed, even acknowledged), and has no
  unacknowledged carried gaps. Only `.persist` tells the host to write a
  `BillRecord`.
- **Extraction failure** is a first-class, retryable `failed` state — never a
  silent partial card.
- **Budgets**: LLM calls are capped per session (`llmCallBudget`).

## Files

| File | Role |
|------|------|
| `BillDraft.swift` | In-memory draft (value type) + `DraftSource`, `BillField` |
| `CardState.swift` | Card lifecycle enum |
| `Validation.swift` | `BillValidator`, `ValidationGap`, `ClarificationQuestion` |
| `RecordingSession.swift` | The pure state machine + `SessionEffect`, `ConfirmError` |

## How the app wraps this

`RecordingSession` is a pure value type. The app layer (not yet in this PR) wraps
one instance in a `@MainActor` observable coordinator that:

1. owns the only `ModelContext` and performs the `.persist` effect — keeping the
   "single writer" rule structural;
2. fans extraction out over a `TaskGroup`, passing `Sendable` DTOs back to the
   actor (the existing bare-`Task` + scattered `MainActor.run` pattern in
   `BillImportFlowView` is the wrong template to extend under Swift 6);
3. renders cards/questions and feeds chip answers back via `answer(...)`.

## Verification status

| Piece | Status |
|-------|--------|
| Agent core (this folder) | **Compiled + unit-tested** under Swift 6 via `swiftc` (33 assertions) and mirrored in `Tests/RecordingAgentTests.swift` |
| `Utils/KeychainStore.swift` | **Typechecked** against the Security framework; not yet wired into call sites |
| `Utils/BillFileCleanup.swift` | **Compiled + tested** against a temp directory (incl. path-traversal guard) |
| `Models/BillMindSchema.swift` + `BillMindApp` migration | **Written, static-review only** — needs an Xcode build to verify (no Xcode/xcodegen on the authoring machine) |

> This machine has the Swift compiler but **no Xcode/xcodegen**, so anything that
> imports SwiftData/SwiftUI/UIKit could not be app-built here. Run
> `xcodegen generate` (these are new files) and the test target before merging.

## Not yet done (follow-ups)

- Wire `AppSettings` to `KeychainStore` with a one-time migration of the existing
  plaintext `apiKey`, and gate the API key out of `ConfigService` export.
- Add `BillMindSchemaV2` + a `MigrationStage` when persisting `sourceSessionID`
  and the audit-trail blob on `BillRecord`.
- Image downscaling (~1500px) at intake; provider structured-output mode in
  `AIService` (Validate is the backstop for providers without strict JSON).
- The SwiftUI Record tab + the `@MainActor` session coordinator.
