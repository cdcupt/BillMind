# Build BillMind

Regenerate the Xcode project and build for iOS simulator.

## Steps

1. Run `xcodegen generate` from the project root to regenerate .xcodeproj from project.yml
2. Run `xcodebuild -project BillMind.xcodeproj -scheme BillMind -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
3. Report build success or failure with relevant error details
