# BillMind

**Bill with AI Mind** — A travel bill tracking iOS app with AI-powered invoice recognition.

## Features

- **AI Bill Recognition** — Snap photos of receipts/invoices and let AI extract merchant, amount, date, category, and line items
- **Multiple AI Providers** — OpenAI GPT-5.4, Google Gemini 3.1, ByteDance Doubao Seed 2.0, Moonshot Kimi K2.5, Anthropic Claude 4.6
- **Journal-based Organization** — Group bills by trip or purpose, each with its own currency and mascot
- **Currency Conversion** — 11 popular currencies with live exchange rates for travel expense tracking
- **Sketch-style UI** — Warm hand-drawn aesthetic inspired by Zinnia, with 5 cute animal mascots
- **Statistics Dashboard** — Category breakdown, spending charts, monthly summaries
- **Export** — CSV and PDF export, plus configuration import/export

## Requirements

- iOS 17.0+
- Xcode 16.0+
- Swift 6.0

## Build

```bash
# Generate Xcode project (requires xcodegen)
brew install xcodegen
xcodegen generate

# Build from command line
xcodebuild -project BillMind.xcodeproj -scheme BillMind -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or open `BillMind.xcodeproj` in Xcode and run.

## Architecture

- **SwiftData** for persistence (Journal, BillRecord, AppSettings)
- **SwiftUI** with NavigationStack + sheet modals
- **Vision framework** for on-device OCR fallback
- **URLSession** for AI provider API calls (OpenAI-compatible + Anthropic format)
- **xcodegen** for project generation from `project.yml`

## Project Structure

```
BillMind/
├── App/            # Entry point, ContentView
├── Models/         # SwiftData models, enums, AI result types
├── Services/       # AI, OCR, currency, keychain, export services
├── Views/
│   ├── Main/       # JournalsListView, StatsDashboardView
│   ├── Journal/    # JournalDetailView, NewJournalView
│   ├── Bill/       # AddBillManualView, BillImportFlowView, BillDetailView
│   ├── Settings/   # SettingsView
│   └── Components/ # AnimalMascotView, HandDrawnButton, EmptyStateView
├── Theme/          # SketchTheme, SketchShapes
└── Utils/          # Extensions, AI prompt templates
```
