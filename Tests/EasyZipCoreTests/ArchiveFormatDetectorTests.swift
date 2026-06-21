import XCTest
import EasyZipTestSupport
@testable import EasyZipCore

final class ArchiveFormatDetectorTests: XCTestCase {
    private let fileManager = FileManager.default

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

    func testDetectsTarZstdByCompoundExtensionAndAlias() throws {
        let detector = DefaultArchiveFormatDetector()

        let compoundFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tar.zst"))
        let aliasFormat = try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.tzst"))

        XCTAssertEqual(compoundFormat, .tarZstd)
        XCTAssertEqual(aliasFormat, .tarZstd)
    }

    func testDetectsSingleFileCompressionByExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        XCTAssertEqual(try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.gz")), .gzip)
        XCTAssertEqual(try detector.detectFormat(for: URL(fileURLWithPath: "/tmp/example.xz")), .xz)
    }

    func testRemovesCompoundArchiveExtension() {
        let baseName = ArchiveFormat.removingArchiveExtension(from: "example.tar.gz")

        XCTAssertEqual(baseName, "example")
    }

    func testEncryptedCompressionSupportIsExplicit() {
        XCTAssertTrue(ArchiveFormat.zip.supportsEncryptedCompression)

        let unsupportedFormats = ArchiveFormat.allCases.filter { $0 != .zip }
        XCTAssertTrue(unsupportedFormats.allSatisfy { !$0.supportsEncryptedCompression })
    }

    func testThrowsForUnsupportedExtension() throws {
        let detector = DefaultArchiveFormatDetector()

        let archiveURL = URL(fileURLWithPath: "/tmp/example.iso")

        XCTAssertThrowsError(try detector.detectFormat(for: archiveURL)) { error in
            XCTAssertEqual(error as? ArchiveError, .unsupportedFormat("iso"))
        }
    }

    func testDetectsZipByMagicNumberBeforeExtension() throws {
        let archiveURL = try makeTemporaryFileURL(filename: "renamed.rar")
        defer {
            TemporaryWorkspace.remove(
                archiveURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
        }
        try Data([0x50, 0x4B, 0x03, 0x04, 0x00]).write(to: archiveURL)

        let format = try DefaultArchiveFormatDetector().detectFormat(for: archiveURL)

        XCTAssertEqual(format, .zip)
    }

    func testDetectsSevenZipAndRARByMagicNumber() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sevenZipURL = workspaceURL.appendingPathComponent("archive.data")
        let rarURL = workspaceURL.appendingPathComponent("archive.bin")

        try Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00]).write(to: sevenZipURL)
        try Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]).write(to: rarURL)

        let detector = DefaultArchiveFormatDetector()

        XCTAssertEqual(try detector.detectFormat(for: sevenZipURL), .sevenZip)
        XCTAssertEqual(try detector.detectFormat(for: rarURL), .rar)
    }

    func testDetectsTarByMagicNumber() throws {
        let archiveURL = try makeTemporaryFileURL(filename: "archive.data")
        defer {
            TemporaryWorkspace.remove(
                archiveURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
        }
        var bytes = [UInt8](repeating: 0, count: 512)
        bytes.replaceSubrange(257..<262, with: [0x75, 0x73, 0x74, 0x61, 0x72])
        try Data(bytes).write(to: archiveURL)

        let format = try DefaultArchiveFormatDetector().detectFormat(for: archiveURL)

        XCTAssertEqual(format, .tar)
    }

    func testDetectsCompressedTarFormatsByMagicNumber() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let zstdURL = workspaceURL.appendingPathComponent("archive.zstd-data")
        let gzipURL = workspaceURL.appendingPathComponent("archive.gz")
        let tarGzipURL = workspaceURL.appendingPathComponent("archive.tar.gz")
        let xzURL = workspaceURL.appendingPathComponent("archive.xz")
        let tarXzURL = workspaceURL.appendingPathComponent("archive.tar.xz")
        try Data([0x28, 0xB5, 0x2F, 0xFD, 0x00]).write(to: zstdURL)
        try Data([0x1F, 0x8B, 0x08, 0x00]).write(to: gzipURL)
        try Data([0x1F, 0x8B, 0x08, 0x00]).write(to: tarGzipURL)
        try Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]).write(to: xzURL)
        try Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]).write(to: tarXzURL)

        let detector = DefaultArchiveFormatDetector()

        XCTAssertEqual(try detector.detectFormat(for: zstdURL), .tarZstd)
        XCTAssertEqual(try detector.detectFormat(for: gzipURL), .gzip)
        XCTAssertEqual(try detector.detectFormat(for: tarGzipURL), .tarGzip)
        XCTAssertEqual(try detector.detectFormat(for: xzURL), .xz)
        XCTAssertEqual(try detector.detectFormat(for: tarXzURL), .tarXz)
    }

    private func makeTemporaryFileURL(filename: String) throws -> URL {
        try makeWorkspaceURL().appendingPathComponent(filename)
    }

    private func makeWorkspaceURL() throws -> URL {
        try TemporaryWorkspace.makeURL(prefix: "EasyZipFormatTests", fileManager: fileManager)
    }
}
