import XCTest
@testable import EasyZipShared

final class ArchiveFileNameMatcherTests: XCTestCase {
    func testMatchesSupportedArchiveFilenames() {
        let filenames = [
            "sample.zip",
            "sample.7z",
            "sample.rar",
            "sample.tar",
            "sample.tar.gz",
            "sample.tgz",
            "sample.tar.bz2",
            "sample.tbz2",
            "sample.tbz",
            "sample.tar.xz",
            "sample.txz",
            "sample.tar.zst",
            "sample.tzst",
            "sample.gz",
            "sample.xz"
        ]

        XCTAssertTrue(filenames.allSatisfy(ArchiveFileNameMatcher.isSupportedArchiveFilename))
    }

    func testMatchesCaseInsensitiveArchiveFilename() {
        XCTAssertTrue(ArchiveFileNameMatcher.isSupportedArchiveFilename("SAMPLE.TAR.GZ"))
    }

    func testRejectsUnsupportedArchiveFilename() {
        XCTAssertFalse(ArchiveFileNameMatcher.isSupportedArchiveFilename("sample.iso"))
    }
}
