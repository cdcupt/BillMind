# CLAUDE.md

This file provides guidance to Claude Code when working with the BillMind project.

## Project Overview

BillMind is an iOS travel bill tracking app with AI-powered invoice recognition. Users photograph receipts, the app sends images to AI providers for structured extraction, and users review/confirm the results.

## Build & Test Commands

All commands run from the project root (`codes/github.com/BillMind/`):

```bash
xcodegen generate                    # Regenerate .xcodeproj from project.yml
xcodebuild -project BillMind.xcodeproj -scheme BillMind -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project BillMind.xcodeproj -scheme BillMindTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Or open `BillMind.xcodeproj` in Xcode.

## Architecture

**Persistence:** SwiftData with `@Model` classes (not Core Data). Models: `Journal`, `BillRecord`, `AppSettings`.

**AI Integration:** `AIService` supports 5 providers via a unified interface:
- OpenAI, Gemini, Doubao, Kimi use OpenAI-compatible chat/completions format
- Claude uses Anthropic messages format
- Images sent as base64 JPEG in multimodal message content
- AI returns structured JSON parsed into `AIRecognitionResult`

**UI:** SwiftUI with NavigationStack. Sketch-style theme (warm cream palette, rounded fonts, paper textures). All styling goes through `SketchTheme`.

**Project Generation:** Uses xcodegen (`project.yml`). After adding/removing files, run `xcodegen generate` to update the .xcodeproj.

## Key Patterns

- Complex types (imagePaths, lineItems) stored as JSON-encoded `Data` blobs in SwiftData
- `Decimal` amounts stored as `Double` in SwiftData, converted via computed properties
- Enum raw values stored as `String` in SwiftData with typed computed accessors
- `AppSettings.getOrCreate(context:)` ensures singleton settings instance
- Animal mascots are context-aware: Cat (empty states), Owl (AI processing), Bear (stats), Rabbit (success), Fox (settings)

## Key Notes

- Default currency is CNY; 11 popular travel currencies pre-loaded
- All view files use `SketchTheme` for colors/fonts — don't use raw Color/Font values
- Don't create new .swift files for Xcode targets; add to existing files when possible
- After modifying files, run `xcodegen generate` before building
- The `.xcodeproj` is generated — edit `project.yml` for build settings, not the pbxproj directly
