# CLAUDE.md

This file provides guidance to Claude Code when working with the BillMind project.

## Project Overview

BillMind is an iOS travel bill tracking app with AI-powered invoice recognition and artistic timeline generation. Users photograph receipts, the app sends images to AI providers for structured extraction, and users review/confirm the results. The "Minds" feature generates sketch-style infographic timelines from bill data.

## Build & Test Commands

All commands run from the project root (`codes/github.com/BillMind/`):

```bash
xcodegen generate                    # Regenerate .xcodeproj from project.yml
xcodebuild -project BillMind.xcodeproj -scheme BillMind -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project BillMind.xcodeproj -scheme BillMindTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Or open `BillMind.xcodeproj` in Xcode.

## Architecture

```
BillMind/
├── App/                    # Entry point, ContentView (TabView with 4 tabs)
├── Models/
│   ├── Enums.swift         # AIProvider (3), BillCategory (10), AnimalType (5), CurrencyInfo
│   ├── Journal.swift       # SwiftData @Model — bill collection
│   ├── BillRecord.swift    # SwiftData @Model — individual bill + BillLineItem
│   ├── AppSettings.swift   # SwiftData @Model — singleton (provider, models, apiKey)
│   └── AIRecognitionResult.swift  # Codable struct for AI responses
├── Services/
│   ├── AIService.swift     # Multi-provider bill recognition (Gemini native + OpenAI-compatible)
│   └── ConfigService.swift # JSON config import/export
├── Views/
│   ├── Main/
│   │   ├── JournalsListView.swift   # Home: journal cards + stats dashboard
│   │   ├── StatsDashboardView.swift # Mini chart widget
│   │   ├── StatsPageView.swift      # Full statistics with charts + journal filter
│   │   └── MindsView.swift          # AI timeline infographic generator
│   ├── Journal/
│   │   ├── JournalDetailView.swift  # Bill list + mind image + currency widget
│   │   └── NewJournalView.swift     # Create journal with mascot/currency picker
│   ├── Bill/
│   │   ├── BillImportFlowView.swift # 3-step: Pick → Recognize → Review
│   │   ├── AddBillManualView.swift  # Manual bill entry
│   │   └── BillDetailView.swift     # Bill detail + edit + zoomable image viewer
│   ├── Settings/
│   │   └── SettingsView.swift       # Provider, models, API key, config, test connection
│   └── Components/
│       └── AnimalMascotView.swift   # Mascot, EmptyState, HandDrawnButton
├── Theme/
│   ├── SketchTheme.swift    # Colors, fonts, card modifiers
│   └── SketchShapes.swift   # WobblyRoundedRectangle
└── Utils/
    ├── Prompts.swift        # AI prompt templates
    └── Extensions.swift     # Color hex, Date helpers, Decimal formatting
```

**Persistence:** SwiftData with `@Model` classes. Auto-resets store on schema migration failure.

**AI Integration:** `AIService` supports 3 providers:
- Gemini uses native API (`X-goog-api-key` header, `generateContent` endpoint)
- OpenAI and Doubao use OpenAI-compatible `chat/completions` format
- Recognition model and image gen model are configured separately in Settings
- Images sent as base64 JPEG; AI returns structured JSON parsed into `AIRecognitionResult`

**Minds:** Uses Gemini image generation models to create sketch-style timeline infographics. One mind saved per journal as `Documents/minds/{journalId}/mind.jpg`.

**UI:** SwiftUI with NavigationStack + TabView (4 tabs: Journals, Statistics, Minds, Settings). Sketch-style theme with warm cream palette. All styling via `SketchTheme`.

**Project Generation:** Uses xcodegen (`project.yml`). Run `xcodegen generate` after adding/removing files.

## Key Patterns

- Complex types (imagePaths, lineItems) stored as JSON-encoded `Data` blobs in SwiftData
- `Decimal` amounts stored as `Double`, converted via computed properties
- Enum raw values stored as `String` with typed computed accessors
- `AppSettings.getOrCreate(context:)` ensures singleton settings instance
- ID-based navigation to avoid SwiftData object identity issues (`BillNavID` wrapper for bills)
- Animal mascots as AI-generated images (not emoji) — Cat, Owl, Bear, Rabbit, Fox
- Category icons as AI-generated images (not emoji)

## Key Notes

- Default provider is Gemini; default currency is CNY
- 3 providers: Gemini, OpenAI, Doubao (with model + pricing selection)
- All text is English (no Chinese characters in codebase)
- All illustrations are AI-generated (Gemini) — no emoji anywhere
- Don't create new .swift files; add to existing files when possible
- After modifying files, run `xcodegen generate` before building
- The `.xcodeproj` is generated — edit `project.yml` for build settings
- Delete app from simulator after SwiftData schema changes
