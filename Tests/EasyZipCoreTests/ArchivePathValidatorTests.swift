import XCTest
@testable import EasyZipCore

final class ArchivePathValidatorTests: XCTestCase {
    func testAcceptsSafeRelativePath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        let url = try validator.validatedDestination(for: "folder/file.txt")

        XCTAssertEqual(url.path, "/tmp/output/folder/file.txt")
    }

    func testRejectsParentTraversal() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "../file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("../file.txt"))
        }
    }

    func testRejectsAbsolutePath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "/etc/passwd")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("/etc/passwd"))
        }
    }

    func testRejectsWindowsDrivePath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "C:\\Users\\file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("C:\\Users\\file.txt"))
        }
    }
}
