import SwiftUI

@main
struct AuphonicAppApp: App {
    /// One batch per app: the view model is shared by the main window and
    /// the Settings scene, and `Window` (not `WindowGroup`) means Cmd+N cannot
    /// open a second, independent batch.
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        Window("AuphonicApp", id: "main") {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: MainWindowSize.defaultWidth, height: MainWindowSize.defaultHeight)

        // The system settings window: Cmd+, and the app menu entry come for free
        Settings {
            SettingsView(
                settingsManager: viewModel.settingsManager,
                audioPlayer: viewModel.audioPlayer,
                onTokenChanged: { Task { await viewModel.connectAndFetch() } }
            )
        }
    }
}
