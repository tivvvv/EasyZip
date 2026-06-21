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

        return "默认输出目录不可用, 将跟随源文件位置"
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

    private var defaultOutputDirectoryIsAvailable: Bool {
        guard let defaultOutputDirectory else {
            return true
        }

        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(
            atPath: defaultOutputDirectory.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private func saveDefaultOutputDirectory() {
        guard let defaultOutputDirectory else {
            userDefaults.removeObject(forKey: Keys.defaultOutputDirectoryPath)
            return
        }

        userDefaults.set(defaultOutputDirectory.path, forKey: Keys.defaultOutputDirectoryPath)
    }

    private static func loadDefaultOutputDirectory(from userDefaults: UserDefaults) -> URL? {
        guard let path = userDefaults.string(forKey: Keys.defaultOutputDirectoryPath),
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
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
