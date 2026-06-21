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
        XCTAssertEqual(model.item(with: .finderExtension)?.status, .unsupported)
        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .normal)
        XCTAssertEqual(model.item(with: .rarCommand)?.status, .normal)
        XCTAssertEqual(model.item(with: .zstdCommand)?.status, .normal)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.status, .normal)
        XCTAssertEqual(model.item(with: .codeSignature)?.status, .normal)
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
            codeSignatureStatus: .needsAction
        )

        await model.refresh()

        XCTAssertEqual(model.item(with: .appLocation)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .appLocation)?.action, .openApplications)
        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .notificationPermission)?.action, .openNotificationSettings)
        XCTAssertEqual(model.item(with: .rarCommand)?.status, .needsAction)
        XCTAssertNil(model.item(with: .rarCommand)?.action)
        XCTAssertEqual(model.item(with: .zstdCommand)?.status, .needsAction)
        XCTAssertNil(model.item(with: .zstdCommand)?.action)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .defaultOutputDirectory)?.action, .openSettings)
        XCTAssertEqual(model.item(with: .codeSignature)?.status, .needsAction)
    }

    func testRequestsNotificationPermissionWhenStatusIsNotDetermined() async {
        let model = makeModel(notificationStatus: .notDetermined)

        await model.refresh()

        XCTAssertEqual(model.item(with: .notificationPermission)?.status, .needsAction)
        XCTAssertEqual(model.item(with: .notificationPermission)?.action, .requestNotificationAuthorization)
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
        codeSignatureStatus: EasyZipDiagnosticStatus = .normal
    ) -> EasyZipDiagnosticsModel {
        EasyZipDiagnosticsModel(
            settings: settings ?? makeSettings(),
            bundleURL: bundleURL,
            notificationAuthorizationStatusProvider: { notificationStatus },
            rarAvailabilityProvider: { rarAvailability },
            zstdAvailabilityProvider: { zstdAvailability },
            codeSignatureStatusProvider: { _ in codeSignatureStatus }
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
