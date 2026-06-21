import EasyZipCore
import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelPreviewSelectionTests: XCTestCase {
    func testReplacesSelectionWithSelectableRowsOnly() {
        let model = makeModel()
        let rows = makeRows()

        model.archiveEntries = rows
        model.replaceArchiveEntrySelection(with: rows)

        XCTAssertEqual(
            model.selectedArchiveEntryPaths,
            ["folder", "folder/file.txt", "folder/link"]
        )
    }

    func testInvertsVisibleSelectableRows() {
        let model = makeModel()
        let rows = makeRows()

        model.archiveEntries = rows
        model.replaceArchiveEntrySelection(with: [rows[1]])
        model.invertArchiveEntrySelection(in: rows)

        XCTAssertEqual(
            model.selectedArchiveEntryPaths,
            ["folder", "folder/link"]
        )
    }

    func testSelectionShortcutsFilterVisibleRows() {
        let model = makeModel()
        let rows = makeRows()

        model.archiveEntries = rows

        model.replaceArchiveEntrySelectionWithFiles(in: rows)
        XCTAssertEqual(model.selectedArchiveEntryPaths, ["folder/file.txt"])

        model.replaceArchiveEntrySelectionWithDirectories(in: rows)
        XCTAssertEqual(model.selectedArchiveEntryPaths, ["folder"])

        model.replaceArchiveEntrySelectionWithRiskEntries(in: rows)
        XCTAssertEqual(model.selectedArchiveEntryPaths, ["folder/link"])
    }

    private func makeRows() -> [ArchiveEntryRow] {
        [
            ArchiveEntryRow(entry: ArchiveEntry(path: "folder", kind: .directory)),
            ArchiveEntryRow(entry: ArchiveEntry(path: "folder/file.txt", kind: .file)),
            ArchiveEntryRow(entry: ArchiveEntry(path: "folder/link", kind: .symbolicLink(target: "file.txt"))),
            ArchiveEntryRow(entry: ArchiveEntry(path: "folder/hard", kind: .hardLink(target: "file.txt"))),
            ArchiveEntryRow(entry: ArchiveEntry(path: "folder/device", kind: .other))
        ]
    }

    private func makeModel() -> EasyZipAppModel {
        EasyZipAppModel(
            settings: EasyZipAppSettings(
                userDefaults: makeUserDefaults(),
                launchAtLoginController: PreviewSelectionLaunchAtLoginController(isEnabled: false),
                notificationAuthorizationRequester: {}
            )
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelPreviewSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class PreviewSelectionLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
