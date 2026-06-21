import EasyZipCore
import XCTest
@testable import EasyZipApp

final class ArchivePreviewModelingTests: XCTestCase {
    func testSortsRowsBySizeWithUnknownValuesLastInAscendingOrder() {
        let rows = [
            makeRow(path: "unknown.bin", size: nil),
            makeRow(path: "small.bin", size: 1),
            makeRow(path: "large.bin", size: 10)
        ]

        let sortedRows = ArchivePreviewSorter.sortedRows(rows, field: .size, descending: false)

        XCTAssertEqual(sortedRows.map(\.path), [
            "small.bin",
            "large.bin",
            "unknown.bin"
        ])
    }

    func testSortsRowsByRiskAndUsesPathAsTieBreaker() {
        let rows = [
            makeRow(path: "safe-b.txt", kind: .file),
            makeRow(path: "risk-link", kind: .symbolicLink(target: "target")),
            makeRow(path: "safe-a.txt", kind: .file)
        ]

        let sortedRows = ArchivePreviewSorter.sortedRows(rows, field: .risk, descending: false)

        XCTAssertEqual(sortedRows.map(\.path), [
            "safe-a.txt",
            "safe-b.txt",
            "risk-link"
        ])
    }

    func testBuildsPreviewSummary() {
        let rows = [
            makeRow(path: "safe.txt", size: 2),
            makeRow(path: "link", kind: .symbolicLink(target: "target"), size: 1)
        ]

        let summary = ArchivePreviewSummary(rows: rows, visibleCount: 1)

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.visibleCount, 1)
        XCTAssertEqual(summary.riskCount, 1)
        XCTAssertFalse(summary.totalSizeText.isEmpty)
    }

    private func makeRow(
        path: String,
        kind: ArchiveEntryKind = .file,
        size: Int64? = nil,
        modifiedAt: Date? = nil
    ) -> ArchiveEntryRow {
        ArchiveEntryRow(
            entry: ArchiveEntry(
                path: path,
                kind: kind,
                uncompressedSize: size,
                modifiedAt: modifiedAt
            )
        )
    }
}
