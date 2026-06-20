import XCTest
import EasyZipTestSupport
@testable import EasyZipCore

final class ArchiveFixtureTests: XCTestCase {
    private let fileManager = FileManager.default

    func testListsAndExtractsStoredArchiveFixtures() async throws {
        let fixtures: [(name: String, format: ArchiveFormat)] = [
            ("basic.zip", .zip),
            ("basic.7z", .sevenZip),
            ("basic.tar.gz", .tarGzip)
        ]
        let detector = DefaultArchiveFormatDetector()
        let engine = LibArchiveEngine()

        for fixture in fixtures {
            let archiveURL = try fixtureURL(named: fixture.name)
            let workspaceURL = try makeWorkspaceURL(prefix: "EasyZipStoredFixtureTests")
            defer {
                TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
            }

            XCTAssertEqual(try detector.detectFormat(for: archiveURL), fixture.format)

            let entries = try await engine.listEntries(in: archiveURL)
            let entryPaths = Set(entries.map(\.path))

            XCTAssertTrue(entryPaths.contains("source/hello.txt"))
            XCTAssertTrue(entryPaths.contains("source/nested/message.txt"))
            XCTAssertTrue(entryPaths.contains("source/中文.txt"))
            XCTAssertTrue(entryPaths.containsDirectory("source/empty"))

            let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: outputURL,
                    options: .init(
                        overwritePolicy: .overwrite,
                        shouldCreateContainingDirectory: false
                    )
                )
            )

            XCTAssertEqual(
                try String(
                    contentsOf: outputURL.appendingPathComponent("source/hello.txt"),
                    encoding: .utf8
                ),
                "hello fixture\n"
            )
            XCTAssertEqual(
                try String(
                    contentsOf: outputURL.appendingPathComponent("source/nested/message.txt"),
                    encoding: .utf8
                ),
                "nested fixture\n"
            )
            XCTAssertEqual(
                try String(
                    contentsOf: outputURL.appendingPathComponent("source/中文.txt"),
                    encoding: .utf8
                ),
                "unicode fixture\n"
            )
            XCTAssertTrue(
                isDirectory(outputURL.appendingPathComponent("source/empty", isDirectory: true))
            )
        }
    }

    func testExtractsEncryptedZipFixtureWithPassword() async throws {
        let archiveURL = try fixtureURL(named: "encrypted.zip")
        let workspaceURL = try makeWorkspaceURL(prefix: "EasyZipEncryptedFixtureTests")
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let engine = LibArchiveEngine()
        let entries = try await engine.listEntries(in: archiveURL)

        XCTAssertTrue(entries.contains { $0.path == "source/hello.txt" })

        do {
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: workspaceURL.appendingPathComponent("missing-password"),
                    options: .init(
                        overwritePolicy: .overwrite,
                        shouldCreateContainingDirectory: false
                    )
                )
            )
            XCTFail("Expected encrypted archive error.")
        } catch ArchiveError.encryptedArchive(let url) {
            XCTAssertEqual(url, archiveURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: workspaceURL.appendingPathComponent("wrong-password"),
                    options: .init(
                        overwritePolicy: .overwrite,
                        shouldCreateContainingDirectory: false,
                        password: "wrong-password"
                    )
                )
            )
            XCTFail("Expected incorrect password error.")
        } catch ArchiveError.incorrectArchivePassword(let url) {
            XCTAssertEqual(url, archiveURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try await engine.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(
                    overwritePolicy: .overwrite,
                    shouldCreateContainingDirectory: false,
                    password: "easyzip-secret"
                )
            )
        )

        XCTAssertEqual(
            try String(
                contentsOf: outputURL.appendingPathComponent("source/hello.txt"),
                encoding: .utf8
            ),
            "hello fixture\n"
        )
    }

    func testRejectsUnsafeTraversalFixture() async throws {
        let archiveURL = try fixtureURL(named: "unsafe-traversal.zip")
        let workspaceURL = try makeWorkspaceURL(prefix: "EasyZipUnsafeFixtureTests")
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()
        let entries = try await engine.listEntries(in: archiveURL)

        XCTAssertTrue(entries.contains { $0.path == "../escape.txt" })

        do {
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: outputURL,
                    options: .init(
                        overwritePolicy: .overwrite,
                        shouldCreateContainingDirectory: false
                    )
                )
            )
            XCTFail("Expected unsafe entry path error.")
        } catch ArchiveError.unsafeEntryPath(let path) {
            XCTAssertEqual(path, "../escape.txt")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(
            fileManager.fileExists(
                atPath: workspaceURL.appendingPathComponent("escape.txt").path
            )
        )
    }

    func testRejectsBrokenZipFixture() async throws {
        let archiveURL = try fixtureURL(named: "broken.zip")
        let engine = LibArchiveEngine()

        do {
            _ = try await engine.listEntries(in: archiveURL)
            XCTFail("Expected broken archive error.")
        } catch ArchiveError.engineFailure(let engineName, let message) {
            XCTAssertEqual(engineName, "libarchive")
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func fixtureURL(named name: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Fixtures/Archives"
        ) else {
            throw FixtureError.missingFixture(name)
        }

        return url
    }

    private func makeWorkspaceURL(prefix: String) throws -> URL {
        try TemporaryWorkspace.makeURL(prefix: prefix, fileManager: fileManager)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

private enum FixtureError: Error {
    case missingFixture(String)
}

private extension Set where Element == String {
    func containsDirectory(_ path: String) -> Bool {
        contains(path) || contains(path + "/")
    }
}
