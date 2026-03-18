# AuphonicApp

macOS desktop client for the [Auphonic](https://auphonic.com) audio post-production service. Built with C++17 and JUCE 8.0.4.

## Build & Run

```bash
# Configure + build (universal binary: arm64 + x86_64)
./Packaging/build.sh

# Or manually:
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build --config Release --parallel

# Run
./build/AuphonicApp_artefacts/Release/AuphonicApp.app/Contents/MacOS/AuphonicApp
```

**Distribution (sign + notarize + DMG):**
```bash
./Packaging/distribute.sh
```

There are no tests in this project.

## Project Structure

```
Source/                          All application source code
  Main.cpp                      Entry point (JUCEApplication, MainWindow)
  MainComponent.h/.cpp          Main UI coordinator — owns all sub-components
  AuphonicApiClient.h/.cpp      REST API client (https://auphonic.com/api)
  ProcessingWorkflow.h/.cpp     State machine: extract → trim → upload → process → download → save
  SettingsManager.h/.cpp        Persistent config via JUCE ApplicationProperties
  SettingsComponent.h/.cpp      Settings dialog UI
  FileDropComponent.h/.cpp      Drag-and-drop file selector
  AudioPlayerComponent.h/.cpp   Waveform display + A/B playback with click-free crossfade
  PresetListComponent.h/.cpp    Preset dropdown selector
  ManualOptionsComponent.h/.cpp Processing parameter controls (leveler, noise, normalization, etc.)
  PreviewDurationComponent.h/.cpp  Preview duration toggle buttons
  CreditsComponent.h/.cpp       Credits display + cost estimation
  StatusComponent.h/.cpp        Status bar + progress indicator
  MacStyleLookAndFeel.h/.cpp    Custom macOS-native UI theme (extends LookAndFeel_V4)
Packaging/                      Build scripts, signing, icons
CMakeLists.txt                  CMake build config — fetches JUCE via FetchContent
```

## Architecture

- **Component-based UI**: Each UI section is a JUCE `Component` subclass. `MainComponent` coordinates them all.
- **Listener/Observer pattern**: `ProcessingWorkflow::Listener` notifies `MainComponent` of state/progress changes.
- **State machine**: `ProcessingWorkflow` drives the processing lifecycle (Idle → ExtractingChannel → Trimming → CreatingProduction → Uploading → Starting → Processing → Downloading → Converting → Saving → Done/Error).
- **Async threading**: API calls and file I/O run on background threads via `Thread::launch()`. UI updates marshal back via `MessageManager::callAsync()`.
- **Persistence**: `SettingsManager` wraps JUCE `ApplicationProperties` (stored in `~/Library/Application Support/AuphonicApp/`).

## Code Conventions

- **C++17**, JUCE idioms throughout
- **Naming**: PascalCase classes, camelCase methods/members, files match class names
- **Braces**: opening `{` on same line
- **Indentation**: 4 spaces
- **Memory**: prefer stack allocation, `std::unique_ptr`, RAII; avoid raw `new`
- **Leak detection**: all components use `JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR`
- **Threading**: never touch UI from background threads — always use `MessageManager::callAsync()`
- **Networking**: use JUCE's `URL` class (cURL and WebBrowser modules are disabled)

## Dependencies

Only dependency is **JUCE 8.0.4**, fetched automatically via CMake `FetchContent`. No package managers. JUCE modules used: `juce_core`, `juce_events`, `juce_gui_basics`, `juce_gui_extra`, `juce_audio_basics`, `juce_audio_devices`, `juce_audio_formats`, `juce_audio_utils`.

## Key Patterns

- **Adding a new source file**: add both `.h` and `.cpp` to `target_sources()` in `CMakeLists.txt`
- **Adding a new UI component**: create a `Component` subclass, instantiate it in `MainComponent`, position in `resized()`
- **API endpoints**: all go through `AuphonicApiClient` using bearer token auth from `SettingsManager`
- **Processing parameters**: `ManualOptionsComponent::getSettings()` returns a `juce::var` (JSON-like) for API submission
