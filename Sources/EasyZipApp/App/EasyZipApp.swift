import SwiftUI

@main
struct EasyZipApp: App {
    @NSApplicationDelegateAdaptor(EasyZipAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("易压缩") {
            EasyZipWorkspaceView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
