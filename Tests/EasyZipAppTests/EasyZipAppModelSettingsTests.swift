import XCTest
import EasyZipCore
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelSettingsTests: XCTestCase {
    func testInitializesWithEffectiveDefaultOutputDirectory() {
        let settings = makeSettings()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyZipTests-\(UUID().uuidString)", isDirectory: true)

        settings.defaultOutputDirectory = missingURL

        let model = EasyZipAppModel(settings: settings)

        XCTAssertNil(model.outputDirectory)
    }

    func testAppliesSettingsChangesToWorkspace() async throws {
        let settings = makeSettings()
        let model = EasyZipAppModel(settings: settings)
        let outputURL = try makeTemporaryDirectory()

        settings.defaultOutputDirectory = outputURL
        settings.defaultCompressionFormat = .tarGzip
        settings.defaultOverwritePolicy = .skip
        settings.shouldCreateContainingDirectory = false
        await waitForSettingsUpdate()

        XCTAssertEqual(model.outputDirectory?.path, outputURL.path)
        XCTAssertEqual(model.selectedFormat, .tarGzip)
        XCTAssertEqual(model.overwritePolicy, .skip)
        XCTAssertFalse(model.shouldCreateContainingDirectory)
        XCTAssertEqual(model.taskResult?.title, "设置已应用")
        XCTAssertEqual(model.progressText, "设置已应用")
    }

    private func makeSettings() -> EasyZipAppSettings {
        EasyZipAppSettings(
            userDefaults: makeUserDefaults(),
            launchAtLoginController: ModelSettingsLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyZipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForSettingsUpdate() async {
        await Task.yield()
        await Task.yield()
    }
}

@MainActor
private final class ModelSettingsLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
