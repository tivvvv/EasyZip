import XCTest
import EasyZipCore
@testable import EasyZipApp

@MainActor
final class EasyZipAppSettingsTests: XCTestCase {
    func testLoadsDefaultValuesWhenStorageIsEmpty() {
        let defaults = makeUserDefaults()
        let launchAtLoginController = StubLaunchAtLoginController(isEnabled: false)
        let settings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: launchAtLoginController,
            notificationAuthorizationRequester: {}
        )

        XCTAssertNil(settings.defaultOutputDirectory)
        XCTAssertEqual(settings.defaultCompressionFormat, .zip)
        XCTAssertEqual(settings.defaultOverwritePolicy, .rename)
        XCTAssertTrue(settings.taskCompletionNotificationEnabled)
        XCTAssertTrue(settings.shouldCreateContainingDirectory)
        XCTAssertFalse(settings.launchAtLoginEnabled)
    }

    func testPersistsTaskDefaults() {
        let defaults = makeUserDefaults()
        let outputURL = URL(fileURLWithPath: "/tmp/easyzip-output", isDirectory: true)
        var authorizationRequestCount = 0
        let settings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: StubLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {
                authorizationRequestCount += 1
            }
        )

        settings.defaultOutputDirectory = outputURL
        settings.defaultCompressionFormat = .sevenZip
        settings.defaultOverwritePolicy = .skip
        settings.taskCompletionNotificationEnabled = false
        settings.taskCompletionNotificationEnabled = true
        settings.shouldCreateContainingDirectory = false

        let reloadedSettings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: StubLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )

        XCTAssertEqual(reloadedSettings.defaultOutputDirectory?.path, outputURL.path)
        XCTAssertEqual(reloadedSettings.defaultCompressionFormat, .sevenZip)
        XCTAssertEqual(reloadedSettings.defaultOverwritePolicy, .skip)
        XCTAssertTrue(reloadedSettings.taskCompletionNotificationEnabled)
        XCTAssertFalse(reloadedSettings.shouldCreateContainingDirectory)
        XCTAssertEqual(authorizationRequestCount, 1)
    }

    func testClearsDefaultOutputDirectory() {
        let defaults = makeUserDefaults()
        let settings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: StubLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )

        settings.defaultOutputDirectory = URL(fileURLWithPath: "/tmp/easyzip-output", isDirectory: true)
        settings.defaultOutputDirectory = nil

        let reloadedSettings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: StubLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )

        XCTAssertNil(reloadedSettings.defaultOutputDirectory)
    }

    func testUpdatesLaunchAtLoginStatusThroughController() {
        let defaults = makeUserDefaults()
        let launchAtLoginController = StubLaunchAtLoginController(isEnabled: false)
        let settings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: launchAtLoginController,
            notificationAuthorizationRequester: {}
        )

        settings.setLaunchAtLoginEnabled(true)
        XCTAssertTrue(settings.launchAtLoginEnabled)
        XCTAssertNil(settings.launchAtLoginErrorMessage)

        settings.setLaunchAtLoginEnabled(false)
        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertNil(settings.launchAtLoginErrorMessage)
    }

    func testKeepsLaunchAtLoginStatusWhenControllerFails() {
        let defaults = makeUserDefaults()
        let launchAtLoginController = StubLaunchAtLoginController(isEnabled: false)
        launchAtLoginController.shouldThrow = true
        let settings = EasyZipAppSettings(
            userDefaults: defaults,
            launchAtLoginController: launchAtLoginController,
            notificationAuthorizationRequester: {}
        )

        settings.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(settings.launchAtLoginErrorMessage, "开机启动设置失败")
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class StubLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    var shouldThrow = false

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if shouldThrow {
            throw StubError.failure
        }

        self.isEnabled = isEnabled
    }
}

private enum StubError: Error {
    case failure
}
