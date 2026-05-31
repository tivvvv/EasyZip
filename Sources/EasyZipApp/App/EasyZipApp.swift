import SwiftUI

@main
struct EasyZipApp: App {
    @NSApplicationDelegateAdaptor(EasyZipAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
