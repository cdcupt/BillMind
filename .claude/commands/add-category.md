# Add Bill Category

Add a new bill category to BillMind.

## Steps

1. Add a new case to `BillCategory` enum in `BillMind/Models/Enums.swift`
   - Add `displayName` (Chinese), `englishName`, `icon` (emoji), `sfSymbol`, `color`
2. Update the AI prompt in `BillMind/Utils/Prompts.swift` to include the new category
3. Run `/build` to verify compilation
4. Update the test in `Tests/BillMindTests.swift` to reflect the new count
