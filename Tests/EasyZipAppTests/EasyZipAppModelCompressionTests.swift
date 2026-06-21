import EasyZipCore
import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelCompressionTests: XCTestCase {
    func testSingleFileCompressionKeepsSourceExtensionInDefaultArchiveName() {
        let model = makeModel()

        model.addFileURLs([URL(fileURLWithPath: "/tmp/hello.txt")])
        XCTAssertEqual(model.archiveName, "hello")

        model.selectedFormat = .gzip

        XCTAssertEqual(model.archiveName, "hello.txt")
        XCTAssertEqual(model.archiveFileNamePreview, "hello.txt.gz")
    }

    func testFormatChangeKeepsCustomArchiveName() {
        let model = makeModel()

        model.addFileURLs([URL(fileURLWithPath: "/tmp/hello.txt")])
        model.archiveName = "custom-name"
        model.selectedFormat = .gzip

        XCTAssertEqual(model.archiveName, "custom-name")
    }

    private func makeModel() -> EasyZipAppModel {
        EasyZipAppModel(
            settings: EasyZipAppSettings(
                userDefaults: makeUserDefaults(),
                launchAtLoginController: CompressionLaunchAtLoginController(isEnabled: false),
                notificationAuthorizationRequester: {}
            )
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelCompressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class CompressionLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
