import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelInputFilterTests: XCTestCase {
    func testExtractModeAddsSupportedArchivesAndReportsRejectedFiles() {
        let model = makeModel()
        let archiveURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/document.txt")

        model.mode = .extract
        model.addFileURLs([archiveURL, unsupportedURL])

        XCTAssertEqual(model.selectedItems.map(\.path), [archiveURL.standardizedFileURL.path])
        XCTAssertEqual(model.alert?.title, "已忽略不支持的文件")
        XCTAssertEqual(model.alert?.message, "已忽略 1 个不支持解压的文件")
    }

    func testExtractModeRejectsUnsupportedFilesWithoutChangingQueue() {
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([URL(fileURLWithPath: "/tmp/document.txt")])

        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertEqual(model.alert?.title, "没有可处理的文件")
        XCTAssertEqual(model.alert?.message, "请选择支持的归档文件后重试")
    }

    func testExternalSelectionReportsRejectedFilesBeforeDeferringRunningTask() {
        let model = makeModel()
        let archiveURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/document.txt")

        model.isRunning = true
        model.prepareExternalSelection(mode: .extract, fileURLs: [archiveURL, unsupportedURL])

        XCTAssertEqual(model.pendingExternalSelection?.mode, .extract)
        XCTAssertEqual(model.pendingExternalSelection?.fileURLs.map(\.path), [archiveURL.standardizedFileURL.path])
        XCTAssertEqual(model.alert?.title, "已暂存新选择")
        XCTAssertEqual(
            model.alert?.message,
            "当前任务完成后可应用 1 项解压文件, 已忽略 1 个不支持解压的文件"
        )
    }

    func testExternalExtractionSelectionUsesRequestedModeForWarnings() {
        let model = makeModel()
        let archiveURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/document.txt")

        model.mode = .compress
        model.prepareExternalSelection(mode: .extract, fileURLs: [archiveURL, unsupportedURL])

        XCTAssertEqual(model.mode, .extract)
        XCTAssertEqual(model.selectedItems.map(\.path), [archiveURL.standardizedFileURL.path])
        XCTAssertEqual(model.alert?.title, "已忽略不支持的文件")
        XCTAssertEqual(model.alert?.message, "已忽略 1 个不支持解压的文件")
    }

    func testExternalExtractionSelectionRejectsUnsupportedFilesUsingRequestedMode() {
        let model = makeModel()

        model.mode = .compress
        model.prepareExternalSelection(mode: .extract, fileURLs: [URL(fileURLWithPath: "/tmp/document.txt")])

        XCTAssertEqual(model.mode, .compress)
        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertEqual(model.alert?.title, "没有可处理的文件")
        XCTAssertEqual(model.alert?.message, "请选择支持的归档文件后重试")
    }

    private func makeModel() -> EasyZipAppModel {
        EasyZipAppModel(
            settings: EasyZipAppSettings(
                userDefaults: makeUserDefaults(),
                launchAtLoginController: InputFilterLaunchAtLoginController(isEnabled: false),
                notificationAuthorizationRequester: {}
            )
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelInputFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class InputFilterLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
