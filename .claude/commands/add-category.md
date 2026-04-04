# Add Bill Category

Add a new bill category to BillMind.

## Steps

1. Add a new case to `BillCategory` enum in `BillMind/Models/Enums.swift`
   - Add `englishName`, `icon` (image asset name), `sfSymbol`, `color`
   - `displayName` returns `englishName` automatically
2. Generate an AI illustration for the category icon using `/gemini generate a cute cartoon [category] icon on cream background (#FDF6EC)`
3. Add the generated image to `Assets.xcassets/{icon_name}.imageset/`
4. Update the AI prompt in `BillMind/Utils/Prompts.swift` to include the new category
5. Run `/build` to verify compilation
6. Update the test in `Tests/BillMindTests.swift` to reflect the new count
