# CLAUDE.md

## Project Overview

AuphonicApp is a native macOS application (SwiftUI) built for a film-set sound recordist's workflow: batch-process individual channels of multichannel broadcast WAV files (BWF, typically 32-bit float, 2–10 channels) through the Auphonic API and write the processed channels back into untouched copies of the originals.

Core invariants:

- **Originals are never modified.** Output = byte-for-byte copy of the original with only the processed channels' samples patched in the data chunk (`ChannelReplacer`). Untouched channels and all metadata chunks (bext timecode, iXML track names, etc.) stay bit-perfect; the container keeps its sample format (incl. 32-bit float).
- **Files are grouped for batch configuration.** Files are sorted by BWF timecode (bext TimeReference) and consecutive runs with the same channel count form a `FileGroup`; API settings are configured once per group.
- **Stereo packing saves credits.** Auphonic bills per minute of upload duration regardless of channel count (3-min minimum per production), so unpaired mono channels are packed two-per-stereo-upload (`ChannelConfig.uploadJobs`). Only channels with identical settings may share an upload. Toggle per group in case joint stereo processing causes cross-channel interference.
- Multitrack productions are deliberately NOT used (user decision — unsuited to this workflow).

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
- **No external dependencies** — pure Swift + Apple frameworks (SwiftUI, AVFoundation, AppKit)

## Architecture

MVVM pattern with a service layer:

- **Models/** — `BatchFile`/`FileGroup`/`FileGrouper` (file metadata + timecode grouping), `ChannelConfig` (per-group channel selection, stereo pairing, packing into `UploadJob`s), `AuphonicModels.swift`, `OutputFormat.swift`
- **Views/** — SwiftUI views + `AppViewModel` (`@Observable`); `FileListView` (grouped batch list), `ChannelConfigView` (per-group config), `ManualOptionsView` (per-channel Auphonic algorithm settings, holds `ManualOptionsState`)
- **Services/** — `AuphonicAPIClient` (API-key bearer auth), `ChannelReplacer` (in-place channel patching), `WavChunkCopier` (RIFF chunk read/write, bext timecode, iXML track names), `AudioPlayerService`, `SettingsManager`, `NotificationService`
- **Processing/** — `BatchWorkflow`: per file → extract packed channels (chunked, format-preserving) → one Auphonic production per upload job (create/upload/start/poll/download, max 3 concurrent) → `ChannelReplacer` writes the output into the chosen destination folder under the original file name

## Key Patterns

- Modern Swift concurrency (async/await) throughout
- `@Observable` macro for reactive state
- Swift Testing framework (`@Test` macro) for tests
- App is sandboxed with network + user-selected file access entitlements
- RF64/BW64 (>4 GB WAVs) are detected and rejected with a clear error (not yet supported)

## Tests

Test files in `AuphonicAppTests/` covering the API client, models, channel packing (`ChannelConfigTests`), grouping/extraction/replacement round trips with generated WAVs (`BatchProcessingTests`), WAV chunk handling, settings, formats, and credits. Uses `@testable import AuphonicApp`. Real sample recordings live in `Testfiles/` (untracked).
