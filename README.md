# BillMind

**Bill with AI Mind** — A travel bill tracking iOS app with AI-powered invoice recognition and artistic timeline generation.

## Features

- **AI Bill Recognition** — Snap photos of receipts/invoices and let AI extract merchant, amount, date, category, and line items
- **3 AI Providers** — Google Gemini, OpenAI, ByteDance Doubao — with model and pricing selection
- **Minds** — AI-generated sketch-style timeline infographics of your travel expenses, saveable and shareable
- **Journal-based Organization** — Group bills by trip or purpose, each with its own currency and mascot
- **11 Popular Currencies** — CNY, USD, EUR, JPY, KRW, THB, GBP, HKD, SGD, AUD, MYR
- **Statistics** — Category breakdown, daily/monthly charts, per-journal and total expenses, top merchants
- **Sketch-style UI** — Warm hand-drawn aesthetic with AI-generated mascot illustrations
- **Config Import/Export** — Share settings as JSON files between devices
- **Demo Mode** — Try all features without an API key (for App Store review or first-time exploration)
- **Privacy-first** — In-app AI data sharing consent, all data stored locally, no BillMind servers

## Screenshots

| Journals | Bill Detail | Minds | Statistics |
|----------|------------|-------|------------|
| Journal list with stats | Zoomable bill photo + details | AI-generated timeline | Charts + filters |

## Requirements

- iOS 17.0+
- Xcode 16.0+
- Swift 6.0
- [xcodegen](https://github.com/yonaskolb/XcodeGen) for project generation

## Build

```bash
brew install xcodegen
cd codes/github.com/BillMind
xcodegen generate
open BillMind.xcodeproj
# Run on iPhone 17 Pro simulator
```

## Architecture

- **SwiftData** for persistence (Journal, BillRecord, AppSettings)
- **SwiftUI** with NavigationStack + TabView (4 tabs)
- **AIService** with Gemini native API + OpenAI-compatible format
- **xcodegen** for project generation from `project.yml`
- **AI-generated illustrations** — all mascots and category icons created by Gemini, no emoji

## Project Structure

```
BillMind/
├── App/            # Entry point, TabView (Journals, Statistics, Minds, Settings)
├── Models/         # SwiftData models, enums, AI result types
├── Services/       # AI recognition, config import/export
├── Views/
│   ├── Main/       # JournalsListView, StatsPageView, MindsView
│   ├── Journal/    # JournalDetailView, NewJournalView
│   ├── Bill/       # BillImportFlowView, AddBillManualView, BillDetailView
│   ├── Settings/   # SettingsView, APIKeyEditorView, EditBillView
│   └── Components/ # AnimalMascotView, HandDrawnButton, EmptyStateView
├── Theme/          # SketchTheme, SketchShapes
└── Utils/          # Prompts, Extensions
```

## Configuration

Import `BillMind_config.json` in Settings to quickly set up:
```json
{
  "provider": "gemini",
  "model": "gemini-3-flash-preview",
  "imageModel": "gemini-3.1-flash-image-preview",
  "apiKey": "your-api-key",
  "defaultCurrency": "CNY"
}
```

## License

This project is licensed under the [MIT License](LICENSE).
