import EasyZipCore
import UserNotifications
import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipDiagnosticsModelTests: XCTestCase {
    func testBuildsHealthyDiagnosticItems() async {
        let model = makeModel(
            bundleURL: URL(fileURLWithPath: "/Applications/易压缩.app", isDirectory: true),
            notificationStatus: .authorized,
            rarAvailability: ExternalToolAvailability(
                name: "rar",
                executableURL: URL(fileURLWithPath: "/usr/local/bin/rar")
            ),
            zstdAvailability: ExternalToolAvailability(
                name: "zstd",
                executableURL: URL(fileURLWithPath: "/usr/local/bin/zstd")
            ),
            codeSignatureStatus: .normal
        )

        await model.refresh()

        XCTAssertEqual(model.items.count, EasyZipDiagnosticID.allCases.count)
        XCTAssertEqual(model.item(with: .appLocation)?.status, .normal)
        XCTAssertEqual(model.item(with: .finderExtensionBundle)?.status, .normal)
        XCTAssertEqual(model.item(with: .sandboxEntitlements)?.status, .normal)
        XCTAssertEqual(model.item(with: .finderExtension)?.status, .unsupported)
        XCTAssertEqual(model.item(with: .appGroup)?.status, .normal)
        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .normal)
        XCTAssertEqual(model.item(with: .rarCommand)?.status, .normal)
        XCTAssertEqual(model.item(with: .zstdCommand)?.status, .normal)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.status, .normal)
        XCTAssertEqual(model.item(with: .codeSignature)?.status, .normal)
        XCTAssertEqual(model.needsActionCount, 0)
        XCTAssertEqual(model.quickActions.map(\.action), [
            .openFinderExtensionSettings,
            .restartFinder,
            .openLoginItemsSettings,
            .openWorkspace
        ])
    }

    func testBuildsActionableDiagnosticItems() async {
        let settings = makeSettings()
        settings.defaultOutputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyZipMissing-\(UUID().uuidString)", isDirectory: true)
        let model = makeModel(
            settings: settings,
            bundleURL: URL(fileURLWithPath: "/tmp/易压缩.app", isDirectory: true),
            notificationStatus: .denied,
            rarAvailability: ExternalToolAvailability(name: "rar", executableURL: nil),
            zstdAvailability: ExternalToolAvailability(name: "zstd", executableURL: nil),
            codeSignatureStatus: .needsAction,
            appGroupStatus: .needsAction,
            finderExtensionBundleStatus: .needsAction,
            sandboxEntitlementsStatus: .needsAction
        )

        await model.refresh()

        XCTAssertEqual(model.item(with: .appLocation)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .appLocation)?.action, .openApplications)
        XCTAssertEqual(model.item(with: .finderExtensionBundle)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .finderExtensionBundle)?.action, .openApplications)
        XCTAssertEqual(model.item(with: .sandboxEntitlements)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .sandboxEntitlements)?.action, .openApplications)
        XCTAssertEqual(model.item(with: .appGroup)?.status, .needsAction)
        XCTAssertNil(model.item(with: .appGroup)?.action)
        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .notificationPermission)?.action, .openNotificationSettings)
        XCTAssertTrue(model.quickActions.map(\.action).contains(.openNotificationSettings))
        XCTAssertEqual(model.item(with: .rarCommand)?.status, .needsAction)
        XCTAssertNil(model.item(with: .rarCommand)?.action)
        XCTAssertEqual(model.item(with: .zstdCommand)?.status, .needsAction)
        XCTAssertNil(model.item(with: .zstdCommand)?.action)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.action, .openSettings)
        XCTAssertEqual(model.item(with: .codeSignature)?.status, .needsAction)
        XCTAssertEqual(model.needsActionCount, 9)
        XCTAssertEqual(model.summaryTitle, "9 项需要处理")
    }

    func testRequestsNotificationPermissionWhenStatusIsNotDetermined() async {
        let model = makeModel(notificationStatus: .notDetermined)

        await model.refresh()

        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .notificationPermission)?.action, .requestNotificationAuthorization)
        XCTAssertTrue(model.quickActions.map(\.action).contains(.requestNotificationAuthorization))
    }

    func testReportsUnsupportedBundleSpecificChecksWhenNotRunningAsAppBundle() async {
        let model = makeModel(
            bundleURL: URL(fileURLWithPath: "/tmp/EasyZipApp", isDirectory: false),
            finderExtensionBundleStatus: .unsupported,
            sandboxEntitlementsStatus: .unsupported
        )

        await model.refresh()

        XCTAssertEqual(model.item(with: .finderExtensionBundle)?.status, .unsupported)
        XCTAssertEqual(model.item(with: .sandboxEntitlements)?.status, .unsupported)
    }

    private func makeModel(
        settings: EasyZipAppSettings? = nil,
        bundleURL: URL = URL(fileURLWithPath: "/Applications/易压缩.app", isDirectory: true),
        notificationStatus: UNAuthorizationStatus = .authorized,
        rarAvailability: ExternalToolAvailability = ExternalToolAvailability(
            name: "rar",
            executableURL: URL(fileURLWithPath: "/usr/local/bin/rar")
        ),
        zstdAvailability: ExternalToolAvailability = ExternalToolAvailability(
            name: "zstd",
            executableURL: URL(fileURLWithPath: "/usr/local/bin/zstd")
        ),
        codeSignatureStatus: EasyZipDiagnosticStatus = .normal,
        appGroupStatus: EasyZipDiagnosticStatus = .normal,
        finderExtensionBundleStatus: EasyZipDiagnosticStatus = .normal,
        sandboxEntitlementsStatus: EasyZipDiagnosticStatus = .normal
    ) -> EasyZipDiagnosticsModel {
        EasyZipDiagnosticsModel(
            settings: settings ?? makeSettings(),
            bundleURL: bundleURL,
            appGroupIdentifier: "group.com.tiv.easyzip",
            notificationAuthorizationStatusProvider: { notificationStatus },
            rarAvailabilityProvider: { rarAvailability },
            zstdAvailabilityProvider: { zstdAvailability },
            codeSignatureStatusProvider: { _ in codeSignatureStatus },
            appGroupStatusProvider: { _ in appGroupStatus },
            finderExtensionBundleStatusProvider: { _ in finderExtensionBundleStatus },
            sandboxEntitlementsStatusProvider: { _, _ in sandboxEntitlementsStatus }
        )
    }

    private func makeSettings() -> EasyZipAppSettings {
        EasyZipAppSettings(
            userDefaults: makeUserDefaults(),
            launchAtLoginController: DiagnosticsLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipDiagnosticsModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class DiagnosticsLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
