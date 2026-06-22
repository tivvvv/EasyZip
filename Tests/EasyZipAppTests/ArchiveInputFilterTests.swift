import XCTest
@testable import EasyZipApp

final class ArchiveInputFilterTests: XCTestCase {
    func testAcceptsEveryFileForCompression() {
        let urls = [
            URL(fileURLWithPath: "/tmp/document.txt"),
            URL(fileURLWithPath: "/tmp/archive.zip")
        ]

        let result = ArchiveInputFilter.filter(urls, for: .compress)

        XCTAssertEqual(result.acceptedFileURLs, urls)
        XCTAssertTrue(result.rejectedFileURLs.isEmpty)
    }

    func testAcceptsSupportedArchivesForExtraction() {
        let archiveURL = URL(fileURLWithPath: "/tmp/archive.TAR.GZ")
        let unsupportedURL = URL(fileURLWithPath: "/tmp/document.txt")

        let result = ArchiveInputFilter.filter([archiveURL, unsupportedURL], for: .extract)

        XCTAssertEqual(result.acceptedFileURLs, [archiveURL])
        XCTAssertEqual(result.rejectedFileURLs, [unsupportedURL])
        XCTAssertEqual(result.rejectedCount, 1)
    }
}
