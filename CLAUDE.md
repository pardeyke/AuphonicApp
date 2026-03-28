# CLAUDE.md

## Project Overview

AuphonicApp is a native macOS application (SwiftUI) that provides a GUI for the Auphonic audio processing service. Users can upload audio files, apply processing (leveling, noise reduction, filtering, loudness normalization), and download results. Supports batch processing and per-channel workflows.

## Build & Run

```bash
# Build
xcodebuild -project AuphonicApp.xcodeproj -scheme AuphonicApp build

# Run tests
xcodebuild -project AuphonicApp.xcodeproj -scheme AuphonicApp test

# Or open in Xcode
open AuphonicApp.xcodeproj
```

- **Target:** macOS 26.2+
- **Swift version:** 5.0
- **No external dependencies** — pure Swift + Apple frameworks (SwiftUI, AVFoundation, AVAudioEngine, AppKit)

## Architecture

MVVM pattern with a service layer:

- **Models/** — Data structures (`AuphonicModels.swift`, `OutputFormat.swift`)
- **Views/** — SwiftUI views + ViewModels (`AppViewModel`, `ManualOptionsState`, `ChannelTabsState` use `@Observable`)
- **Services/** — `AuphonicAPIClient`, `AudioPlayerService`, `WavChunkCopier`, `SettingsManager`, `NotificationService`
- **Processing/** — `ProcessingWorkflow` (single-file pipeline), `BatchWorkflow` (multi-file with rate limiting)

## Key Patterns

- Modern Swift concurrency (async/await) throughout
- `@Observable` macro for reactive state
- `MockURLProtocol` for API test mocking
- Swift Testing framework (`@Test` macro) for tests
- App is sandboxed with network + user-selected file access entitlements

## Tests

10 test files in `AuphonicAppTests/` covering API client, models, workflows, settings, formats, and credits. Uses `@testable import AuphonicApp`.
