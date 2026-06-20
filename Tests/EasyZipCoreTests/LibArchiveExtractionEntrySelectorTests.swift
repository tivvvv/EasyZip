import XCTest
@testable import EasyZipCore

final class LibArchiveExtractionEntrySelectorTests: XCTestCase {
    func testEmptySelectionExtractsEveryEntry() {
        let selector = LibArchiveExtractionEntrySelector(selectedPaths: [])

        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder/file.txt",
                fileType: LibArchiveFileType.regular
            )
        )
        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder",
                fileType: LibArchiveFileType.directory
            )
        )
    }

    func testExtractsExactSelectedFile() {
        let selector = LibArchiveExtractionEntrySelector(selectedPaths: ["folder/file.txt"])

        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder/file.txt",
                fileType: LibArchiveFileType.regular
            )
        )
        XCTAssertFalse(
            selector.shouldExtract(
                entryPath: "folder/other.txt",
                fileType: LibArchiveFileType.regular
            )
        )
    }

    func testExtractsSelectedDirectorySubtreeAndAncestorDirectory() {
        let selector = LibArchiveExtractionEntrySelector(selectedPaths: ["folder/nested"])

        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder",
                fileType: LibArchiveFileType.directory
            )
        )
        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder/nested",
                fileType: LibArchiveFileType.directory
            )
        )
        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "folder/nested/file.txt",
                fileType: LibArchiveFileType.regular
            )
        )
        XCTAssertFalse(
            selector.shouldExtract(
                entryPath: "folder/other.txt",
                fileType: LibArchiveFileType.regular
            )
        )
    }

    func testNormalizesSlashesInSelectedPathsAndEntryPaths() {
        let selector = LibArchiveExtractionEntrySelector(selectedPaths: ["/folder\\nested/"])

        XCTAssertTrue(
            selector.shouldExtract(
                entryPath: "\\folder/nested/file.txt",
                fileType: LibArchiveFileType.regular
            )
        )
    }
}
