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

    private static func openFirstAvailableURL(_ urls: [URL?]) {
        for url in urls.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
