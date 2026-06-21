import XCTest
import EasyZipCore
@testable import EasyZipApp

final class ArchiveTaskRunnerTests: XCTestCase {
    private let fileManager = FileManager.default

    func testExtractWithoutContainingDirectoryRevealsBaseOutputDirectory() async throws {
        let workspaceURL = makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("source", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("sample.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try "hello".write(
            to: sourceURL.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await ArchiveService.makeDefault().create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip
            )
        )

        let result = try await ArchiveTaskRunner.extract(
            archiveURLs: [archiveURL],
            outputDirectory: outputURL,
            overwritePolicy: .overwrite,
            shouldCreateContainingDirectory: false,
            progressHandler: nil
        )

        XCTAssertEqual(result.outputURL?.path, outputURL.path)
        XCTAssertEqual(
            try String(
                contentsOf: outputURL.appendingPathComponent("source/hello.txt"),
                encoding: .utf8
            ),
            "hello"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: outputURL.appendingPathComponent("sample").path))
    }

    func testExtractSingleFileCompressionRevealsBaseOutputDirectory() async throws {
        let workspaceURL = makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("hello.txt")
        let archiveURL = workspaceURL.appendingPathComponent("hello.txt.gz")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)
        try await ArchiveService.makeDefault().create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .gzip
            )
        )

        let result = try await ArchiveTaskRunner.extract(
            archiveURLs: [archiveURL],
            outputDirectory: outputURL,
            overwritePolicy: .overwrite,
            shouldCreateContainingDirectory: true,
            progressHandler: nil
        )

        XCTAssertEqual(result.outputURL?.path, outputURL.path)
        XCTAssertEqual(
            try String(
                contentsOf: outputURL.appendingPathComponent("hello.txt"),
                encoding: .utf8
            ),
            "hello"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: outputURL.appendingPathComponent("hello.txt/hello.txt").path))
    }

    private func makeWorkspaceURL() -> URL {
        let workspaceURL = fileManager.temporaryDirectory.appendingPathComponent(
            "EasyZipTaskRunnerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try? fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }
}
