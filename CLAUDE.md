# CLAUDE.md

## Project Overview

AuphonicApp is a native macOS application (SwiftUI) that batch-processes audio through the Auphonic API. It has **two modes** (`AppMode`, persisted in `SettingsManager.appMode`, switched in the toolbar):

- **Standard mode** — the general workflow: every file is uploaded as a whole, one production per file, and downloaded again in the chosen output format (`StandardModeConfig` + `StandardModeView`, `BatchWorkflow.processFileDirect`). No channel surgery, no grouping.
- **Mix Preparation mode** — the film-set workflow it was originally built for: process individual channels of multichannel broadcast WAVs (BWF, typically 32-bit float, 2–10 channels) and write them back into untouched copies of the originals, configured per group.

**Input** (`AudioFileTypes`, mode-dependent): Standard mode takes anything Core Audio can decode (WAV/BWF, AIFF, CAF, MP3, AAC/M4A, ALAC, FLAC …) — `AVAudioFile` decides what really opens. Mix Preparation accepts **WAV only**, because its output is a copy of the original with channels patched into the RIFF data chunk; switching into it drops non-WAV files from the batch.

Core invariants of Mix Preparation mode:

- **Originals are never modified.** Output = byte-for-byte copy of the original with only the processed channels' samples patched in the data chunk (`ChannelReplacer`). Untouched channels and all metadata chunks (bext timecode, iXML track names, etc.) stay bit-perfect; the container keeps its sample format (incl. 32-bit float).
- **Files are grouped for batch configuration.** Files are sorted by BWF timecode (bext TimeReference) and consecutive runs with the same channel count form a `FileGroup`; API settings are configured once per group.
- **Two production modes, switchable per group** (`ChannelConfig.productionMode`):
  - *Singletrack*: one mono production per selected channel (24-bit output). Channels must never share an upload — Auphonic support confirmed singletrack treats a stereo file as one finished mix.
  - *Multitrack*: one production per file, every selected channel uploaded as its own track (per-track denoise/leveler + master gate/crosstalk damping). Bills one 3-min minimum per file instead of per channel, but Auphonic currently exports individual tracks as **16-bit** (verified for both wav.zip and flac.zip) — 24-bit request pending with support.
- Multitrack always exports the individual tracks (written back into their own channels). Optionally the master mixdown is downloaded too (always requested with `mono_mixdown: true`) and written into a user-chosen channel of the output file.

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

- **Models/** — `AppMode` (Standard / Mix Preparation), `BatchFile`/`FileGroup`/`FileGrouper` (file metadata + timecode grouping), `ChannelConfig` (per-group channel selection, packing into `UploadJob`s), `StandardModeConfig` (Standard mode settings + output format), `AuphonicModels.swift`, `OutputFormat.swift`
- **Views/** — SwiftUI views + `AppViewModel` (`@Observable`); `FileListView` (flat list in Standard mode, grouped in Mix Preparation), `StandardModeView` (Standard mode settings + output format), `ChannelConfigView` (per-group config), `ManualOptionsView` (Auphonic algorithm settings, holds `ManualOptionsState`)
- **Services/** — `AuphonicAPIClient` (API-key bearer auth, singletrack + multitrack productions, streamed multipart upload), `AudioFileTypes` (accepted input formats), `ChannelReplacer` (in-place channel patching), `WavChunkCopier` (RIFF chunk read/write, bext timecode, iXML track names/timecode rate), `ZipArchive` (minimal ZIP reader for the tracks archive), `AudioPlayerService`, `SettingsManager`, `NotificationService`
- **Processing/** — `BatchWorkflow`, one run loop with two per-file paths:
  - *Standard mode* (`processFileDirect`): upload the file as it is → poll → download → save under the original base name with the chosen format's extension
  - *Mix Preparation*: extract channels (chunked, format-preserving) → *singletrack*: one production per channel (max 3 concurrent) / *multitrack*: one production with all tracks, unzip the tracks archive and map files back to channels → `ChannelReplacer` writes the output into the chosen destination folder under the original file name

## Key Patterns

- Modern Swift concurrency (async/await) throughout
- `@Observable` macro for reactive state
- Swift Testing framework (`@Test` macro) for tests
- App is sandboxed with network + user-selected file access entitlements
- RF64/BW64 (>4 GB WAVs) are detected and rejected with a clear error (not yet supported)

## Tests

Test files in `AuphonicAppTests/` covering the API client, models, channel packing (`ChannelConfigTests`), grouping/extraction/replacement round trips with generated WAVs (`BatchProcessingTests`), WAV chunk handling, settings, formats, and credits. Uses `@testable import AuphonicApp`. Real sample recordings live in `Testfiles/` (untracked).
