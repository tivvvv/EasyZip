import EasyZipCore
import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelExternalToolTests: XCTestCase {
    func testReportsMissingZstdCommandForTarZstdCompression() {
        let model = makeModel(
            zstdCommandResolver: ZstdCommandResolver(
                executableURL: URL(fileURLWithPath: "/tmp/missing-zstd"),
                candidatePaths: [],
                pathValue: ""
            )
        )

        model.selectedFormat = .tarZstd

        let requirement = model.formatRequirementStatus
        XCTAssertEqual(requirement?.title, "需要安装 zstd 命令")
        XCTAssertEqual(requirement?.iconName, "exclamationmark.triangle")
        XCTAssertEqual(requirement?.isBlocking, true)
    }

    func testBlocksTarZstdCompressionWhenZstdCommandIsMissing() {
        let model = makeModel(
            zstdCommandResolver: ZstdCommandResolver(
                executableURL: URL(fileURLWithPath: "/tmp/missing-zstd"),
                candidatePaths: [],
                pathValue: ""
            )
        )

        model.selectedFormat = .tarZstd
        model.selectedItems = [URL(fileURLWithPath: "/tmp/source")]
        model.outputDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.startOperation()

        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.taskResult?.title, "TAR.ZST 压缩不可用")
        XCTAssertEqual(model.progressText, "等待外部工具")
        XCTAssertEqual(model.alert?.title, "TAR.ZST 压缩不可用")
    }

    private func makeModel(
        zstdCommandResolver: ZstdCommandResolver
    ) -> EasyZipAppModel {
        EasyZipAppModel(
            settings: EasyZipAppSettings(
                userDefaults: makeUserDefaults(),
                launchAtLoginController: ExternalToolLaunchAtLoginController(isEnabled: false),
                notificationAuthorizationRequester: {}
            ),
            zstdCommandResolver: zstdCommandResolver
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelExternalToolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class ExternalToolLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
