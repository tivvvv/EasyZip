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

    func testRejectsBackslashAbsolutePath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "\\etc\\passwd")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("\\etc\\passwd"))
        }
    }

    func testRejectsWindowsDrivePath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "C:\\Users\\file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("C:\\Users\\file.txt"))
        }
    }

    func testRejectsBackslashTraversalPath() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "folder\\..\\outside.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder\\..\\outside.txt"))
        }
    }

    func testRejectsEmptyAndDotComponents() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "folder//file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder//file.txt"))
        }
        XCTAssertThrowsError(try validator.validatedDestination(for: "folder/./file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder/./file.txt"))
        }
    }

    func testRejectsNullByte() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "folder/\0file.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder/\0file.txt"))
        }
    }

    func testRejectsControlAndBidirectionalCharacters() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        XCTAssertThrowsError(try validator.validatedDestination(for: "folder/\nfile.txt")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder/\nfile.txt"))
        }
        XCTAssertThrowsError(try validator.validatedDestination(for: "folder/\u{202E}cod.exe")) { error in
            XCTAssertEqual(error as? ArchiveError, .unsafeEntryPath("folder/\u{202E}cod.exe"))
        }
    }

    func testAcceptsUnicodeNameWithoutUnsafeControlCharacters() throws {
        let validator = ArchivePathValidator(destinationURL: URL(fileURLWithPath: "/tmp/output"))

        let url = try validator.validatedDestination(for: "folder/e\u{301}.txt")

        XCTAssertEqual(url.path, "/tmp/output/folder/e\u{301}.txt")
    }
}
