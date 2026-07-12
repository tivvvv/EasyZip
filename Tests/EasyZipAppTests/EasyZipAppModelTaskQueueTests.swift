import EasyZipCore
import XCTest
@testable import EasyZipApp

@MainActor
final class EasyZipAppModelTaskQueueTests: XCTestCase {
    func testExternalCompressionRunsInBackgroundWithOutputDirectory() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let sourceURL = workspaceURL.appendingPathComponent("finder.txt")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try "finder".write(to: sourceURL, atomically: true, encoding: .utf8)
        let model = makeModel(defaultOutputDirectory: outputURL)

        let disposition = model.prepareExternalSelection(mode: .compress, fileURLs: [sourceURL])
        try await waitForIdle(model)

        XCTAssertEqual(disposition, .handledInBackground)
        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .succeeded)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputURL.appendingPathComponent("finder.zip").path
            )
        )
    }

    func testRecordsSuccessfulCompressionTaskInQueue() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let sourceURL = workspaceURL.appendingPathComponent("hello.txt")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try "hello".write(to: sourceURL, atomically: true, encoding: .utf8)
        let model = makeModel()

        model.addFileURLs([sourceURL])
        model.outputDirectory = outputURL
        model.archiveName = "hello"
        model.startOperation()

        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .succeeded)
        XCTAssertEqual(model.taskQueue.first?.progressFraction, 1)
        XCTAssertEqual(model.taskQueue.first?.result?.title, "压缩完成")
        XCTAssertEqual(model.visibleTaskQueue.first?.id, model.taskQueue.first?.id)
    }

    func testRecordsFailedTaskAndAllowsRetry() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let missingSourceURL = workspaceURL.appendingPathComponent("missing.txt")
        let model = makeModel()

        model.selectedItems = [missingSourceURL]
        model.outputDirectory = workspaceURL
        model.startOperation()

        try await waitForIdle(model)
        let failedTask = try XCTUnwrap(model.taskQueue.first)
        XCTAssertEqual(failedTask.status, .failed)

        model.retryQueuedTask(failedTask)
        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.count, 2)
        XCTAssertEqual(model.taskQueue.map(\.status), [.failed, .failed])
    }

    func testFailedBackgroundTaskSendsNotification() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let missingSourceURL = workspaceURL.appendingPathComponent("missing.txt")
        var notifiedResults: [TaskResult] = []
        let model = makeModel(
            defaultOutputDirectory: workspaceURL,
            notificationEnabled: true,
            taskResultNotifier: { notifiedResults.append($0) }
        )

        let disposition = model.prepareExternalSelection(
            mode: .compress,
            fileURLs: [missingSourceURL]
        )
        try await waitForIdle(model)

        XCTAssertEqual(disposition, .handledInBackground)
        XCTAssertEqual(model.taskQueue.first?.status, .failed)
        XCTAssertEqual(notifiedResults.map(\.title), ["操作失败"])
    }

    func testRetryQueuesWhenAnotherTaskIsRunning() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let missingSourceURL = workspaceURL.appendingPathComponent("missing.txt")
        let model = makeModel()

        model.selectedItems = [missingSourceURL]
        model.outputDirectory = workspaceURL
        model.startOperation()
        try await waitForIdle(model)
        let failedTask = try XCTUnwrap(model.taskQueue.first)

        model.isRunning = true
        model.retryQueuedTask(failedTask)

        XCTAssertEqual(model.taskQueue.count, 2)
        XCTAssertEqual(model.taskQueue.last?.status, .waiting)
        XCTAssertEqual(model.taskQueue.last?.snapshot.sourceURLs, failedTask.snapshot.sourceURLs)
    }

    func testRetryKeepsSelectedArchiveEntriesInTaskSnapshot() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let missingArchiveURL = workspaceURL.appendingPathComponent("missing.zip")
        let selectedEntryPaths: Set<String> = ["folder/file.txt"]
        let model = makeModel()

        model.mode = .extract
        model.selectedItems = [missingArchiveURL]
        model.selectedArchiveEntryPaths = selectedEntryPaths
        model.outputDirectory = workspaceURL
        model.startOperation()

        try await waitForIdle(model)
        let failedTask = try XCTUnwrap(model.taskQueue.first)
        XCTAssertEqual(failedTask.snapshot.selectedEntryPaths, selectedEntryPaths)

        model.retryQueuedTask(failedTask)
        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.count, 2)
        XCTAssertEqual(model.taskQueue.last?.snapshot.selectedEntryPaths, selectedEntryPaths)
    }

    func testFinishedTaskSnapshotDoesNotKeepPasswords() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let sourceURL = workspaceURL.appendingPathComponent("secret.txt")
        try "secret".write(to: sourceURL, atomically: true, encoding: .utf8)
        let model = makeModel()

        model.addFileURLs([sourceURL])
        model.outputDirectory = workspaceURL
        model.encryptCompression = true
        model.compressionPassword = "password"
        model.compressionPasswordConfirmation = "password"
        model.startOperation()

        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.first?.status, .succeeded)
        XCTAssertNil(model.taskQueue.first?.snapshot.compressionPassword)
    }

    func testPasswordPromptReusesWaitingQueuedTask() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.outputDirectory = workspaceURL.appendingPathComponent("output", isDirectory: true)
        model.startOperation()

        try await waitForPasswordPrompt(model)
        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .waiting)

        model.submitExtractionPassword("password")
        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .succeeded)
        XCTAssertNil(model.taskQueue.first?.snapshot.extractionPassword)
    }

    func testCancellingPasswordPromptCancelsWaitingQueuedTask() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.outputDirectory = workspaceURL.appendingPathComponent("output", isDirectory: true)
        model.startOperation()

        try await waitForPasswordPrompt(model)
        model.cancelExtractionPasswordPrompt()

        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .cancelled)
        XCTAssertEqual(model.taskQueue.first?.result?.detail, "未输入归档密码")
    }

    func testWaitingPasswordTaskCannotBeRetriedFromQueue() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.outputDirectory = workspaceURL.appendingPathComponent("output", isDirectory: true)
        model.startOperation()

        try await waitForPasswordPrompt(model)
        let waitingTask = try XCTUnwrap(model.taskQueue.first)
        model.retryQueuedTask(waitingTask)

        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .waiting)
        XCTAssertNotNil(model.passwordPrompt)
    }

    func testCancelsWaitingPasswordTaskFromQueue() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.outputDirectory = workspaceURL.appendingPathComponent("output", isDirectory: true)
        model.startOperation()

        try await waitForPasswordPrompt(model)
        let waitingTask = try XCTUnwrap(model.taskQueue.first)
        model.cancelQueuedTask(waitingTask)

        XCTAssertEqual(model.taskQueue.count, 1)
        XCTAssertEqual(model.taskQueue.first?.status, .cancelled)
        XCTAssertNil(model.passwordPrompt)
    }

    func testCancellingPasswordPromptStartsNextQueuedTask() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let queuedSourceURL = workspaceURL.appendingPathComponent("queued.txt")
        try "queued".write(to: queuedSourceURL, atomically: true, encoding: .utf8)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.outputDirectory = workspaceURL
        model.startOperation()

        try await waitForPasswordPrompt(model)
        model.prepareExternalSelection(mode: .compress, fileURLs: [queuedSourceURL])
        XCTAssertEqual(model.taskQueue.map(\.status), [.waiting, .waiting])

        model.cancelExtractionPasswordPrompt()
        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.map(\.status), [.cancelled, .succeeded])
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("queued.zip").path))
    }

    func testExternalTaskWaitsForOutputDirectoryAndResumesSameQueueItem() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let archiveURL = try await makeEncryptedArchive(in: workspaceURL)
        let queuedSourceURL = workspaceURL.appendingPathComponent("queued.txt")
        let secondQueuedSourceURL = workspaceURL.appendingPathComponent("second.txt")
        let outputURL = workspaceURL.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try "queued".write(to: queuedSourceURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondQueuedSourceURL, atomically: true, encoding: .utf8)
        let model = makeModel()

        model.mode = .extract
        model.addFileURLs([archiveURL])
        model.startOperation()
        try await waitForPasswordPrompt(model)

        let disposition = model.prepareExternalSelection(
            mode: .compress,
            fileURLs: [queuedSourceURL]
        )
        model.prepareExternalSelection(mode: .compress, fileURLs: [secondQueuedSourceURL])
        model.cancelExtractionPasswordPrompt()

        XCTAssertEqual(disposition, .requiresWorkspace)
        XCTAssertEqual(model.taskQueue.map(\.status), [.cancelled, .waiting, .waiting])
        XCTAssertEqual(model.taskResult?.title, "请选择输出目录")

        model.useOutputDirectory(outputURL)
        try await waitForIdle(model)

        XCTAssertEqual(model.taskQueue.count, 3)
        XCTAssertEqual(model.taskQueue.map(\.status), [.cancelled, .succeeded, .succeeded])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputURL.appendingPathComponent("queued.zip").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputURL.appendingPathComponent("second.zip").path
            )
        )
    }

    func testClearsFinishedQueuedTasksOnly() async throws {
        let workspaceURL = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        let missingSourceURL = workspaceURL.appendingPathComponent("missing.txt")
        let model = makeModel()

        model.selectedItems = [missingSourceURL]
        model.outputDirectory = workspaceURL
        model.startOperation()
        try await waitForIdle(model)

        model.clearFinishedQueuedTasks()

        XCTAssertTrue(model.taskQueue.isEmpty)
    }

    private func makeModel(
        defaultOutputDirectory: URL? = nil,
        notificationEnabled: Bool = false,
        taskResultNotifier: @escaping (TaskResult) -> Void = { _ in }
    ) -> EasyZipAppModel {
        let settings = EasyZipAppSettings(
            userDefaults: makeUserDefaults(),
            launchAtLoginController: TaskQueueLaunchAtLoginController(isEnabled: false),
            notificationAuthorizationRequester: {}
        )
        settings.taskCompletionNotificationEnabled = notificationEnabled
        settings.defaultOutputDirectory = defaultOutputDirectory

        return EasyZipAppModel(
            settings: settings,
            taskResultNotifier: taskResultNotifier
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "EasyZipAppModelTaskQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "EasyZipAppModelTaskQueueTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEncryptedArchive(in workspaceURL: URL) async throws -> URL {
        let sourceURL = workspaceURL.appendingPathComponent("secure", isDirectory: true)
        let archiveURL = workspaceURL.appendingPathComponent("secure.zip")
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try "secret".write(
            to: sourceURL.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await ArchiveService.makeDefault().create(
            CompressionRequest(
                sourceURLs: [sourceURL],
                destinationURL: archiveURL,
                format: .zip,
                options: CompressionOptions(password: "password")
            )
        )

        return archiveURL
    }

    private func waitForIdle(_ model: EasyZipAppModel) async throws {
        for _ in 0..<200 {
            if !model.isRunning {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for task to finish.")
    }

    private func waitForPasswordPrompt(_ model: EasyZipAppModel) async throws {
        for _ in 0..<200 {
            if model.passwordPrompt != nil && !model.isRunning {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for password prompt.")
    }
}

@MainActor
private final class TaskQueueLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}
