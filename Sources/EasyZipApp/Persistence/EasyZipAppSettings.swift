import Combine
import EasyZipCore
import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
final class SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class EasyZipAppSettings: ObservableObject {
    static let shared = EasyZipAppSettings()

    @Published var defaultOutputDirectory: URL? {
        didSet {
            saveDefaultOutputDirectory()
            refreshDefaultOutputDirectoryAccess()
        }
    }
    @Published var defaultCompressionFormat: ArchiveFormat {
        didSet {
            userDefaults.set(defaultCompressionFormat.fileExtension, forKey: Keys.defaultCompressionFormat)
        }
    }
    @Published var defaultOverwritePolicy: OverwritePolicy {
        didSet {
            userDefaults.set(defaultOverwritePolicy.settingsValue, forKey: Keys.defaultOverwritePolicy)
        }
    }
    @Published var taskCompletionNotificationEnabled: Bool {
        didSet {
            userDefaults.set(
                taskCompletionNotificationEnabled,
                forKey: Keys.taskCompletionNotificationEnabled
            )
            if taskCompletionNotificationEnabled {
                notificationAuthorizationRequester()
            }
        }
    }
    @Published var shouldCreateContainingDirectory: Bool {
        didSet {
            userDefaults.set(shouldCreateContainingDirectory, forKey: Keys.shouldCreateContainingDirectory)
        }
    }
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var launchAtLoginErrorMessage: String?

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let launchAtLoginController: any LaunchAtLoginControlling
    private let notificationAuthorizationRequester: () -> Void
    private var securityScopedDefaultOutputDirectory: URL?

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        launchAtLoginController: any LaunchAtLoginControlling = SystemLaunchAtLoginController(),
        notificationAuthorizationRequester: @escaping () -> Void = TaskCompletionNotifier.requestAuthorization
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.launchAtLoginController = launchAtLoginController
        self.notificationAuthorizationRequester = notificationAuthorizationRequester
        defaultOutputDirectory = Self.loadDefaultOutputDirectory(from: userDefaults)
        defaultCompressionFormat = Self.loadDefaultCompressionFormat(from: userDefaults)
        defaultOverwritePolicy = Self.loadDefaultOverwritePolicy(from: userDefaults)
        taskCompletionNotificationEnabled = Self.loadBool(
            from: userDefaults,
            key: Keys.taskCompletionNotificationEnabled,
            defaultValue: true
        )
        shouldCreateContainingDirectory = Self.loadBool(
            from: userDefaults,
            key: Keys.shouldCreateContainingDirectory,
            defaultValue: true
        )
        launchAtLoginEnabled = launchAtLoginController.isEnabled
        refreshDefaultOutputDirectoryAccess()
    }

    var effectiveDefaultOutputDirectory: URL? {
        guard let defaultOutputDirectory,
              defaultOutputDirectoryIsAvailable else {
            return nil
        }

        return defaultOutputDirectory
    }

    var defaultOutputDirectoryWarning: String? {
        guard defaultOutputDirectory != nil,
              !defaultOutputDirectoryIsAvailable else {
            return nil
        }

        return "默认输出目录不可用, 请重新选择"
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard launchAtLoginController.isEnabled != isEnabled else {
            launchAtLoginEnabled = isEnabled
            launchAtLoginErrorMessage = nil
            return
        }

        do {
            try launchAtLoginController.setEnabled(isEnabled)
            launchAtLoginEnabled = launchAtLoginController.isEnabled
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginEnabled = launchAtLoginController.isEnabled
            let title = isEnabled ? "开机启动设置失败" : "关闭开机启动失败"
            launchAtLoginErrorMessage = "\(title): \(error.localizedDescription)"
        }
    }

    func restoreDefaults() {
        defaultOutputDirectory = nil
        defaultCompressionFormat = .zip
        defaultOverwritePolicy = .rename
        shouldCreateContainingDirectory = true
        taskCompletionNotificationEnabled = true
        setLaunchAtLoginEnabled(false)
    }

    func stopAccessingDefaultOutputDirectory() {
        securityScopedDefaultOutputDirectory?.stopAccessingSecurityScopedResource()
        securityScopedDefaultOutputDirectory = nil
    }

    private var defaultOutputDirectoryIsAvailable: Bool {
        guard let defaultOutputDirectory else {
            return true
        }

        var isDirectory = ObjCBool(false)
        let directoryExists = fileManager.fileExists(
            atPath: defaultOutputDirectory.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        guard directoryExists else {
            return false
        }

        return !requiresSecurityScopedFileAccess
            || securityScopedDefaultOutputDirectory != nil
    }

    private var requiresSecurityScopedFileAccess: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func saveDefaultOutputDirectory() {
        guard let defaultOutputDirectory else {
            userDefaults.removeObject(forKey: Keys.defaultOutputDirectoryPath)
            userDefaults.removeObject(forKey: Keys.defaultOutputDirectoryBookmark)
            return
        }

        userDefaults.set(defaultOutputDirectory.path, forKey: Keys.defaultOutputDirectoryPath)

        do {
            let bookmark = try defaultOutputDirectory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmark, forKey: Keys.defaultOutputDirectoryBookmark)
        } catch {
            userDefaults.removeObject(forKey: Keys.defaultOutputDirectoryBookmark)
        }
    }

    private static func loadDefaultOutputDirectory(from userDefaults: UserDefaults) -> URL? {
        if let bookmark = userDefaults.data(forKey: Keys.defaultOutputDirectoryBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale,
                   let refreshedBookmark = try? url.bookmarkData(
                       options: .withSecurityScope,
                       includingResourceValuesForKeys: nil,
                       relativeTo: nil
                   ) {
                    userDefaults.set(
                        refreshedBookmark,
                        forKey: Keys.defaultOutputDirectoryBookmark
                    )
                }
                return url
            }
        }

        guard let path = userDefaults.string(forKey: Keys.defaultOutputDirectoryPath),
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func refreshDefaultOutputDirectoryAccess() {
        stopAccessingDefaultOutputDirectory()

        guard let defaultOutputDirectory,
              defaultOutputDirectory.startAccessingSecurityScopedResource() else {
            return
        }

        securityScopedDefaultOutputDirectory = defaultOutputDirectory
    }

    private static func loadDefaultCompressionFormat(from userDefaults: UserDefaults) -> ArchiveFormat {
        guard let value = userDefaults.string(forKey: Keys.defaultCompressionFormat) else {
            return .zip
        }

        return ArchiveFormat.allCases.first { $0.fileExtension == value } ?? .zip
    }

    private static func loadDefaultOverwritePolicy(from userDefaults: UserDefaults) -> OverwritePolicy {
        guard let value = userDefaults.string(forKey: Keys.defaultOverwritePolicy) else {
            return .rename
        }

        return OverwritePolicy(settingsValue: value) ?? .rename
    }

    private static func loadBool(
        from userDefaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.bool(forKey: key)
    }
}

private enum Keys {
    static let defaultOutputDirectoryPath = "easyzip.settings.defaultOutputDirectoryPath"
    static let defaultOutputDirectoryBookmark = "easyzip.settings.defaultOutputDirectoryBookmark"
    static let defaultCompressionFormat = "easyzip.settings.defaultCompressionFormat"
    static let defaultOverwritePolicy = "easyzip.settings.defaultOverwritePolicy"
    static let taskCompletionNotificationEnabled = "easyzip.settings.taskCompletionNotificationEnabled"
    static let shouldCreateContainingDirectory = "easyzip.settings.shouldCreateContainingDirectory"
}

extension OverwritePolicy {
    var settingsValue: String {
        switch self {
        case .ask:
            "ask"
        case .skip:
            "skip"
        case .overwrite:
            "overwrite"
        case .rename:
            "rename"
        }
    }

    init?(settingsValue: String) {
        switch settingsValue {
        case "ask":
            self = .ask
        case "skip":
            self = .skip
        case "overwrite":
            self = .overwrite
        case "rename":
            self = .rename
        default:
            return nil
        }
    }
}
