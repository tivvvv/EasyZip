import XCTest
@testable import EasyZipCore

final class ArchiveFormatDetectorTests: XCTestCase {
    func testDetectsZipByExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let format = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.ZIP"))

        XCTAssertEqual(format, .zip)
    }

    func testDetectsSevenZipByExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let format = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.7z"))

        XCTAssertEqual(format, .sevenZip)
    }

    func testThrowsForUnsupportedExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let archiveURL = URL(fileURLWithPath: "/tmp/example.rar")

        XCTAssertThrowsError(try detector.detectFormat(for: archiveURL)) { error in
            XCTAssertEqual(error as? ArchiveError, .unsupportedFormat("rar"))
        }
    }
}
