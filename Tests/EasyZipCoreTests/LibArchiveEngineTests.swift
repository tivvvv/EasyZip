import XCTest
@testable import EasyZipCore

final class LibArchiveEngineTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCreatesListsAndExtractsZipArchive() async throws {
        try await assertRoundTrip(format: .zip, archiveName: "sample.zip")
    }

    func testCreatesListsAndExtractsSevenZipArchive() async throws {
        try await assertRoundTrip(format: .sevenZip, archiveName: "sample.7z")
    }

    func testDefaultArchiveServiceUsesLibArchiveEngine() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("service.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let service = ArchiveService.makeDefault()

        try await service.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: .init(includeHiddenFiles: true)
            )
        )

        let entries = try await service.listEntries(in: archiveURL)

        XCTAssertTrue(entries.contains { $0.path == "source/hello.txt" })

        try await service.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(overwritePolicy: .overwrite)
            )
        )

        let extractedFileURL = outputURL.appendingPathComponent("source/hello.txt")
        XCTAssertEqual(try String(contentsOf: extractedFileURL, encoding: .utf8), "hello easyzip")
    }

    func testCreateSkipsHiddenFilesByDefault() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let hiddenDirectoryURL = sourceURL.appendingPathComponent(".cache", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("without-hidden.zip")
        let engine = LibArchiveEngine()

        try fileManager.createDirectory(at: hiddenDirectoryURL, withIntermediateDirectories: true)
        try "hidden file".write(
            to: sourceURL.appendingPathComponent(".hidden.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "hidden child".write(
            to: hiddenDirectoryURL.appendingPathComponent("child.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip
            )
        )

        let entryPaths = Set(try await engine.listEntries(in: archiveURL).map(\.path))

        XCTAssertFalse(entryPaths.contains("source/.hidden.txt"))
        XCTAssertFalse(entryPaths.contains("source/.cache/child.txt"))
        XCTAssertTrue(entryPaths.contains("source/hello.txt"))
    }
}

private extension LibArchiveEngineTests {
    func assertRoundTrip(format: ArchiveFormat, archiveName: String) async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent(archiveName)
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: format,
                options: .init(includeHiddenFiles: true)
            )
        )

        XCTAssertTrue(fileManager.fileExists(atPath: archiveURL.path))

        let entries = try await engine.listEntries(in: archiveURL)
        let entryPaths = Set(entries.map(\.path))

        XCTAssertTrue(entryPaths.containsDirectory("source"))
        XCTAssertTrue(entryPaths.contains("source/hello.txt"))
        XCTAssertTrue(entryPaths.containsDirectory("source/nested"))
        XCTAssertTrue(entryPaths.contains("source/nested/message.txt"))

        try await engine.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(overwritePolicy: .overwrite)
            )
        )

        let helloURL = outputURL.appendingPathComponent("source/hello.txt")
        let messageURL = outputURL.appendingPathComponent("source/nested/message.txt")

        XCTAssertEqual(try String(contentsOf: helloURL, encoding: .utf8), "hello easyzip")
        XCTAssertEqual(try String(contentsOf: messageURL, encoding: .utf8), "nested content")
    }

    func makeWorkspaceURL() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("EasyZipTests-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeFixtureSource(in workspaceURL: URL) throws -> URL {
        let sourceURL = workspaceURL.appendingPathComponent("source", isDirectory: true)
        let nestedURL = sourceURL.appendingPathComponent("nested", isDirectory: true)

        try fileManager.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "hello easyzip".write(
            to: sourceURL.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "nested content".write(
            to: nestedURL.appendingPathComponent("message.txt"),
            atomically: true,
            encoding: .utf8
        )

        return sourceURL
    }
}

private extension Set where Element == String {
    func containsDirectory(_ path: String) -> Bool {
        contains(path) || contains(path + "/")
    }
}
