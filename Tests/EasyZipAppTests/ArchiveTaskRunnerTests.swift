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

    func testSelectedEntryExtractionAvoidsDuplicatedContainingDirectory() async throws {
        let workspaceURL = makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("用户资料", isDirectory: true)
        let nestedURL = sourceURL.appendingPathComponent("子目录", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("用户资料.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "中文内容".write(
            to: nestedURL.appendingPathComponent("中文 文件.txt"),
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
            shouldCreateContainingDirectory: true,
            selectedEntryPaths: ["用户资料/子目录/中文 文件.txt"],
            progressHandler: nil
        )

        let extractedURL = outputURL.appendingPathComponent("用户资料/子目录/中文 文件.txt")
        let duplicatedURL = outputURL.appendingPathComponent("用户资料/用户资料/子目录/中文 文件.txt")
        XCTAssertEqual(result.outputURL?.path, outputURL.appendingPathComponent("用户资料").path)
        XCTAssertEqual(try String(contentsOf: extractedURL, encoding: .utf8), "中文内容")
        XCTAssertFalse(fileManager.fileExists(atPath: duplicatedURL.path))
    }

    func testSelectedEntryExtractionRevealsExistingTopLevelDirectoryWithoutContainingOption() async throws {
        let workspaceURL = makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("用户资料", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("用户资料.zip")
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
            selectedEntryPaths: ["用户资料/hello.txt"],
            progressHandler: nil
        )

        let extractedURL = outputURL.appendingPathComponent("用户资料/hello.txt")
        XCTAssertEqual(result.outputURL?.path, outputURL.appendingPathComponent("用户资料").path)
        XCTAssertEqual(try String(contentsOf: extractedURL, encoding: .utf8), "hello")
    }

    func testExtractAskPolicyUsesConflictResolverDecision() async throws {
        let workspaceURL = makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("source", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("sample.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let existingFileURL = outputURL.appendingPathComponent("source/hello.txt")
        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "new".write(
            to: sourceURL.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "old".write(to: existingFileURL, atomically: true, encoding: .utf8)
        try await ArchiveService.makeDefault().create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip
            )
        )

        let conflictCapture = ConflictCapture()
        _ = try await ArchiveTaskRunner.extract(
            archiveURLs: [archiveURL],
            outputDirectory: outputURL,
            overwritePolicy: .ask,
            shouldCreateContainingDirectory: false,
            conflictResolver: { conflict in
                conflictCapture.store(conflict)
                return .skip
            },
            progressHandler: nil
        )

        let resolvedConflict = conflictCapture.value
        XCTAssertEqual(resolvedConflict?.entryPath, "source/hello.txt")
        XCTAssertEqual(resolvedConflict?.destinationURL.path, existingFileURL.path)
        XCTAssertEqual(try String(contentsOf: existingFileURL, encoding: .utf8), "old")
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

private final class ConflictCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedConflict: ArchiveConflict?

    var value: ArchiveConflict? {
        lock.lock()
        let conflict = storedConflict
        lock.unlock()
        return conflict
    }

    func store(_ conflict: ArchiveConflict) {
        lock.lock()
        storedConflict = conflict
        lock.unlock()
    }
}
