import SwiftUI

struct ShowSettingsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showSettings: Binding<Bool>? {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

@main
struct AuphonicAppApp: App {
    @FocusedValue(\.showSettings) private var showSettings

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    showSettings?.wrappedValue = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
