import XCTest
@testable import EasyZipShared

final class FileURLListNormalizerTests: XCTestCase {
    func testKeepsFirstUniqueStandardizedFileURL() {
        let firstURL = URL(fileURLWithPath: "/tmp/example.txt")
        let duplicateURL = URL(fileURLWithPath: "/tmp/folder/../example.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")

        let normalizedURLs = FileURLListNormalizer.uniqueStandardizedFileURLs([
            firstURL,
            duplicateURL,
            secondURL
        ])

        XCTAssertEqual(normalizedURLs.map(\.path), [
            firstURL.standardizedFileURL.path,
            secondURL.standardizedFileURL.path
        ])
    }

    func testReturnsEmptyListForEmptyInput() {
        XCTAssertEqual(FileURLListNormalizer.uniqueStandardizedFileURLs([]), [])
    }
}
