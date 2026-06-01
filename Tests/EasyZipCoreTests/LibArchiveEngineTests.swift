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

    func testCreatesListsAndExtractsTarArchive() async throws {
        try await assertRoundTrip(format: .tar, archiveName: "sample.tar")
    }

    func testCreatesListsAndExtractsTarGzipArchive() async throws {
        try await assertRoundTrip(format: .tarGzip, archiveName: "sample.tar.gz")
    }

    func testCreatesListsAndExtractsTarBzip2Archive() async throws {
        try await assertRoundTrip(format: .tarBzip2, archiveName: "sample.tar.bz2")
    }

    func testCreatesListsAndExtractsTarXzArchive() async throws {
        try await assertRoundTrip(format: .tarXz, archiveName: "sample.tar.xz")
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
                options: .init(
                    overwritePolicy: .overwrite,
                    shouldCreateContainingDirectory: false
                )
            )
        )

        let extractedFileURL = outputURL.appendingPathComponent("source/hello.txt")
        XCTAssertEqual(try String(contentsOf: extractedFileURL, encoding: .utf8), "hello easyzip")
    }

    func testLibArchiveSupportsRARReadingButNotWriting() {
        let engine = LibArchiveEngine()

        XCTAssertTrue(engine.canHandle(format: .rar, operation: .list))
        XCTAssertTrue(engine.canHandle(format: .rar, operation: .extract))
        XCTAssertFalse(engine.canHandle(format: .rar, operation: .create))
    }

    func testRARCompressionReportsMissingToolWhenUnavailable() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("sample.rar")
        let missingToolURL = workspaceURL.appendingPathComponent("missing-rar")
        let engine = RARCommandCompressionEngine(executableURL: missingToolURL)

        do {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: archiveURL,
                    format: .rar
                )
            )
            XCTFail("Expected missing external tool error.")
        } catch ArchiveError.externalToolUnavailable(let toolName) {
            XCTAssertEqual(toolName, "rar")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRARCompressionCancelsRunningExternalProcess() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("sample.rar")
        let startedURL = workspaceURL.appendingPathComponent("rar-started")
        let executableURL = workspaceURL.appendingPathComponent("rar")
        let script = """
        #!/bin/sh
        touch "\(startedURL.path)"
        exec /bin/sleep 5
        """

        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let engine = RARCommandCompressionEngine(executableURL: executableURL)
        let task = Task {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: archiveURL,
                    format: .rar
                )
            )
        }

        for _ in 0..<100 where !fileManager.fileExists(atPath: startedURL.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(fileManager.fileExists(atPath: startedURL.path))

        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            XCTAssertFalse(fileManager.fileExists(atPath: archiveURL.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    func testCreateAcceptsCompressionLevelOptions() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let engine = LibArchiveEngine()
        let cases: [(ArchiveFormat, String, CompressionLevel)] = [
            (.zip, "zip-fastest.zip", .fastest),
            (.zip, "zip-maximum.zip", .maximum),
            (.zip, "zip-custom.zip", .custom(42)),
            (.sevenZip, "sevenzip-fastest.7z", .fastest),
            (.sevenZip, "sevenzip-maximum.7z", .maximum),
            (.tarGzip, "gzip-fastest.tar.gz", .fastest),
            (.tarBzip2, "bzip2-maximum.tar.bz2", .maximum),
            (.tarXz, "xz-custom.tar.xz", .custom(9))
        ]

        for (format, archiveName, level) in cases {
            let archiveURL = workspaceURL.appendingPathComponent(archiveName)

            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: archiveURL,
                    format: format,
                    options: .init(compressionLevel: level, includeHiddenFiles: true)
                )
            )

            let entryPaths = Set(try await engine.listEntries(in: archiveURL).map(\.path))

            XCTAssertTrue(entryPaths.contains("source/hello.txt"))
        }
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
                options: .init(
                    overwritePolicy: .rename,
                    shouldCreateContainingDirectory: false
                )
            )
        )

        XCTAssertEqual(try String(contentsOf: existingFileURL, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: renamedFileURL, encoding: .utf8), "hello easyzip")
    }

    func testExtractCreatesContainingDirectoryWhenRequested() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("containing.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

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
        )

        let extractedFileURL = outputURL.appendingPathComponent("containing/source/hello.txt")

        XCTAssertEqual(try String(contentsOf: extractedFileURL, encoding: .utf8), "hello easyzip")
    }

    func testAskConflictRequiresResolver() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("ask.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let existingFileURL = outputURL.appendingPathComponent("source/hello.txt")
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

        do {
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: outputURL,
                    options: .init(
                        overwritePolicy: .ask,
                        shouldCreateContainingDirectory: false
                    )
                )
            )
            XCTFail("Expected conflict decision error.")
        } catch ArchiveError.conflictRequiresDecision(let url) {
            XCTAssertEqual(url.path, existingFileURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAskConflictUsesResolverDecision() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("ask-resolver.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let existingFileURL = outputURL.appendingPathComponent("source/hello.txt")
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
                options: .init(
                    overwritePolicy: .ask,
                    shouldCreateContainingDirectory: false,
                    conflictResolver: { conflict in
                        XCTAssertEqual(conflict.entryPath, "source/hello.txt")
                        XCTAssertEqual(conflict.destinationURL.path, existingFileURL.path)
                        return .rename
                    }
                )
            )
        )

        XCTAssertEqual(try String(contentsOf: existingFileURL, encoding: .utf8), "existing")
        XCTAssertEqual(
            try String(
                contentsOf: outputURL.appendingPathComponent("source/hello 2.txt"),
                encoding: .utf8
            ),
            "hello easyzip"
        )
    }

    func testCreateRejectsDestinationMatchingSource() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = workspaceURL.appendingPathComponent("source.zip")
        try "keep me".write(to: sourceURL, atomically: true, encoding: .utf8)
        let engine = LibArchiveEngine()

        do {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: sourceURL,
                    format: .zip
                )
            )
            XCTFail("Expected invalid destination error.")
        } catch ArchiveError.invalidDestination(let url) {
            XCTAssertEqual(url.standardizedFileURL.path, sourceURL.standardizedFileURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "keep me")
    }

    func testCreateRejectsDestinationInsideSourceDirectory() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = sourceURL.appendingPathComponent("nested-output.zip")
        let engine = LibArchiveEngine()

        do {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [sourceURL],
                    destinationURL: archiveURL,
                    format: .zip
                )
            )
            XCTFail("Expected invalid destination error.")
        } catch ArchiveError.invalidDestination(let url) {
            XCTAssertEqual(url.standardizedFileURL.path, archiveURL.standardizedFileURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateKeepsExistingDestinationWhenSourceIsInvalid() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("existing.zip")
        let missingSourceURL = workspaceURL.appendingPathComponent("missing")
        let engine = LibArchiveEngine()

        try "existing archive".write(to: archiveURL, atomically: true, encoding: .utf8)

        do {
            try await engine.create(
                CompressionRequest(
                    sourceURLs: [missingSourceURL],
                    destinationURL: archiveURL,
                    format: .zip
                )
            )
            XCTFail("Expected invalid source error.")
        } catch ArchiveError.invalidSource(let url) {
            XCTAssertEqual(url.standardizedFileURL.path, missingSourceURL.standardizedFileURL.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try String(contentsOf: archiveURL, encoding: .utf8), "existing archive")
    }

    func testExtractRejectsExistingSymlinkDirectoryEscape() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let sourceURL = try makeFixtureSource(in: workspaceURL)
        let archiveURL = workspaceURL.appendingPathComponent("symlink-parent.zip")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let outsideURL = workspaceURL.appendingPathComponent("outside", isDirectory: true)
        let symlinkURL = outputURL.appendingPathComponent("source")
        let engine = LibArchiveEngine()

        try await engine.create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: .init(includeHiddenFiles: true)
            )
        )

        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: symlinkURL.path,
            withDestinationPath: outsideURL.path
        )

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
        } catch ArchiveError.unsafeEntryPath {
            XCTAssertFalse(fileManager.fileExists(atPath: outsideURL.appendingPathComponent("hello.txt").path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListEntriesMarksHardLink() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("hard-link.tar")
        let engine = LibArchiveEngine()

        try makeRawTarArchive(
            at: archiveURL,
            entries: [
                RawArchiveEntry(
                    path: "linked.txt",
                    fileType: LibArchiveFileType.regular,
                    hardLinkTarget: "original.txt"
                )
            ]
        )

        let entries = try await engine.listEntries(in: archiveURL)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.path, "linked.txt")
        XCTAssertEqual(entry.kind, .hardLink(target: "original.txt"))
    }

    func testExtractRejectsHardLinkEntry() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("unsafe-hard-link.tar")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

        try makeRawTarArchive(
            at: archiveURL,
            entries: [
                RawArchiveEntry(
                    path: "linked.txt",
                    fileType: LibArchiveFileType.regular,
                    hardLinkTarget: "../../outside.txt"
                )
            ]
        )

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
            XCTFail("Expected unsupported entry type error.")
        } catch ArchiveError.unsupportedEntryType(let path, let type) {
            XCTAssertEqual(path, "linked.txt")
            XCTAssertEqual(type, "hard link")
            XCTAssertFalse(fileManager.fileExists(atPath: outputURL.appendingPathComponent("linked.txt").path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExtractRejectsSpecialFileEntry() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("special.tar")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

        try makeRawTarArchive(
            at: archiveURL,
            entries: [
                RawArchiveEntry(path: "pipe", fileType: LibArchiveFileType.fifo)
            ]
        )

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
            XCTFail("Expected unsupported entry type error.")
        } catch ArchiveError.unsupportedEntryType(let path, let type) {
            XCTAssertEqual(path, "pipe")
            XCTAssertEqual(type, "fifo")
            XCTAssertFalse(fileManager.fileExists(atPath: outputURL.appendingPathComponent("pipe").path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExtractRejectsUnsafeSymbolicLinkTarget() async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("unsafe-symlink.tar")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

        try makeRawTarArchive(
            at: archiveURL,
            entries: [
                RawArchiveEntry(
                    path: "link",
                    fileType: LibArchiveFileType.symbolicLink,
                    symlinkTarget: "folder/\u{202E}target"
                )
            ]
        )

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
            XCTFail("Expected unsafe symbolic link target error.")
        } catch ArchiveError.unsafeEntryPath(let path) {
            XCTAssertEqual(path, "folder/\u{202E}target")
            XCTAssertFalse(fileManager.fileExists(atPath: outputURL.appendingPathComponent("link").path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExtractRejectsArchiveWhenEntryCountExceedsLimit() async throws {
        try await assertExtractRejectsResourceLimit(
            entries: [
                RawArchiveEntry(
                    path: "one.txt",
                    fileType: LibArchiveFileType.regular,
                    data: Data("one".utf8)
                ),
                RawArchiveEntry(
                    path: "two.txt",
                    fileType: LibArchiveFileType.regular,
                    data: Data("two".utf8)
                )
            ],
            limits: ExtractionResourceLimits(
                maxEntryCount: 1,
                maxTotalUncompressedSize: nil,
                maxSingleFileUncompressedSize: nil,
                maxDirectoryDepth: nil
            ),
            expectedViolation: .entryCount(limit: 1, actual: 2)
        )
    }

    func testExtractRejectsArchiveWhenTotalUncompressedSizeExceedsLimit() async throws {
        try await assertExtractRejectsResourceLimit(
            entries: [
                RawArchiveEntry(
                    path: "one.txt",
                    fileType: LibArchiveFileType.regular,
                    data: Data("one".utf8)
                ),
                RawArchiveEntry(
                    path: "two.txt",
                    fileType: LibArchiveFileType.regular,
                    data: Data("two".utf8)
                )
            ],
            limits: ExtractionResourceLimits(
                maxEntryCount: nil,
                maxTotalUncompressedSize: 5,
                maxSingleFileUncompressedSize: nil,
                maxDirectoryDepth: nil
            ),
            expectedViolation: .totalUncompressedSize(limit: 5, actual: 6)
        )
    }

    func testExtractRejectsArchiveWhenSingleFileSizeExceedsLimit() async throws {
        try await assertExtractRejectsResourceLimit(
            entries: [
                RawArchiveEntry(
                    path: "large.bin",
                    fileType: LibArchiveFileType.regular,
                    data: Data(repeating: 1, count: 8)
                )
            ],
            limits: ExtractionResourceLimits(
                maxEntryCount: nil,
                maxTotalUncompressedSize: nil,
                maxSingleFileUncompressedSize: 4,
                maxDirectoryDepth: nil
            ),
            expectedViolation: .singleFileUncompressedSize(path: "large.bin", limit: 4, actual: 8)
        )
    }

    func testExtractRejectsArchiveWhenDirectoryDepthExceedsLimit() async throws {
        try await assertExtractRejectsResourceLimit(
            entries: [
                RawArchiveEntry(
                    path: "a/b/c/file.txt",
                    fileType: LibArchiveFileType.regular,
                    data: Data("deep".utf8)
                )
            ],
            limits: ExtractionResourceLimits(
                maxEntryCount: nil,
                maxTotalUncompressedSize: nil,
                maxSingleFileUncompressedSize: nil,
                maxDirectoryDepth: 2
            ),
            expectedViolation: .directoryDepth(path: "a/b/c/file.txt", limit: 2, actual: 3)
        )
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
                options: .init(
                    overwritePolicy: .overwrite,
                    shouldCreateContainingDirectory: false
                )
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
    struct RawArchiveEntry {
        let path: String
        let fileType: UInt32
        let data: Data?
        let hardLinkTarget: String?
        let symlinkTarget: String?

        init(
            path: String,
            fileType: UInt32,
            data: Data? = nil,
            hardLinkTarget: String? = nil,
            symlinkTarget: String? = nil
        ) {
            self.path = path
            self.fileType = fileType
            self.data = data
            self.hardLinkTarget = hardLinkTarget
            self.symlinkTarget = symlinkTarget
        }
    }

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
                options: .init(
                    overwritePolicy: .overwrite,
                    shouldCreateContainingDirectory: false
                )
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

    func assertExtractRejectsResourceLimit(
        entries: [RawArchiveEntry],
        limits: ExtractionResourceLimits,
        expectedViolation: ExtractionResourceLimitViolation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let archiveURL = workspaceURL.appendingPathComponent("resource-limit.tar")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        let engine = LibArchiveEngine()

        try makeRawTarArchive(at: archiveURL, entries: entries)

        do {
            try await engine.extract(
                ExtractionRequest(
                    archiveURL: archiveURL,
                    destinationURL: outputURL,
                    options: .init(
                        overwritePolicy: .overwrite,
                        shouldCreateContainingDirectory: false,
                        resourceLimits: limits
                    )
                )
            )
            XCTFail("Expected resource limit error.", file: file, line: line)
        } catch ArchiveError.extractionResourceLimitExceeded(let violation) {
            XCTAssertEqual(violation, expectedViolation, file: file, line: line)
            XCTAssertFalse(fileManager.fileExists(atPath: outputURL.path), file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
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

    func makeRawTarArchive(at archiveURL: URL, entries: [RawArchiveEntry]) throws {
        guard let archive = archive_write_new() else {
            throw ArchiveError.engineFailure(engine: "test", message: "Failed to allocate archive writer.")
        }
        defer {
            _ = archive_write_free(archive)
        }

        try requireArchiveStatus(
            archive_write_set_format_pax_restricted(archive),
            archive: archive,
            operation: "set tar writer"
        )
        try archiveURL.path.withCString { path in
            try requireArchiveStatus(
                archive_write_open_filename(archive, path),
                archive: archive,
                operation: "open archive writer"
            )
        }

        for rawEntry in entries {
            try writeRawEntry(rawEntry, to: archive)
        }

        try requireArchiveStatus(
            archive_write_close(archive),
            archive: archive,
            operation: "close archive writer"
        )
    }

    func writeRawEntry(_ rawEntry: RawArchiveEntry, to archive: OpaquePointer) throws {
        guard let entry = archive_entry_new() else {
            throw ArchiveError.engineFailure(engine: "test", message: "Failed to allocate archive entry.")
        }
        defer {
            archive_entry_free(entry)
        }

        rawEntry.path.withCString { path in
            archive_entry_copy_pathname(entry, path)
        }
        if let hardLinkTarget = rawEntry.hardLinkTarget {
            hardLinkTarget.withCString { target in
                archive_entry_copy_hardlink(entry, target)
            }
        }
        if let symlinkTarget = rawEntry.symlinkTarget {
            symlinkTarget.withCString { target in
                archive_entry_copy_symlink(entry, target)
            }
        }

        archive_entry_set_filetype(entry, rawEntry.fileType)
        archive_entry_set_perm(entry, 0o644)
        archive_entry_set_size(entry, Int64(rawEntry.data?.count ?? 0))

        try requireArchiveStatus(
            archive_write_header(archive, entry),
            archive: archive,
            operation: "write archive header"
        )

        if let data = rawEntry.data, !data.isEmpty {
            let writtenCount = data.withUnsafeBytes { buffer in
                archive_write_data(archive, buffer.baseAddress, data.count)
            }

            guard writtenCount == data.count else {
                throw ArchiveError.engineFailure(engine: "test", message: "Failed to write archive data.")
            }
        }

        try requireArchiveStatus(
            archive_write_finish_entry(archive),
            archive: archive,
            operation: "finish archive entry"
        )
    }

    func requireArchiveStatus(
        _ status: Int32,
        archive: OpaquePointer,
        operation: String
    ) throws {
        guard status == LibArchiveStatus.ok else {
            let message = archive_error_string(archive).map { String(cString: $0) }
                ?? "Unknown libarchive error."
            throw ArchiveError.engineFailure(engine: "test", message: "\(operation): \(message)")
        }
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
