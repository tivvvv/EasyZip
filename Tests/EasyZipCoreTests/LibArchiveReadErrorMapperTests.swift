import XCTest
@testable import EasyZipCore

final class LibArchiveReadErrorMapperTests: XCTestCase {
    func testMapsMissingPasswordMessageToEncryptedArchiveError() {
        let archiveURL = URL(fileURLWithPath: "/tmp/encrypted.zip")
        let error = LibArchiveReadErrorMapper.map(
            archiveURL: archiveURL,
            message: "Passphrase required for this entry",
            engine: "libarchive",
            operation: "read header"
        )

        XCTAssertEqual(error, .encryptedArchive(archiveURL))
    }

    func testMapsIncorrectPasswordMessageToIncorrectPasswordError() {
        let archiveURL = URL(fileURLWithPath: "/tmp/encrypted.zip")
        let error = LibArchiveReadErrorMapper.map(
            archiveURL: archiveURL,
            message: "Incorrect passphrase",
            engine: "libarchive",
            operation: "read file data"
        )

        XCTAssertEqual(error, .incorrectArchivePassword(archiveURL))
    }

    func testKeepsRegularReadFailureAsEngineFailure() {
        let archiveURL = URL(fileURLWithPath: "/tmp/broken.zip")
        let error = LibArchiveReadErrorMapper.map(
            archiveURL: archiveURL,
            message: "Truncated archive",
            engine: "libarchive",
            operation: "read header"
        )

        XCTAssertEqual(
            error,
            .engineFailure(engine: "libarchive", message: "read header: Truncated archive")
        )
    }
}
