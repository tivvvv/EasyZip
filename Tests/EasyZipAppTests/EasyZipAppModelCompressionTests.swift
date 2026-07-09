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

    func testCompressionRequiresExplicitOutputDirectory() {
        let model = makeModel()

        model.addFileURLs([URL(fileURLWithPath: "/tmp/hello.txt")])
        model.startOperation()

        XCTAssertTrue(model.taskQueue.isEmpty)
        XCTAssertEqual(model.taskResult?.title, "请选择输出目录")
        XCTAssertEqual(model.progressText, "等待输出目录")
        XCTAssertEqual(model.alert?.message, "压缩前请先选择一个可写入的输出目录")
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
