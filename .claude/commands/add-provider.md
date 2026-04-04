# Add AI Provider

Add a new AI provider to BillMind.

## Steps

1. Add a new case to `AIProvider` enum in `BillMind/Models/Enums.swift`
   - Add `displayName`, `defaultModel`, `defaultImageModel`, `baseURL`, `usesGeminiFormat`, `iconName`, `color`
   - Add `availableModels` and `availableImageModels` arrays
   - Add pricing in `priceLabel(for:)` and short names in `shortName(for:)`
2. Update `AIService.swift` to handle the new provider's request/response format
3. Update `SettingsView.swift` if any provider-specific UI is needed
4. Update `MindsView.swift` if the provider supports image generation
5. Run `/build` to verify compilation
6. Add a test case in `Tests/BillMindTests.swift` for the new provider defaults
