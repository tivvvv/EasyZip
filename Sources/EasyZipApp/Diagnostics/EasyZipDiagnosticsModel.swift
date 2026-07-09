import EasyZipCore
import EasyZipShared
import Foundation
import UserNotifications

enum EasyZipDiagnosticID: String, CaseIterable, Sendable {
    case appLocation
    case finderExtensionBundle
    case sandboxEntitlements
    case finderExtension
    case appGroup
    case notificationPermission
    case rarCommand
    case zstdCommand
    case defaultOutputDirectory
    case codeSignature
}

enum EasyZipDiagnosticStatus: Equatable, Sendable {
    case normal
    case needsAction
    case unsupported

    var title: String {
        switch self {
        case .normal:
            "正常"
        case .needsAction:
            "需要处理"
        case .unsupported:
            "不支持自动检测"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:
            "checkmark.circle"
        case .needsAction:
            "exclamationmark.triangle"
        case .unsupported:
            "questionmark.circle"
        }
    }
}

enum EasyZipDiagnosticAction: Equatable, Sendable {
    case openApplications
    case openFinderExtensionSettings
    case openNotificationSettings
    case openLoginItemsSettings
    case requestNotificationAuthorization
    case openSettings
    case openWorkspace
    case restartFinder
}

struct EasyZipDiagnosticItem: Identifiable, Equatable, Sendable {
    let id: EasyZipDiagnosticID
    let title: String
    let detail: String
    let status: EasyZipDiagnosticStatus
    let actionTitle: String?
    let action: EasyZipDiagnosticAction?

    init(
        id: EasyZipDiagnosticID,
        title: String,
        detail: String,
        status: EasyZipDiagnosticStatus,
        actionTitle: String? = nil,
        action: EasyZipDiagnosticAction? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.actionTitle = actionTitle
        self.action = action
    }
}

struct EasyZipDiagnosticQuickAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let action: EasyZipDiagnosticAction

    init(
        id: String,
        title: String,
        systemImage: String,
        action: EasyZipDiagnosticAction
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

@MainActor
final class EasyZipDiagnosticsModel: ObservableObject {
    @Published private(set) var items: [EasyZipDiagnosticItem] = []
    @Published private(set) var quickActions: [EasyZipDiagnosticQuickAction] = []
    @Published private(set) var isRefreshing = false

    private let settings: EasyZipAppSettings
    private let bundleURL: URL
    private let notificationAuthorizationStatusProvider: () async -> UNAuthorizationStatus
    private let rarAvailabilityProvider: () -> ExternalToolAvailability
    private let zstdAvailabilityProvider: () -> ExternalToolAvailability
    private let codeSignatureStatusProvider: (URL) async -> EasyZipDiagnosticStatus
    private let appGroupIdentifier: String
    private let appGroupStatusProvider: (String) -> EasyZipDiagnosticStatus
    private let finderExtensionBundleStatusProvider: (URL) async -> EasyZipDiagnosticStatus
    private let sandboxEntitlementsStatusProvider: (URL, String) async -> EasyZipDiagnosticStatus

    init(
        settings: EasyZipAppSettings = .shared,
        bundleURL: URL = Bundle.main.bundleURL,
        appGroupIdentifier: String = FinderActionHandoffStore.configuredAppGroupIdentifier(),
        notificationAuthorizationStatusProvider: @escaping () async -> UNAuthorizationStatus =
            EasyZipDiagnosticsModel.currentNotificationAuthorizationStatus,
        rarAvailabilityProvider: @escaping () -> ExternalToolAvailability = {
            RARCommandResolver().availability()
        },
        zstdAvailabilityProvider: @escaping () -> ExternalToolAvailability = {
            ZstdCommandResolver().availability()
        },
        codeSignatureStatusProvider: @escaping (URL) async -> EasyZipDiagnosticStatus =
            EasyZipDiagnosticsModel.currentCodeSignatureStatus,
        appGroupStatusProvider: @escaping (String) -> EasyZipDiagnosticStatus =
            EasyZipDiagnosticsModel.currentAppGroupStatus,
        finderExtensionBundleStatusProvider: @escaping (URL) async -> EasyZipDiagnosticStatus =
            EasyZipDiagnosticsModel.currentFinderExtensionBundleStatus,
        sandboxEntitlementsStatusProvider: @escaping (URL, String) async -> EasyZipDiagnosticStatus =
            EasyZipDiagnosticsModel.currentSandboxEntitlementsStatus
    ) {
        self.settings = settings
        self.bundleURL = bundleURL
        self.appGroupIdentifier = appGroupIdentifier
        self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
        self.rarAvailabilityProvider = rarAvailabilityProvider
        self.zstdAvailabilityProvider = zstdAvailabilityProvider
        self.codeSignatureStatusProvider = codeSignatureStatusProvider
        self.appGroupStatusProvider = appGroupStatusProvider
        self.finderExtensionBundleStatusProvider = finderExtensionBundleStatusProvider
        self.sandboxEntitlementsStatusProvider = sandboxEntitlementsStatusProvider
    }

    var summaryTitle: String {
        if items.isEmpty {
            return "正在检查"
        }

        if needsActionCount > 0 {
            return "\(needsActionCount) 项需要处理"
        }

        if unsupportedCount > 0 {
            return "可自动检测项目正常"
        }

        return "安装状态正常"
    }

    var summaryDetail: String {
        if items.isEmpty {
            return "正在读取安装状态和系统权限."
        }

        if needsActionCount > 0 {
            return "建议先处理标记项目, 再确认 Finder 右键菜单是否出现."
        }

        if unsupportedCount > 0 {
            return "Finder Sync 启用状态仍需要在 System Settings 中人工确认."
        }

        return "安装位置, 签名, 共享容器, Finder 扩展和通知状态均已通过检测."
    }

    var needsActionCount: Int {
        items.filter { $0.status == .needsAction }.count
    }

    var unsupportedCount: Int {
        items.filter { $0.status == .unsupported }.count
    }

    func refresh() async {
        isRefreshing = true

        let notificationStatus = await notificationAuthorizationStatusProvider()
        let codeSignatureStatus = await codeSignatureStatusProvider(bundleURL)
        let finderExtensionBundleStatus = await finderExtensionBundleStatusProvider(bundleURL)
        let sandboxEntitlementsStatus = await sandboxEntitlementsStatusProvider(
            bundleURL,
            appGroupIdentifier
        )
        let rarAvailability = rarAvailabilityProvider()
        let zstdAvailability = zstdAvailabilityProvider()
        let appGroupStatus = appGroupStatusProvider(appGroupIdentifier)

        items = [
            appLocationItem(),
            finderExtensionBundleItem(for: finderExtensionBundleStatus),
            sandboxEntitlementsItem(for: sandboxEntitlementsStatus),
            finderExtensionItem(),
            appGroupItem(for: appGroupStatus),
            notificationPermissionItem(for: notificationStatus),
            rarCommandItem(for: rarAvailability),
            zstdCommandItem(for: zstdAvailability),
            defaultOutputDirectoryItem(),
            codeSignatureItem(for: codeSignatureStatus)
        ]
        quickActions = quickActionItems(for: notificationStatus)
        isRefreshing = false
    }

    func item(with id: EasyZipDiagnosticID) -> EasyZipDiagnosticItem? {
        items.first { $0.id == id }
    }

    private func appLocationItem() -> EasyZipDiagnosticItem {
        let path = bundleURL.standardizedFileURL.path

        guard path.hasPrefix("/Applications/") else {
            return EasyZipDiagnosticItem(
                id: .appLocation,
                title: "安装位置",
                detail: "建议将应用放入 /Applications, 当前路径为 \(path).",
                status: .needsAction,
                actionTitle: "打开 Applications",
                action: .openApplications
            )
        }

        return EasyZipDiagnosticItem(
            id: .appLocation,
            title: "安装位置",
            detail: "应用已位于 /Applications.",
            status: .normal
        )
    }

    private func finderExtensionItem() -> EasyZipDiagnosticItem {
        EasyZipDiagnosticItem(
            id: .finderExtension,
            title: "Finder 右键菜单",
            detail: "macOS 不提供稳定自动检测, 请在 Finder Extensions 中确认 EasyZip Finder Sync Extension 已启用.",
            status: .unsupported,
            actionTitle: "扩展设置",
            action: .openFinderExtensionSettings
        )
    }

    private func finderExtensionBundleItem(
        for status: EasyZipDiagnosticStatus
    ) -> EasyZipDiagnosticItem {
        switch status {
        case .normal:
            return EasyZipDiagnosticItem(
                id: .finderExtensionBundle,
                title: "Finder 扩展包",
                detail: "Finder Sync extension 已嵌入应用包.",
                status: .normal
            )
        case .needsAction:
            return EasyZipDiagnosticItem(
                id: .finderExtensionBundle,
                title: "Finder 扩展包",
                detail: "应用包内未找到可用 Finder Sync extension, 建议重新安装发布包.",
                status: .needsAction,
                actionTitle: "打开 Applications",
                action: .openApplications
            )
        case .unsupported:
            return EasyZipDiagnosticItem(
                id: .finderExtensionBundle,
                title: "Finder 扩展包",
                detail: "当前运行方式不是正式 .app 包, 无法检查 Finder Sync extension.",
                status: .unsupported
            )
        }
    }

    private func sandboxEntitlementsItem(
        for status: EasyZipDiagnosticStatus
    ) -> EasyZipDiagnosticItem {
        switch status {
        case .normal:
            return EasyZipDiagnosticItem(
                id: .sandboxEntitlements,
                title: "沙盒授权",
                detail: "App Sandbox, App Group 和文件访问授权完整.",
                status: .normal
            )
        case .needsAction:
            return EasyZipDiagnosticItem(
                id: .sandboxEntitlements,
                title: "沙盒授权",
                detail: "应用签名授权不完整, Finder 选择或 App Group handoff 可能不可用.",
                status: .needsAction,
                actionTitle: "打开 Applications",
                action: .openApplications
            )
        case .unsupported:
            return EasyZipDiagnosticItem(
                id: .sandboxEntitlements,
                title: "沙盒授权",
                detail: "当前运行方式不支持沙盒授权自动检测.",
                status: .unsupported
            )
        }
    }

    private func appGroupItem(for status: EasyZipDiagnosticStatus) -> EasyZipDiagnosticItem {
        switch status {
        case .normal:
            return EasyZipDiagnosticItem(
                id: .appGroup,
                title: "App Group",
                detail: "共享容器可用: \(appGroupIdentifier).",
                status: .normal
            )
        case .needsAction:
            return EasyZipDiagnosticItem(
                id: .appGroup,
                title: "App Group",
                detail: "共享容器不可用, Finder handoff 将使用开发环境回退目录.",
                status: .needsAction
            )
        case .unsupported:
            return EasyZipDiagnosticItem(
                id: .appGroup,
                title: "App Group",
                detail: "当前运行方式不支持共享容器自动检测.",
                status: .unsupported
            )
        }
    }

    private func notificationPermissionItem(
        for status: UNAuthorizationStatus
    ) -> EasyZipDiagnosticItem {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return EasyZipDiagnosticItem(
                id: .notificationPermission,
                title: "任务完成通知",
                detail: "系统通知权限已允许.",
                status: .normal
            )
        case .notDetermined:
            return EasyZipDiagnosticItem(
                id: .notificationPermission,
                title: "任务完成通知",
                detail: "尚未请求系统通知权限.",
                status: .needsAction,
                actionTitle: "请求权限",
                action: .requestNotificationAuthorization
            )
        case .denied:
            return EasyZipDiagnosticItem(
                id: .notificationPermission,
                title: "任务完成通知",
                detail: "系统通知权限已关闭, 任务完成后不会发送通知.",
                status: .needsAction,
                actionTitle: "通知设置",
                action: .openNotificationSettings
            )
        @unknown default:
            return EasyZipDiagnosticItem(
                id: .notificationPermission,
                title: "任务完成通知",
                detail: "当前系统通知状态无法自动识别.",
                status: .unsupported,
                actionTitle: "通知设置",
                action: .openNotificationSettings
            )
        }
    }

    private func rarCommandItem(
        for availability: ExternalToolAvailability
    ) -> EasyZipDiagnosticItem {
        guard let executableURL = availability.executableURL else {
            return EasyZipDiagnosticItem(
                id: .rarCommand,
                title: "RAR 压缩命令",
                detail: "未找到可执行的 rar 命令, 仅影响 .rar 压缩.",
                status: .needsAction
            )
        }

        return EasyZipDiagnosticItem(
            id: .rarCommand,
            title: "RAR 压缩命令",
            detail: executableURL.path,
            status: .normal
        )
    }

    private func zstdCommandItem(
        for availability: ExternalToolAvailability
    ) -> EasyZipDiagnosticItem {
        guard let executableURL = availability.executableURL else {
            return EasyZipDiagnosticItem(
                id: .zstdCommand,
                title: "Zstandard 压缩命令",
                detail: "未找到可执行的 zstd 命令, 仅影响 .tar.zst 压缩.",
                status: .needsAction
            )
        }

        return EasyZipDiagnosticItem(
            id: .zstdCommand,
            title: "Zstandard 压缩命令",
            detail: executableURL.path,
            status: .normal
        )
    }

    private func defaultOutputDirectoryItem() -> EasyZipDiagnosticItem {
        if let warning = settings.defaultOutputDirectoryWarning {
            return EasyZipDiagnosticItem(
                id: .defaultOutputDirectory,
                title: "默认输出目录",
                detail: warning,
                status: .needsAction,
                actionTitle: "打开设置",
                action: .openSettings
            )
        }

        if let outputDirectory = settings.defaultOutputDirectory {
            return EasyZipDiagnosticItem(
                id: .defaultOutputDirectory,
                title: "默认输出目录",
                detail: outputDirectory.displayPath,
                status: .normal
            )
        }

        return EasyZipDiagnosticItem(
            id: .defaultOutputDirectory,
            title: "默认输出目录",
            detail: "未指定默认输出目录, 压缩前需要选择输出目录.",
            status: .normal
        )
    }

    private func codeSignatureItem(
        for status: EasyZipDiagnosticStatus
    ) -> EasyZipDiagnosticItem {
        switch status {
        case .normal:
            return EasyZipDiagnosticItem(
                id: .codeSignature,
                title: "应用签名",
                detail: "签名校验通过.",
                status: .normal
            )
        case .needsAction:
            return EasyZipDiagnosticItem(
                id: .codeSignature,
                title: "应用签名",
                detail: "签名校验失败, 建议重新安装可信构建.",
                status: .needsAction
            )
        case .unsupported:
            return EasyZipDiagnosticItem(
                id: .codeSignature,
                title: "应用签名",
                detail: "当前运行方式不支持签名自动检测.",
                status: .unsupported
            )
        }
    }

    private func quickActionItems(
        for notificationStatus: UNAuthorizationStatus
    ) -> [EasyZipDiagnosticQuickAction] {
        var actions = [
            EasyZipDiagnosticQuickAction(
                id: "openFinderExtensionSettings",
                title: "扩展设置",
                systemImage: "puzzlepiece.extension",
                action: .openFinderExtensionSettings
            ),
            EasyZipDiagnosticQuickAction(
                id: "restartFinder",
                title: "重启 Finder",
                systemImage: "arrow.clockwise",
                action: .restartFinder
            ),
            EasyZipDiagnosticQuickAction(
                id: "openLoginItemsSettings",
                title: "登录项",
                systemImage: "power",
                action: .openLoginItemsSettings
            ),
            EasyZipDiagnosticQuickAction(
                id: "openWorkspace",
                title: "打开工作台",
                systemImage: "macwindow",
                action: .openWorkspace
            )
        ]

        switch notificationStatus {
        case .notDetermined:
            actions.insert(
                EasyZipDiagnosticQuickAction(
                    id: "requestNotificationAuthorization",
                    title: "请求通知",
                    systemImage: "bell.badge",
                    action: .requestNotificationAuthorization
                ),
                at: 2
            )
        case .denied:
            actions.insert(
                EasyZipDiagnosticQuickAction(
                    id: "openNotificationSettings",
                    title: "通知设置",
                    systemImage: "bell",
                    action: .openNotificationSettings
                ),
                at: 2
            )
        default:
            break
        }

        return actions
    }

    private static func currentNotificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    nonisolated private static func currentAppGroupStatus(
        groupIdentifier: String
    ) -> EasyZipDiagnosticStatus {
        FinderActionHandoffStore.appGroupDirectoryURL(groupIdentifier: groupIdentifier) == nil
            ? .needsAction
            : .normal
    }

    private static func currentFinderExtensionBundleStatus(
        for bundleURL: URL
    ) async -> EasyZipDiagnosticStatus {
        guard bundleURL.pathExtension == "app" else {
            return .unsupported
        }

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let extensionURL = finderExtensionBundleURL(for: bundleURL)
            let infoPlistURL = extensionURL.appendingPathComponent("Contents/Info.plist")
            let executableURL = extensionURL.appendingPathComponent(
                "Contents/MacOS/EasyZipFinderSyncExtension"
            )

            guard fileManager.fileExists(atPath: extensionURL.path),
                  fileManager.isExecutableFile(atPath: executableURL.path),
                  let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any],
                  plist["CFBundleExecutable"] as? String == "EasyZipFinderSyncExtension",
                  plist["CFBundlePackageType"] as? String == "XPC!",
                  let extensionPlist = plist["NSExtension"] as? [String: Any],
                  extensionPlist["NSExtensionPointIdentifier"] as? String == "com.apple.FinderSync" else {
                return EasyZipDiagnosticStatus.needsAction
            }

            return .normal
        }.value
    }

    private static func currentSandboxEntitlementsStatus(
        for bundleURL: URL,
        appGroupIdentifier: String
    ) async -> EasyZipDiagnosticStatus {
        guard bundleURL.pathExtension == "app" else {
            return .unsupported
        }

        return await Task.detached(priority: .utility) {
            let extensionURL = finderExtensionBundleURL(for: bundleURL)

            guard let appEntitlements = codesignEntitlements(for: bundleURL),
                  let extensionEntitlements = codesignEntitlements(for: extensionURL),
                  entitlementIsTrue("com.apple.security.app-sandbox", in: appEntitlements),
                  entitlementIsTrue("com.apple.security.app-sandbox", in: extensionEntitlements),
                  entitlementContains(
                    appGroupIdentifier,
                    key: "com.apple.security.application-groups",
                    in: appEntitlements
                  ),
                  entitlementContains(
                    appGroupIdentifier,
                    key: "com.apple.security.application-groups",
                    in: extensionEntitlements
                  ),
                  entitlementIsTrue(
                    "com.apple.security.files.user-selected.read-write",
                    in: appEntitlements
                  ),
                  entitlementIsTrue(
                    "com.apple.security.files.user-selected.read-only",
                    in: extensionEntitlements
                  ) else {
                return EasyZipDiagnosticStatus.needsAction
            }

            return .normal
        }.value
    }

    private static func currentCodeSignatureStatus(
        for bundleURL: URL
    ) async -> EasyZipDiagnosticStatus {
        guard bundleURL.pathExtension == "app" else {
            return .unsupported
        }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--deep", "--strict", bundleURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return EasyZipDiagnosticStatus.unsupported
            }

            return process.terminationStatus == 0 ? .normal : .needsAction
        }.value
    }

    nonisolated private static func finderExtensionBundleURL(for bundleURL: URL) -> URL {
        bundleURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent("EasyZipFinderSyncExtension.appex", isDirectory: true)
    }

    nonisolated private static func codesignEntitlements(for targetURL: URL) -> [String: Any]? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", targetURL.path]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }

        return plist
    }

    nonisolated private static func entitlementIsTrue(
        _ key: String,
        in entitlements: [String: Any]
    ) -> Bool {
        if let value = entitlements[key] as? Bool {
            return value
        }

        return (entitlements[key] as? NSNumber)?.boolValue == true
    }

    nonisolated private static func entitlementContains(
        _ expectedValue: String,
        key: String,
        in entitlements: [String: Any]
    ) -> Bool {
        let values = entitlements[key] as? [String]
        return values?.contains(expectedValue) == true
    }
}
