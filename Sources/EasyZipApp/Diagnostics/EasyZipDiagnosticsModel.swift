import EasyZipCore
import Foundation
import UserNotifications

enum EasyZipDiagnosticID: String, CaseIterable, Sendable {
    case appLocation
    case finderExtension
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
    case requestNotificationAuthorization
    case openSettings
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

@MainActor
final class EasyZipDiagnosticsModel: ObservableObject {
    @Published private(set) var items: [EasyZipDiagnosticItem] = []
    @Published private(set) var isRefreshing = false

    private let settings: EasyZipAppSettings
    private let bundleURL: URL
    private let notificationAuthorizationStatusProvider: () async -> UNAuthorizationStatus
    private let rarAvailabilityProvider: () -> ExternalToolAvailability
    private let zstdAvailabilityProvider: () -> ExternalToolAvailability
    private let codeSignatureStatusProvider: (URL) async -> EasyZipDiagnosticStatus

    init(
        settings: EasyZipAppSettings = .shared,
        bundleURL: URL = Bundle.main.bundleURL,
        notificationAuthorizationStatusProvider: @escaping () async -> UNAuthorizationStatus =
            EasyZipDiagnosticsModel.currentNotificationAuthorizationStatus,
        rarAvailabilityProvider: @escaping () -> ExternalToolAvailability = {
            RARCommandResolver().availability()
        },
        zstdAvailabilityProvider: @escaping () -> ExternalToolAvailability = {
            ZstdCommandResolver().availability()
        },
        codeSignatureStatusProvider: @escaping (URL) async -> EasyZipDiagnosticStatus =
            EasyZipDiagnosticsModel.currentCodeSignatureStatus
    ) {
        self.settings = settings
        self.bundleURL = bundleURL
        self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
        self.rarAvailabilityProvider = rarAvailabilityProvider
        self.zstdAvailabilityProvider = zstdAvailabilityProvider
        self.codeSignatureStatusProvider = codeSignatureStatusProvider
    }

    func refresh() async {
        isRefreshing = true

        let notificationStatus = await notificationAuthorizationStatusProvider()
        let codeSignatureStatus = await codeSignatureStatusProvider(bundleURL)
        let rarAvailability = rarAvailabilityProvider()
        let zstdAvailability = zstdAvailabilityProvider()

        items = [
            appLocationItem(),
            finderExtensionItem(),
            notificationPermissionItem(for: notificationStatus),
            rarCommandItem(for: rarAvailability),
            zstdCommandItem(for: zstdAvailability),
            defaultOutputDirectoryItem(),
            codeSignatureItem(for: codeSignatureStatus)
        ]
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
            detail: "macOS 不提供稳定自动检测, 请在 Finder Extensions 中确认 EasyZip 已启用.",
            status: .unsupported,
            actionTitle: "扩展设置",
            action: .openFinderExtensionSettings
        )
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
            detail: "未指定默认输出目录, 任务会跟随源文件位置.",
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

    private static func currentNotificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
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
}
