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

    func testDetectsRARByExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let format = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.RAR"))

        XCTAssertEqual(format, .rar)
    }

    func testDetectsTarByExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let format = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tar"))

        XCTAssertEqual(format, .tar)
    }

    func testDetectsTarGzipByCompoundExtensionAndAlias() throws {
        let detector = DefaultArchiveFormatDetector()

        let compoundFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.TAR.GZ"))
        let aliasFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tgz"))

        XCTAssertEqual(compoundFormat, .tarGzip)
        XCTAssertEqual(aliasFormat, .tarGzip)
    }

    func testDetectsTarBzip2ByCompoundExtensionAndAlias() throws {
        let detector = DefaultArchiveFormatDetector()

        let compoundFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tar.bz2"))
        let aliasFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tbz2"))

        XCTAssertEqual(compoundFormat, .tarBzip2)
        XCTAssertEqual(aliasFormat, .tarBzip2)
    }

    func testDetectsTarXzByCompoundExtensionAndAlias() throws {
        let detector = DefaultArchiveFormatDetector()

        let compoundFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tar.xz"))
        let aliasFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.txz"))

        XCTAssertEqual(compoundFormat, .tarXz)
        XCTAssertEqual(aliasFormat, .tarXz)
    }

    func testRemovesCompoundArchiveExtension() {
        let baseName = ArchiveFormat.removingArchiveExtension(from: "example.tar.gz")

        XCTAssertEqual(baseName, "example")
    }

    func testThrowsForUnsupportedExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let archiveURL = URL(fileURLWithPath: "/tmp/example.iso")

        XCTAssertThrowsError(try detector.detectFormat(for: archiveURL)) { error in
            XCTAssertEqual(error as? ArchiveError, .unsupportedFormat("iso"))
        }
    }
}
