import SwiftUI

@main
struct EasyZipApp: App {
    @NSApplicationDelegateAdaptor(EasyZipAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EasyZipSettingsView(
                settings: .shared,
                openDiagnostics: {
                    Task { @MainActor in
                        appDelegate.openDiagnosticsFromSettingsScene()
                    }
                }
            )
        }
    }
}
