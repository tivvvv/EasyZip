import EasyZipCore
import XCTest
@testable import EasyZipApp

final class ArchiveEntryRowTests: XCTestCase {
    func testBuildsDisplayFieldsFromNestedEntry() {
        let entry = ArchiveEntry(
            path: "folder/nested/file.txt",
            kind: .file,
            uncompressedSize: 128,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let row = ArchiveEntryRow(entry: entry)

        XCTAssertEqual(row.name, "file.txt")
        XCTAssertEqual(row.parentPath, "folder/nested")
        XCTAssertEqual(row.depth, 2)
        XCTAssertEqual(row.kindTitle, "文件")
        XCTAssertEqual(row.uncompressedSize, 128)
        XCTAssertNil(row.risk)
        XCTAssertTrue(row.matches("nested"))
        XCTAssertTrue(row.matches("文件"))
        XCTAssertFalse(row.matches("missing"))
    }

    func testMarksSymbolicLinkAsRiskyPreviewEntry() {
        let entry = ArchiveEntry(
            path: "folder/link",
            kind: .symbolicLink(target: "../target")
        )

        let row = ArchiveEntryRow(entry: entry)

        XCTAssertEqual(row.kindTitle, "符号链接")
        XCTAssertEqual(row.linkTarget, "../target")
        XCTAssertEqual(row.risk?.title, "链接")
        XCTAssertEqual(row.risk?.sortOrder, 1)
        XCTAssertTrue(row.matches("../target"))
    }

    func testMarksHardLinkAndOtherEntriesAsHighRisk() {
        let hardLinkRow = ArchiveEntryRow(
            entry: ArchiveEntry(path: "hard", kind: .hardLink(target: "file"))
        )
        let otherRow = ArchiveEntryRow(entry: ArchiveEntry(path: "device", kind: .other))

        XCTAssertEqual(hardLinkRow.risk?.title, "高风险")
        XCTAssertEqual(hardLinkRow.risk?.sortOrder, 2)
        XCTAssertEqual(otherRow.risk?.title, "高风险")
        XCTAssertEqual(otherRow.risk?.sortOrder, 3)
    }
}
