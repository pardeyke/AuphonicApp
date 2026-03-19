  Architecture Overview

  AuphonicApp is a macOS desktop client for the Auphonic audio post-production API. Built with C++17 and JUCE 8.0.4, it follows a component-based UI with a state machine driving the processing
  pipeline.

  ---
  Component Diagram

  +------------------------------------------------------------------+
  |  AuphonicAppApplication (Main.cpp)                               |
  |  Entry point, creates MainWindow + MacStyleLookAndFeel           |
  |                                                                  |
  |  +------------------------------------------------------------+ |
  |  |  MainWindow (DocumentWindow)                                | |
  |  |  Native title bar, resizable 480x500 – 800x1200            | |
  |  |                                                             | |
  |  |  +--------------------------------------------------------+ | |
  |  |  |  MainComponent — UI coordinator                        | | |
  |  |  |  Owns all sub-components, routes callbacks             | | |
  |  |  |                                                        | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | CreditsComponent          | SettingsButton (gear) |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | FileDropComponent                                 |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | AudioPlayerComponent (A/B waveforms + controls)   |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | PreviewDurationComponent (Full/30s/1m/3m/5m/10m)  |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | PresetListComponent        | SavePresetButton     |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | Viewport                                          |  | | |
  |  |  |  |   ManualOptionsComponent (scrollable)             |  | | |
  |  |  |  |     Leveler / Noise / Filter / Loudness /         |  | | |
  |  |  |  |     Output Format / Output Behavior               |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | ProcessButton | CancelButton                      |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  |  | StatusComponent (status text + progress bar)       |  | | |
  |  |  |  +--------------------------------------------------+  | | |
  |  |  +--------------------------------------------------------+ | |
  |  +------------------------------------------------------------+ |
  +------------------------------------------------------------------+

                |                              |
                v                              v
  +-------------------------+    +----------------------------+
  | SettingsManager         |    | AuphonicApiClient          |
  | Persistent config       |    | REST client for            |
  | ~/Library/App Support/  |    | https://auphonic.com/api   |
  | AuphonicApp/            |    | All calls async on         |
  |                         |    | background threads         |
  | Stores:                 |    +----------------------------+
  |  - apiToken             |                 |
  |  - lastPresetUuid       |                 v
  |  - lastManualSettings   |    +----------------------------+
  |  - audioOutputDevice    |    | ProcessingWorkflow         |
  +-------------------------+    | State machine driving the  |
                                 | full processing pipeline   |
                                 +----------------------------+

  ---
  Components & Their Methods

  MainComponent (MainComponent.h/.cpp)

  The central coordinator. Owns all UI components and wires them together.

  ┌────────────────────────────┬─────────────────────────────────────────────────────────────────────────┐
  │           Method           │                                 Purpose                                 │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ MainComponent(initialFile) │ Sets up all sub-components, restores last config, connects to API       │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ resized()                  │ Lays out all sub-components vertically                                  │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ keyPressed(key)            │ Space bar toggles play/pause                                            │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ setFile(file)              │ Opens a file (used when another instance sends a file)                  │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ onSettingsClicked()        │ Shows settings dialog, reconnects on save                               │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ onProcessClicked()         │ Validates inputs, starts workflow with preset or manual settings        │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ onCancelClicked()          │ Cancels workflow, resets status                                         │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ onSavePresetClicked()      │ Shows name dialog, saves preset via API                                 │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ connectAndFetchUser()      │ Fetches user info + credits from API, handles auth errors               │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ refreshPresets()           │ Fetches preset list, restores last selected preset                      │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ refreshCredits()           │ Refreshes credit balance after processing                               │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ updateButtonStates()       │ Enables/disables Process, Cancel, Save Preset based on state            │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ saveCurrentConfig()        │ Persists preset UUID + widget state to SettingsManager                  │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ restoreLastConfig()        │ Restores manual settings from last session                              │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ workflowStateChanged()     │ Updates button states on workflow state change                          │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ workflowProgressChanged()  │ Updates status text + progress bar                                      │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ workflowCompleted()        │ Shows success dialog, loads processed file in player, refreshes credits │
  ├────────────────────────────┼─────────────────────────────────────────────────────────────────────────┤
  │ workflowFailed()           │ Shows error dialog                                                      │
  └────────────────────────────┴─────────────────────────────────────────────────────────────────────────┘

  ---
  ProcessingWorkflow (ProcessingWorkflow.h/.cpp)

  State machine that drives the entire processing lifecycle.

  States:
  Idle ──> ExtractingChannel ──> Trimming ──> CreatingProduction ──> Uploading
                                                                        |
             Done <── Saving <── Converting <── Downloading <── Processing
              |                                                     |
            Error <─────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────┐
  │                                        Method                                         │                                         Purpose                                          │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ start(file, presetUuid, settings, avoidOverwrite, writeXml, channel, previewDuration) │ Initializes state, resolves "keep" format, starts pipeline                               │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ cancel()                                                                              │ Sets cancelled flag, stops timer, cleans up temp files                                   │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepExtractChannel()                                                                  │ Background thread: extracts single channel to mono WAV temp file                         │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepTrimPreview()                                                                     │ Background thread: trims first N seconds to WAV temp file                                │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepCreateProduction()                                                                │ API: POST /productions.json (creates production with preset or manual settings)          │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepUpload()                                                                          │ API: uploads file to production, cleans up temp files after success                      │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepStart()                                                                           │ API: POST start.json, begins 5-second polling timer                                      │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepPollStatus()                                                                      │ API: GET production status. If done, downloads. If error, fails. Otherwise keeps polling │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepDownload(url)                                                                     │ API: downloads result file, strips WAV metadata, optionally converts format              │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepConvert(tempFile)                                                                 │ Background thread: WAV to AIFF conversion (for .aif/.aiff files)                         │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stripMetadata(file)                                                                   │ Re-writes WAV through JUCE to discard non-audio chunks                                   │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ stepSave(tempFile)                                                                    │ Moves temp to output path, optionally writes .json metadata, fires completed             │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ setState(state)                                                                       │ Updates state, notifies listener                                                         │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ setError(message)                                                                     │ Stops timer, sets Error state, notifies listener                                         │
  ├───────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────┤
  │ cleanupTempFile(file)                                                                 │ Deletes temp file if it exists, resets reference                                         │
  └───────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────┘

  ---
  AuphonicApiClient (AuphonicApiClient.h/.cpp)

  Async REST client. All methods run on background threads, callbacks fire on UI thread.

  ┌────────────────────────────────────────┬─────────────────────────────────────┬──────────────────────────────────────────────┐
  │                 Method                 │            API Endpoint             │                   Purpose                    │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ fetchUserInfo(cb)                      │ GET /user.json                      │ Gets credit balance (hours remaining)        │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ fetchPresets(cb)                       │ GET /presets.json                   │ Lists all user presets                       │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ fetchPresetDetails(uuid, cb)           │ GET /preset/{uuid}.json             │ Gets algorithms for a preset                 │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ savePreset(name, settings, cb)         │ POST /presets.json                  │ Creates new preset from settings             │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ createProduction(preset, settings, cb) │ POST /productions.json              │ Creates a new production                     │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ uploadFile(uuid, file, cb)             │ POST /production/{uuid}/upload.json │ Multipart file upload (300s timeout)         │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ startProduction(uuid, cb)              │ POST /production/{uuid}/start.json  │ Starts processing                            │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ getProductionStatus(uuid, cb)          │ GET /production/{uuid}.json         │ Polls status + progress                      │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ downloadFile(url, cb)                  │ GET (download URL)                  │ Downloads result to temp file (300s timeout) │
  ├────────────────────────────────────────┼─────────────────────────────────────┼──────────────────────────────────────────────┤
  │ setToken(token)                        │ —                                   │ Updates auth token                           │
  └────────────────────────────────────────┴─────────────────────────────────────┴──────────────────────────────────────────────┘

  ---
  FileDropComponent (FileDropComponent.h/.cpp)

  Drag-and-drop file selector with button fallback.

  ┌──────────────────────────┬──────────────────────────────────────────────────────────────────┐
  │          Method          │                             Purpose                              │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ setFile(file)            │ Programmatically sets file (from command line or other instance) │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ getFile()                │ Returns currently selected file                                  │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ isInterestedInFileDrag() │ Accepts wav/mp3/flac/aac/ogg/m4a/aif/aiff/opus                   │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ filesDropped()           │ Handles drag-and-drop, fires onFileSelected callback             │
  ├──────────────────────────┼──────────────────────────────────────────────────────────────────┤
  │ paint()                  │ Draws drop zone with file path or "Drop audio file here" prompt  │
  └──────────────────────────┴──────────────────────────────────────────────────────────────────┘

  ---
  AudioPlayerComponent (AudioPlayerComponent.h/.cpp)

  Dual-slot (A/B) waveform player with click-free crossfade.

  ┌─────────────────────────┬─────────────────────────────────────────────────────────────────────────────────┐
  │         Method          │                                     Purpose                                     │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ loadFile(file)          │ Loads original file into slot A, generates waveform thumbnail                   │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ loadProcessedFile(file) │ Loads processed result into slot B, enables A/B toggle                          │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ clearProcessedFile()    │ Removes slot B (when new file selected)                                         │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ togglePlayPause()       │ Play/pause toggle                                                               │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ stop()                  │ Stops playback                                                                  │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ hasFileLoaded()         │ Returns true if slot A has a file                                               │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ setOutputDevice(name)   │ Switches audio output device                                                    │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ paint()                 │ Draws two waveform thumbnails (A=top, B=bottom), time display, active highlight │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ mouseDown()             │ Click on waveform to seek; click inactive waveform to switch + play             │
  ├─────────────────────────┼─────────────────────────────────────────────────────────────────────────────────┤
  │ timerCallback()         │ 30Hz: updates time label. 200Hz: crossfade gain ramping (~35ms)                 │
  └─────────────────────────┴─────────────────────────────────────────────────────────────────────────────────┘

  ---
  ManualOptionsComponent (ManualOptionsComponent.h/.cpp)

  Complex options panel with conditional visibility. Sections:

  - Channel Selector — shown for multi-channel files
  - Adaptive Leveler — strength, compressor, separate music/speech, broadcast mode
  - Noise Reduction — method, noise/reverb/breath removal amounts
  - Filtering — high-pass, auto EQ, bandwidth extension
  - Loudness Normalization — target LUFS
  - Output Format — format + bitrate for lossy
  - Output Behavior — overwrite toggle, JSON metadata toggle

  ┌──────────────────────────────┬────────────────────────────────────────────────────────────────┐
  │            Method            │                            Purpose                             │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ getSettings()                │ Builds JSON with algorithms + output format for API submission │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ hasAnyEnabled()              │ True if any processing option is enabled                       │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ getWidgetState()             │ Serializes all combo IDs + toggle states for persistence       │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ applyWidgetState(state)      │ Restores widget state from saved JSON                          │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ applyApiSettings(algorithms) │ Reverse-maps API preset response to widget selections          │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ setFileChannelCount(n)       │ Updates channel selector for current file                      │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ getSelectedChannel()         │ 0=All, 1-N=specific channel                                    │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ updateDependentVisibility()  │ Shows/hides controls based on toggle states                    │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ resized()                    │ Row-based layout using helper lambdas                          │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────┤
  │ getRequiredHeight()          │ Calculates height from visible rows                            │
  └──────────────────────────────┴────────────────────────────────────────────────────────────────┘

  ---
  PresetListComponent (PresetListComponent.h/.cpp)

  Preset dropdown with modification tracking.

  ┌───────────────────────────────┬─────────────────────────────────────────────────┐
  │            Method             │                     Purpose                     │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ setPresets(presets)           │ Populates combo from API response               │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ setSelectedUuid(uuid)         │ Selects preset by UUID                          │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ getSelectedPresetUuid()       │ Returns UUID (empty if modified)                │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ getBasePresetUuid/Name()      │ Returns original preset info even when modified │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ setModified(bool)             │ Marks preset as modified, shows "(modified)"    │
  ├───────────────────────────────┼─────────────────────────────────────────────────┤
  │ isModified() / hasSelection() │ State queries                                   │
  └───────────────────────────────┴─────────────────────────────────────────────────┘

  ---
  CreditsComponent (CreditsComponent.h/.cpp)

  ┌──────────────────────────────┬───────────────────────────────────────────────────────────────────┐
  │            Method            │                              Purpose                              │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ setCredits(credits)          │ Sets available credit hours from API                              │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ setFile(file)                │ Reads file duration + channels, calculates cost                   │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ setPreviewDurationSeconds(s) │ Adjusts cost for preview mode, shows "[preview]"                  │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ getFileDurationSeconds()     │ Returns file duration                                             │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ getFileChannels()            │ Returns channel count                                             │
  ├──────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ paint()                      │ Draws credits remaining, file cost, red highlight if insufficient │
  └──────────────────────────────┴───────────────────────────────────────────────────────────────────┘

  ---
  PreviewDurationComponent (PreviewDurationComponent.h/.cpp)

  ┌─────────────────────────────┬──────────────────────────────────────────┐
  │           Method            │                 Purpose                  │
  ├─────────────────────────────┼──────────────────────────────────────────┤
  │ setFileDuration(seconds)    │ Shows/hides buttons based on file length │
  ├─────────────────────────────┼──────────────────────────────────────────┤
  │ getPreviewDurationSeconds() │ 0=Full, or 30/60/180/300/600             │
  └─────────────────────────────┴──────────────────────────────────────────┘

  ---
  SettingsComponent (SettingsComponent.h/.cpp)

  ┌───────────────────────────────────────┬─────────────────────────────────────────────────────────┐
  │                Method                 │                         Purpose                         │
  ├───────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ showDialog(settings, parent, onSaved) │ Static: shows modal dialog with token + device selector │
  └───────────────────────────────────────┴─────────────────────────────────────────────────────────┘

  ---
  SettingsManager (SettingsManager.h/.cpp)

  Persistent config stored at ~/Library/Application Support/AuphonicApp/.

  ┌─────────────────────────────┬─────────────────────────────────┐
  │           Method            │             Purpose             │
  ├─────────────────────────────┼─────────────────────────────────┤
  │ get/setApiToken()           │ Bearer token for Auphonic API   │
  ├─────────────────────────────┼─────────────────────────────────┤
  │ get/setLastPresetUuid()     │ Restores last preset on launch  │
  ├─────────────────────────────┼─────────────────────────────────┤
  │ get/setLastManualSettings() │ Restores widget state on launch │
  ├─────────────────────────────┼─────────────────────────────────┤
  │ get/setAudioOutputDevice()  │ Audio output device preference  │
  └─────────────────────────────┴─────────────────────────────────┘

  ---
  MacStyleLookAndFeel (MacStyleLookAndFeel.h/.cpp)

  Custom dark theme with macOS styling. Accent blue #007aff, dark background #1e1e1e, SF Pro Text font. Custom rendering for buttons, toggle switches, combo boxes, popup menus, progress bars, and
  text editors.

  ---
  End-to-End Data Flow

  1. User drops audio file
     → FileDropComponent.onFileSelected
     → AudioPlayer loads waveform, Credits reads duration/channels,
       PreviewDuration filters buttons, ManualOptions updates channel selector

  2. User selects preset (optional)
     → API: GET /preset/{uuid}.json
     → ManualOptions populated from API algorithms

  3. User adjusts manual options (optional)
     → Preset marked as "modified"
     → Widget state saved to disk

  4. User clicks Process
     → MainComponent validates file + token + options
     → workflow.start(file, preset, settings, flags...)

  5. ProcessingWorkflow executes:
     [Extract channel] → [Trim preview] → Create production → Upload →
     Start → Poll every 5s → Download → [Strip metadata] → [Convert] → Save

  6. On completion:
     → Success dialog with output path
     → Processed file loaded in AudioPlayer slot B (A/B comparison)
     → Credits refreshed from API

  ---
  Threading Model

  ┌─────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┐
  │           Thread            │                                   Operations                                   │
  ├─────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ UI thread                   │ All rendering, event handling, state updates, timer callbacks                  │
  ├─────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ Background (Thread::launch) │ Channel extraction, trimming, format conversion, all API calls                 │
  ├─────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ Marshaling                  │ MessageManager::callAsync() brings results back to UI thread                   │
  ├─────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ Timers                      │ 5s polling (workflow), 30Hz playback update (player), 200Hz crossfade (player) │
  └─────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┘
