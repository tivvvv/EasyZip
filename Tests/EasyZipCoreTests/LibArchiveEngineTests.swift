import XCTest
@testable import EasyZipCore

final class LibArchiveEngineTests: XCTestCase {
    private let fileManager = FileManager.default
    private let fixtureModificationDate = Date(timeIntervalSince1970: 1_700_000_000)

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

    func testExtractRenamesConflictingFiles() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("rename.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let existingFileURL = outputURL.appendingPathComponent("source/hello.txt")
        let renamedFileURL = outputURL.appendingPathComponent("source/hello 2.txt")
        let engine = LibArchiveEngine()

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: .init(includeHiddenFiles: true)
            )
        )

        try fileManager.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "existing".write(to: existingFileURL, atomically: true, encoding: .utf8)

        try await engine.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(overwritePolicy: .rename)
            )
        )

        XCTAssertEqual(try String(contentsOf: existingFileURL, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: renamedFileURL, encoding: .utf8), "hello easyzip")
    }

    func testCreateReportsByteProgress() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("progress.zip")
        let recorder = ProgressRecorder()
        let expectedByteCount = try regularFileByteCount(in: sourceURL)
        let engine = LibArchiveEngine(bufferSize: 4)

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: .init(includeHiddenFiles: true)
            )
        ) { progress in
            recorder.append(progress)
        }

        let progressValues = recorder.values
        let finalProgress = try XCTUnwrap(progressValues.last)

        XCTAssertEqual(finalProgress.phase, .finishing)
        XCTAssertEqual(finalProgress.completedUnitCount, expectedByteCount)
        XCTAssertEqual(finalProgress.totalUnitCount, expectedByteCount)
        XCTAssertTrue(progressValues.contains { $0.completedUnitCount > 0 })
    }

    func testExtractReportsByteProgress() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("extract-progress.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let recorder = ProgressRecorder()
        let expectedByteCount = try regularFileByteCount(in: sourceURL)
        let engine = LibArchiveEngine(bufferSize: 4)

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: .init(includeHiddenFiles: true)
            )
        )

        try await engine.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(overwritePolicy: .overwrite)
            )
        ) { progress in
            recorder.append(progress)
        }

        let progressValues = recorder.values
        let finalProgress = try XCTUnwrap(progressValues.last)

        XCTAssertEqual(finalProgress.phase, .finishing)
        XCTAssertEqual(finalProgress.completedUnitCount, expectedByteCount)
        XCTAssertEqual(finalProgress.totalUnitCount, expectedByteCount)
        XCTAssertTrue(progressValues.contains { $0.completedUnitCount > 0 })
    }

    func testCreateHonorsCancellation() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("cancel.zip")
        let engine = LibArchiveEngine(bufferSize: 1)
        let task = Task {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: archiveURL,
                    format: .zip,
                    options: .init(includeHiddenFiles: true)
                )
            )
        }

        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            XCTAssertTrue(true)
        }
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
        XCTAssertTrue(entryPaths.containsDirectory("source/empty"))
        XCTAssertTrue(entryPaths.contains("source/中文 文件 #1.txt"))
        XCTAssertTrue(entryPaths.contains("source/nested/emoji-🙂.txt"))
        XCTAssertTrue(entryPaths.contains("source/link-to-hello.txt"))

        try await engine.extract(
            ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: outputURL,
                options: .init(overwritePolicy: .overwrite)
            )
        )

        let helloURL = outputURL.appendingPathComponent("source/hello.txt")
        let messageURL = outputURL.appendingPathComponent("source/nested/message.txt")
        let emptyDirectoryURL = outputURL.appendingPathComponent("source/empty", isDirectory: true)
        let chineseFileURL = outputURL.appendingPathComponent("source/中文 文件 #1.txt")
        let emojiFileURL = outputURL.appendingPathComponent("source/nested/emoji-🙂.txt")
        let symlinkURL = outputURL.appendingPathComponent("source/link-to-hello.txt")

        XCTAssertEqual(try String(contentsOf: helloURL, encoding: .utf8), "hello easyzip")
        XCTAssertEqual(try String(contentsOf: messageURL, encoding: .utf8), "nested content")
        XCTAssertEqual(try String(contentsOf: chineseFileURL, encoding: .utf8), "中文内容")
        XCTAssertEqual(try String(contentsOf: emojiFileURL, encoding: .utf8), "emoji content")
        XCTAssertTrue(isDirectory(emptyDirectoryURL))
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: symlinkURL.path), "hello.txt")
        try assertMetadata(for: helloURL)
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
        let emptyDirectoryURL = sourceURL.appendingPathComponent("empty", isDirectory: true)
        let helloURL = sourceURL.appendingPathComponent("hello.txt")

        try fileManager.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: emptyDirectoryURL, withIntermediateDirectories: true)
        try "hello easyzip".write(
            to: helloURL,
            atomically: true,
            encoding: .utf8
        )
        try "nested content".write(
            to: nestedURL.appendingPathComponent("message.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "中文内容".write(
            to: sourceURL.appendingPathComponent("中文 文件 #1.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "emoji content".write(
            to: nestedURL.appendingPathComponent("emoji-🙂.txt"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createSymbolicLink(
            atPath: sourceURL.appendingPathComponent("link-to-hello.txt").path,
            withDestinationPath: "hello.txt"
        )
        try fileManager.setAttributes(
            [
                .modificationDate: fixtureModificationDate,
                .posixPermissions: 0o640
            ],
            ofItemAtPath: helloURL.path
        )

        return sourceURL
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func assertMetadata(for fileURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        let modifiedAt = try XCTUnwrap(attributes[.modificationDate] as? Date)

        XCTAssertEqual(permissions.intValue & 0o777, 0o640)
        XCTAssertEqual(modifiedAt.timeIntervalSince1970, fixtureModificationDate.timeIntervalSince1970, accuracy: 1)
    }

    func regularFileByteCount(in directoryURL: URL) throws -> Int64 {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        return try childURLs.reduce(Int64(0)) { partialResult, childURL in
            let attributes = try fileManager.attributesOfItem(atPath: childURL.path)
            let fileType = attributes[.type] as? FileAttributeType

            if fileType == .typeDirectory {
                return try partialResult + regularFileByteCount(in: childURL)
            }

            if fileType == .typeRegular {
                let size = attributes[.size] as? NSNumber
                return partialResult + (size?.int64Value ?? 0)
            }

            return partialResult
        }
    }
}

private extension Set where Element == String {
    func containsDirectory(_ path: String) -> Bool {
        contains(path) || contains(path + "/")
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ArchiveProgress] = []

    var values: [ArchiveProgress] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storage
    }

    func append(_ progress: ArchiveProgress) {
        lock.lock()
        defer {
            lock.unlock()
        }

        storage.append(progress)
    }
}
