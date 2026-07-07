import AppKit
import Foundation

enum SystemSettingsOpener {
    static func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    static func openFinderExtensionSettings() {
        openFirstAvailableURL([
            URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"),
            URL(string: "x-apple.systempreferences:com.apple.preferences.extensions?Finder")
        ])
    }

    static func openNotificationSettings() {
        openFirstAvailableURL([
            URL(string: "x-apple.systempreferences:com.apple.preference.notifications"),
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        ])
    }

    static func openLoginItemsSettings() {
        openFirstAvailableURL([
            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
            URL(string: "x-apple.systempreferences:com.apple.preferences.users?LoginItems")
        ])
    }

    static func restartFinder() async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Finder"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return false
            }

            return process.terminationStatus == 0
        }.value
    }

    private static func openFirstAvailableURL(_ urls: [URL?]) {
        for url in urls.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
