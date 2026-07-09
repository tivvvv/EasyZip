import AppKit
import Combine
import EasyZipCore
import EasyZipShared
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EasyZipAppModel: ObservableObject {
    @Published var mode: WorkspaceMode = .compress {
        didSet {
            clearExtractionPassword()
            if mode != .compress {
                disableCompressionEncryption()
            }
            normalizeSelectedItemsForCurrentMode()
            resetProgressIfIdle()
            refreshExternalToolAvailability()
            refreshArchivePreview()
        }
    }
    @Published var selectedItems: [URL] = []
    @Published var outputDirectory: URL? {
        didSet {
            resetProgressIfIdle()
            refreshExternalToolAvailability()
        }
    }
    @Published var selectedFormat: ArchiveFormat = .zip {
        didSet {
            normalizeCompressionEncryptionForSelectedFormat()
            updateDefaultArchiveNameAfterFormatChange(from: oldValue)
            resetProgressIfIdle()
            refreshExternalToolAvailability()
        }
    }
    @Published var overwritePolicy: OverwritePolicy = .rename
    @Published var archiveName = "归档文件"
    @Published var includeHiddenFiles = false
    @Published var preserveParentDirectory = true
    @Published var preserveMetadata = true
    @Published var shouldCreateContainingDirectory = true
    @Published var encryptCompression = false {
        didSet {
            if !encryptCompression {
                clearCompressionPassword()
            }
            resetProgressIfIdle()
        }
    }
    @Published var compressionPassword = ""
    @Published var compressionPasswordConfirmation = ""
    @Published var archiveEntries: [ArchiveEntryRow] = []
    @Published var selectedArchiveEntryPaths: Set<String> = []
    @Published var previewState = "未选择归档"
    @Published var progressFraction = 0.0
    @Published var progressText = "空闲"
    @Published var isRunning = false
    @Published var isDropTargeted = false
    @Published var taskResult: TaskResult?
    @Published private(set) var taskQueue: [ArchiveQueuedTask] = []
    @Published private(set) var rarCommandAvailability = RARCommandResolver().availability()
    @Published private(set) var zstdCommandAvailability = ZstdCommandResolver().availability()
    @Published private(set) var recentTasks = RecentArchiveStore.loadTasks()
    @Published private(set) var recentOutputDirectories = RecentArchiveStore.loadOutputDirectories()
    @Published var passwordPrompt: ArchivePasswordPrompt?
    @Published var conflictPrompt: ArchiveConflictPrompt?
    @Published var alert: AppAlert?

    private var operationTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var activeQueuedTaskID: UUID?
    private let settings: EasyZipAppSettings
    private let rarCommandResolver: RARCommandResolver
    private let zstdCommandResolver: ZstdCommandResolver
    private var settingsCancellables: Set<AnyCancellable> = []
    private var extractionPassword: String?
    private var conflictDecisionCoordinator: ArchiveConflictDecisionCoordinator?
    private var passwordRetryQueuedTaskID: UUID?
    private var shouldContinueQueueAfterCancellation = true

    init(
        settings: EasyZipAppSettings = .shared,
        rarCommandResolver: RARCommandResolver = RARCommandResolver(),
        zstdCommandResolver: ZstdCommandResolver = ZstdCommandResolver()
    ) {
        self.settings = settings
        self.rarCommandResolver = rarCommandResolver
        self.zstdCommandResolver = zstdCommandResolver
        outputDirectory = settings.effectiveDefaultOutputDirectory
        selectedFormat = settings.defaultCompressionFormat
        overwritePolicy = settings.defaultOverwritePolicy
        shouldCreateContainingDirectory = settings.shouldCreateContainingDirectory
        rarCommandAvailability = rarCommandResolver.availability()
        zstdCommandAvailability = zstdCommandResolver.availability()
        observeSettings()
    }

    var primaryActionTitle: String {
        switch mode {
        case .compress:
            return "开始压缩"
        case .extract:
            return selectedArchiveEntryPaths.isEmpty ? "解压全部" : "解压所选"
        }
    }

    var canRun: Bool {
        !selectedItems.isEmpty && !isRunning
    }

    var formatRequirementStatus: (title: String, detail: String, iconName: String, isBlocking: Bool)? {
        if requiresRARCommand {
            return externalToolRequirementStatus(
                availability: rarCommandAvailability,
                availableTitle: "RAR 命令可用",
                missingTitle: "需要安装 rar 命令",
                missingDetail: "安装 RAR 命令行工具后可创建 .rar 归档"
            )
        }

        if requiresZstdCommand {
            return externalToolRequirementStatus(
                availability: zstdCommandAvailability,
                availableTitle: "zstd 命令可用",
                missingTitle: "需要安装 zstd 命令",
                missingDetail: "安装 zstd 命令行工具后可创建 .tar.zst 归档"
            )
        }

        return nil
    }

    var canEncryptCompression: Bool {
        selectedFormat.supportsEncryptedCompression
    }

    var compressionPasswordValidationMessage: String? {
        guard encryptCompression else {
            return nil
        }

        guard canEncryptCompression else {
            return "当前格式暂不支持加密压缩"
        }

        guard !compressionPassword.isEmpty else {
            return "请输入压缩密码"
        }

        guard compressionPassword == compressionPasswordConfirmation else {
            return "两次密码不一致"
        }

        return nil
    }

    var outputLabel: String {
        outputDirectory?.displayPath ?? "选择输出目录"
    }

    var archiveFileNamePreview: String {
        ArchiveTaskRunner.compressionFileName(format: selectedFormat, archiveName: archiveName)
    }

    var canRevealOutput: Bool {
        revealTargetURL != nil
    }

    var visibleTaskQueue: [ArchiveQueuedTask] {
        Array(taskQueue.suffix(8).reversed())
    }

    var hasFinishedQueuedTasks: Bool {
        taskQueue.contains { $0.status.isFinished }
    }

    var selectedArchiveEntryCount: Int {
        selectedArchiveEntryRows.count
    }

    var selectedArchiveEntrySizeText: String {
        let byteCount = selectedArchiveEntryRows.reduce(Int64(0)) { partialResult, row in
            partialResult + max(row.uncompressedSize ?? 0, 0)
        }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    func chooseItems() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = FileSelectionPanelFactory.makeItemSelectionPanel(mode: mode)

        if panel.runModal() == .OK {
            if isRunning || passwordPrompt != nil {
                prepareExternalSelection(mode: mode, fileURLs: panel.urls)
            } else {
                addFileURLs(panel.urls)
            }
        }
    }

    func chooseOutputDirectory() {
        guard !isRunning else {
            alert = AppAlert(title: "任务进行中", message: "当前任务完成后再调整输出目录")
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = FileSelectionPanelFactory.makeOutputDirectoryPanel()

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            recordRecentOutputDirectory(url)
        }
    }

    func addFileURLs(_ urls: [URL]) {
        guard !isRunning else {
            return
        }

        let inputFilterResult = ArchiveInputFilter.filter(urls, for: mode)
        guard !inputFilterResult.acceptedFileURLs.isEmpty else {
            reportNoAcceptableFiles(mode: mode)
            return
        }

        clearExtractionPassword()
        selectedItems = FileURLListNormalizer.uniqueStandardizedFileURLs(
            selectedItems + inputFilterResult.acceptedFileURLs
        )
        resetProgressIfIdle()
        updateDefaultArchiveName()
        refreshArchivePreview()

        if inputFilterResult.rejectedCount > 0 {
            reportRejectedArchiveInputs(count: inputFilterResult.rejectedCount, mode: mode)
        }
    }

    func removeItem(_ url: URL) {
        guard !isRunning else {
            return
        }

        clearExtractionPassword()
        selectedItems.removeAll { $0 == url }
        resetProgressIfIdle()
        updateDefaultArchiveName()
        refreshArchivePreview()
    }

    func clearItems() {
        guard !isRunning else {
            return
        }

        selectedItems.removeAll()
        archiveEntries.removeAll()
        selectedArchiveEntryPaths.removeAll()
        clearExtractionPassword()
        previewState = "未选择归档"
        resetProgressIfIdle()
        updateDefaultArchiveName()
    }

    func prepareExternalSelection(mode: WorkspaceMode, fileURLs: [URL]) {
        let inputFilterResult = ArchiveInputFilter.filter(fileURLs, for: mode)
        let acceptedFileURLs = FileURLListNormalizer.uniqueStandardizedFileURLs(
            inputFilterResult.acceptedFileURLs
        )

        guard !acceptedFileURLs.isEmpty else {
            reportNoAcceptableFiles(mode: mode)
            return
        }

        guard !isRunning, passwordPrompt == nil else {
            enqueueExternalSelection(
                mode: mode,
                fileURLs: acceptedFileURLs,
                rejectedCount: inputFilterResult.rejectedCount
            )
            return
        }

        if inputFilterResult.rejectedCount > 0 {
            reportRejectedArchiveInputs(count: inputFilterResult.rejectedCount, mode: mode)
        }

        applyExternalSelection(mode: mode, fileURLs: acceptedFileURLs)
    }

    func submitExtractionPassword(_ password: String) {
        guard !password.isEmpty else {
            return
        }

        let queuedTaskID = passwordRetryQueuedTaskID
        passwordRetryQueuedTaskID = nil
        extractionPassword = password
        passwordPrompt = nil
        startOperation(reusingQueuedTaskID: queuedTaskID)
    }

    func cancelExtractionPasswordPrompt() {
        clearExtractionPassword()
        progressText = "已取消"
        let result = TaskResult(
            title: "已取消",
            detail: "未输入归档密码",
            outputURL: nil,
            iconName: "xmark.circle"
        )
        taskResult = result

        if let passwordRetryQueuedTaskID {
            finishQueuedTask(id: passwordRetryQueuedTaskID, status: .cancelled, result: result)
            self.passwordRetryQueuedTaskID = nil
        }

        startNextQueuedTaskIfPossible()
    }

    func resolveArchiveConflict(
        _ prompt: ArchiveConflictPrompt,
        policy: OverwritePolicy,
        appliesToRemainingConflicts: Bool
    ) {
        conflictPrompt = nil
        conflictDecisionCoordinator?.submitDecision(
            ArchiveConflictDecision(
                policy: policy,
                appliesToRemainingConflicts: appliesToRemainingConflicts
            ),
            for: prompt.id
        )
    }

    private func applyExternalSelection(mode: WorkspaceMode, fileURLs: [URL]) {
        let shouldMerge = self.mode == mode && !selectedItems.isEmpty

        self.mode = mode

        if !shouldMerge {
            selectedItems.removeAll()
            archiveEntries.removeAll()
            selectedArchiveEntryPaths.removeAll()
            clearExtractionPassword()
            previewState = mode == .extract ? "未选择归档" : "归档预览"
        }

        addFileURLs(fileURLs)

        taskResult = TaskResult(
            title: shouldMerge ? "已合并新选择" : "已载入新选择",
            detail: "\(mode.rawValue)队列当前包含 \(selectedItems.count) 项",
            outputURL: nil,
            iconName: shouldMerge ? "plus.square.on.square" : "tray.full"
        )
    }

    private func enqueueExternalSelection(
        mode: WorkspaceMode,
        fileURLs: [URL],
        rejectedCount: Int
    ) {
        let snapshot = externalTaskSnapshot(mode: mode, fileURLs: fileURLs)
        enqueueTask(snapshot)

        let rejectedDetail = rejectedCount > 0
            ? ", 已忽略 \(rejectedCount) 个不支持解压的文件"
            : ""
        alert = AppAlert(
            title: "已加入任务队列",
            message: "当前任务完成后自动执行 \(fileURLs.count) 项\(mode.rawValue)文件\(rejectedDetail)"
        )
    }

    func startOperation(reusingQueuedTaskID: UUID? = nil) {
        if let reusingQueuedTaskID {
            startQueuedTask(id: reusingQueuedTaskID, snapshot: currentTaskSnapshot())
            return
        }

        guard !selectedItems.isEmpty else {
            return
        }

        guard compressionPasswordIsValid() else {
            return
        }

        guard outputDirectoryIsReadyForCurrentOperation() else {
            return
        }

        enqueueTask(currentTaskSnapshot())
    }

    private func startQueuedTask(id queuedTaskID: UUID, snapshot: ArchiveTaskSnapshot? = nil) {
        guard !isRunning else {
            return
        }

        if let snapshot {
            updateQueuedTask(id: queuedTaskID) { task in
                task.snapshot = snapshot
            }
        }

        guard let task = taskQueue.first(where: { $0.id == queuedTaskID }) else {
            return
        }

        applyTaskSnapshot(task.snapshot)
        refreshExternalToolAvailability()

        guard requiredExternalToolsAreAvailable else {
            reportMissingRequiredExternalTool()
            finishQueuedTaskFromCurrentResult(id: queuedTaskID, status: .failed)
            startNextQueuedTaskIfPossible()
            return
        }

        guard compressionPasswordIsValid() else {
            finishQueuedTaskFromCurrentResult(id: queuedTaskID, status: .failed)
            startNextQueuedTaskIfPossible()
            return
        }

        guard outputDirectoryIsReadyForCurrentOperation() else {
            finishQueuedTaskFromCurrentResult(id: queuedTaskID, status: .failed)
            startNextQueuedTaskIfPossible()
            return
        }

        let taskSnapshot = currentTaskSnapshot()
        let queuedTaskID = prepareQueuedTask(taskSnapshot, reusingQueuedTaskID: queuedTaskID)
        isRunning = true
        progressFraction = 0
        progressText = startingProgressText(for: mode)
        taskResult = TaskResult(
            title: "任务进行中",
            detail: "\(mode.rawValue)任务正在执行",
            outputURL: nil,
            iconName: "clock"
        )

        let mode = mode
        let selectedItems = selectedItems
        let outputDirectory = outputDirectory
        let selectedFormat = selectedFormat
        let overwritePolicy = overwritePolicy
        let shouldCreateContainingDirectory = shouldCreateContainingDirectory
        let entryPathsToExtract = mode == .extract && selectedItems.count == 1
            ? selectedArchiveEntryPaths
            : []
        let extractionPassword = mode == .extract ? extractionPassword : nil
        let conflictDecisionCoordinator = makeConflictDecisionCoordinatorIfNeeded(
            mode: mode,
            overwritePolicy: overwritePolicy
        )
        let conflictResolver = conflictDecisionCoordinator?.makeResolver()
        let archiveName = archiveName
        let includeHiddenFiles = includeHiddenFiles
        let preserveParentDirectory = preserveParentDirectory
        let preserveMetadata = preserveMetadata
        let compressionPassword = mode == .compress && encryptCompression ? compressionPassword : nil

        operationTask = Task.detached { [weak self] in
            do {
                let result: TaskResult

                switch mode {
                case .compress:
                    result = try await ArchiveTaskRunner.compress(
                        sourceURLs: selectedItems,
                        outputDirectory: outputDirectory,
                        format: selectedFormat,
                        archiveName: archiveName,
                        includeHiddenFiles: includeHiddenFiles,
                        preserveParentDirectory: preserveParentDirectory,
                        preserveMetadata: preserveMetadata,
                        password: compressionPassword,
                        progressHandler: { progress in
                            Task { @MainActor in
                                self?.apply(progress)
                            }
                        }
                    )
                case .extract:
                    result = try await ArchiveTaskRunner.extract(
                        archiveURLs: selectedItems,
                        outputDirectory: outputDirectory,
                        overwritePolicy: overwritePolicy,
                        shouldCreateContainingDirectory: shouldCreateContainingDirectory,
                        selectedEntryPaths: entryPathsToExtract,
                        password: extractionPassword,
                        conflictResolver: conflictResolver,
                        progressHandler: { progress in
                            Task { @MainActor in
                                self?.apply(progress)
                            }
                        }
                    )
                }

                await self?.finishOperation(result)
            } catch is CancellationError {
                await self?.cancelOperationResult(queuedTaskID: queuedTaskID)
            } catch {
                await self?.failOperation(error, queuedTaskID: queuedTaskID)
            }
        }
    }

    func cancelOperation(shouldContinueQueue: Bool = true) {
        shouldContinueQueueAfterCancellation = shouldContinueQueue
        conflictPrompt = nil
        operationTask?.cancel()
        conflictDecisionCoordinator?.cancelPendingDecision()
    }

    func refreshExternalToolAvailability() {
        guard !isRunning else {
            return
        }

        rarCommandAvailability = rarCommandResolver.availability()
        zstdCommandAvailability = zstdCommandResolver.availability()
    }

    func revealOutputInFinder() {
        guard let revealTargetURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([revealTargetURL])
    }

    func revealQueuedTaskOutput(_ task: ArchiveQueuedTask) {
        guard let outputURL = task.outputURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func retryQueuedTask(_ task: ArchiveQueuedTask) {
        guard task.status.allowsRetry else {
            return
        }

        enqueueTask(task.snapshot.withoutPasswords())
    }

    func cancelQueuedTask(_ task: ArchiveQueuedTask) {
        if task.status == .waiting, task.id == passwordRetryQueuedTaskID {
            cancelExtractionPasswordPrompt()
            return
        }

        if task.status == .waiting {
            let result = TaskResult(
                title: "已取消",
                detail: "任务已从等待队列中取消",
                outputURL: nil,
                iconName: "xmark.circle"
            )
            finishQueuedTask(id: task.id, status: .cancelled, result: result)
            startNextQueuedTaskIfPossible()
            return
        }

        guard task.status == .running,
              task.id == activeQueuedTaskID else {
            return
        }

        cancelOperation()
    }

    func clearFinishedQueuedTasks() {
        taskQueue.removeAll { task in
            task.status.isFinished
        }
    }

    func clearRecentTasks() {
        recentTasks.removeAll()
        RecentArchiveStore.saveTasks(recentTasks)
    }

    func isArchiveEntrySelected(_ row: ArchiveEntryRow) -> Bool {
        selectedArchiveEntryPaths.contains(row.path)
    }

    func setArchiveEntrySelection(_ row: ArchiveEntryRow, isSelected: Bool) {
        guard row.canSelectForExtraction else {
            selectedArchiveEntryPaths.remove(row.path)
            return
        }

        if isSelected {
            selectedArchiveEntryPaths.insert(row.path)
        } else {
            selectedArchiveEntryPaths.remove(row.path)
        }
    }

    func selectArchiveEntries(_ rows: [ArchiveEntryRow]) {
        let selectablePaths = rows
            .filter(\.canSelectForExtraction)
            .map(\.path)

        selectedArchiveEntryPaths.formUnion(selectablePaths)
    }

    func replaceArchiveEntrySelection(with rows: [ArchiveEntryRow]) {
        selectedArchiveEntryPaths = selectablePathSet(from: rows)
    }

    func replaceArchiveEntrySelectionWithFiles(in rows: [ArchiveEntryRow]) {
        replaceArchiveEntrySelection(with: rows.filter(\.isFile))
    }

    func replaceArchiveEntrySelectionWithDirectories(in rows: [ArchiveEntryRow]) {
        replaceArchiveEntrySelection(with: rows.filter(\.isDirectory))
    }

    func replaceArchiveEntrySelectionWithRiskEntries(in rows: [ArchiveEntryRow]) {
        replaceArchiveEntrySelection(with: rows.filter { $0.risk != nil })
    }

    func invertArchiveEntrySelection(in rows: [ArchiveEntryRow]) {
        for path in selectablePathSet(from: rows) {
            if selectedArchiveEntryPaths.contains(path) {
                selectedArchiveEntryPaths.remove(path)
            } else {
                selectedArchiveEntryPaths.insert(path)
            }
        }
    }

    func clearArchiveEntrySelection() {
        selectedArchiveEntryPaths.removeAll()
    }

    func removeRecentOutputDirectory(_ directory: RecentOutputDirectory) {
        recentOutputDirectories.removeAll { $0.id == directory.id }
        RecentArchiveStore.saveOutputDirectories(recentOutputDirectories)
    }

    func toggleRecentOutputDirectoryPin(_ directory: RecentOutputDirectory) {
        guard let index = recentOutputDirectories.firstIndex(where: { $0.id == directory.id }) else {
            return
        }

        recentOutputDirectories[index].isPinned.toggle()
        recentOutputDirectories[index].updatedAt = Date()
        recentOutputDirectories = RecentArchiveStore.sortedVisibleOutputDirectories(
            recentOutputDirectories
        )
        RecentArchiveStore.saveOutputDirectories(recentOutputDirectories)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !isRunning else {
            return false
        }

        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    self?.addFileURLs([url])
                }
            }
        }

        return !providers.isEmpty
    }

    private var revealTargetURL: URL? {
        taskResult?.outputURL ?? outputDirectory
    }

    private var selectedArchiveEntryRows: [ArchiveEntryRow] {
        archiveEntries.filter { selectedArchiveEntryPaths.contains($0.path) }
    }

    private func selectablePathSet(from rows: [ArchiveEntryRow]) -> Set<String> {
        Set(rows.filter(\.canSelectForExtraction).map(\.path))
    }

    private var requiresRARCommand: Bool {
        mode == .compress && selectedFormat == .rar
    }

    private var requiresZstdCommand: Bool {
        mode == .compress && selectedFormat == .tarZstd
    }

    private var requiredExternalToolsAreAvailable: Bool {
        (!requiresRARCommand || rarCommandAvailability.isAvailable)
            && (!requiresZstdCommand || zstdCommandAvailability.isAvailable)
    }

    private func externalToolRequirementStatus(
        availability: ExternalToolAvailability,
        availableTitle: String,
        missingTitle: String,
        missingDetail: String
    ) -> (title: String, detail: String, iconName: String, isBlocking: Bool) {
        if let executableURL = availability.executableURL {
            return (
                title: availableTitle,
                detail: executableURL.path,
                iconName: "checkmark.circle",
                isBlocking: false
            )
        }

        return (
            title: missingTitle,
            detail: missingDetail,
            iconName: "exclamationmark.triangle",
            isBlocking: true
        )
    }

    private func observeSettings() {
        settings.$defaultOutputDirectory
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    self.outputDirectory = self.settings.effectiveDefaultOutputDirectory
                    self.showSettingsAppliedResult()
                }
            }
            .store(in: &settingsCancellables)

        settings.$defaultCompressionFormat
            .dropFirst()
            .sink { [weak self] format in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    self.selectedFormat = format
                    self.showSettingsAppliedResult()
                }
            }
            .store(in: &settingsCancellables)

        settings.$defaultOverwritePolicy
            .dropFirst()
            .sink { [weak self] overwritePolicy in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    self.overwritePolicy = overwritePolicy
                    self.showSettingsAppliedResult()
                }
            }
            .store(in: &settingsCancellables)

        settings.$shouldCreateContainingDirectory
            .dropFirst()
            .sink { [weak self] shouldCreateContainingDirectory in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    self.shouldCreateContainingDirectory = shouldCreateContainingDirectory
                    self.showSettingsAppliedResult()
                }
            }
            .store(in: &settingsCancellables)
    }

    private func showSettingsAppliedResult() {
        guard !isRunning else {
            return
        }

        taskResult = TaskResult(
            title: "设置已应用",
            detail: "默认任务设置已同步到工作台",
            outputURL: nil,
            iconName: "gearshape"
        )
        progressFraction = 0
        progressText = "设置已应用"
    }

    private func currentTaskSnapshot() -> ArchiveTaskSnapshot {
        ArchiveTaskSnapshot(
            mode: mode,
            sourceURLs: selectedItems,
            outputDirectory: outputDirectory,
            selectedFormat: selectedFormat,
            overwritePolicy: overwritePolicy,
            archiveName: archiveName,
            includeHiddenFiles: includeHiddenFiles,
            preserveParentDirectory: preserveParentDirectory,
            preserveMetadata: preserveMetadata,
            shouldCreateContainingDirectory: shouldCreateContainingDirectory,
            selectedEntryPaths: selectedArchiveEntryPaths,
            encryptCompression: encryptCompression,
            compressionPassword: mode == .compress && encryptCompression ? compressionPassword : nil,
            extractionPassword: mode == .extract ? extractionPassword : nil
        )
    }

    private func externalTaskSnapshot(
        mode: WorkspaceMode,
        fileURLs: [URL]
    ) -> ArchiveTaskSnapshot {
        ArchiveTaskSnapshot(
            mode: mode,
            sourceURLs: fileURLs,
            outputDirectory: outputDirectory,
            selectedFormat: selectedFormat,
            overwritePolicy: overwritePolicy,
            archiveName: defaultArchiveName(for: fileURLs, format: selectedFormat),
            includeHiddenFiles: includeHiddenFiles,
            preserveParentDirectory: preserveParentDirectory,
            preserveMetadata: preserveMetadata,
            shouldCreateContainingDirectory: shouldCreateContainingDirectory,
            selectedEntryPaths: [],
            encryptCompression: false,
            compressionPassword: nil,
            extractionPassword: nil
        )
    }

    private func defaultArchiveName(
        for urls: [URL],
        format: ArchiveFormat
    ) -> String {
        if urls.count == 1, let url = urls.first {
            return defaultArchiveName(for: url, format: format)
        }

        return urls.isEmpty ? "归档文件" : "批量归档"
    }

    private func applyTaskSnapshot(_ snapshot: ArchiveTaskSnapshot) {
        clearExtractionPassword()
        mode = snapshot.mode
        selectedItems = snapshot.sourceURLs
        outputDirectory = snapshot.outputDirectory
        selectedFormat = snapshot.selectedFormat
        overwritePolicy = snapshot.overwritePolicy
        archiveName = snapshot.archiveName
        includeHiddenFiles = snapshot.includeHiddenFiles
        preserveParentDirectory = snapshot.preserveParentDirectory
        preserveMetadata = snapshot.preserveMetadata
        shouldCreateContainingDirectory = snapshot.shouldCreateContainingDirectory
        selectedArchiveEntryPaths = snapshot.selectedEntryPaths
        encryptCompression = snapshot.encryptCompression
        compressionPassword = snapshot.compressionPassword ?? ""
        compressionPasswordConfirmation = snapshot.compressionPassword ?? ""
        extractionPassword = snapshot.extractionPassword
        resetProgressIfIdle()
        refreshExternalToolAvailability()
        refreshArchivePreview(preservingSelection: snapshot.selectedEntryPaths)
    }

    private func enqueueTask(_ snapshot: ArchiveTaskSnapshot) {
        _ = appendQueuedTask(snapshot, status: .waiting)

        if isRunning || passwordPrompt != nil {
            taskResult = TaskResult(
                title: "已加入队列",
                detail: "\(snapshot.mode.rawValue)任务将在当前任务完成后自动执行",
                outputURL: nil,
                iconName: "text.line.first.and.arrowtriangle.forward"
            )
            return
        }

        startNextQueuedTaskIfPossible()
    }

    private func appendQueuedTask(
        _ snapshot: ArchiveTaskSnapshot,
        status: ArchiveQueuedTaskStatus
    ) -> UUID {
        let queuedTask = ArchiveQueuedTask(
            snapshot: snapshot,
            status: status,
            progressText: startingProgressText(for: snapshot.mode)
        )
        taskQueue.append(queuedTask)
        trimTaskQueueIfNeeded()

        return queuedTask.id
    }

    private func prepareQueuedTask(
        _ snapshot: ArchiveTaskSnapshot,
        reusingQueuedTaskID: UUID?
    ) -> UUID {
        guard let reusingQueuedTaskID,
              taskQueue.contains(where: { $0.id == reusingQueuedTaskID }) else {
            let queuedTaskID = appendQueuedTask(snapshot, status: .running)
            activeQueuedTaskID = queuedTaskID

            return queuedTaskID
        }

        updateQueuedTask(id: reusingQueuedTaskID) { task in
            task.snapshot = snapshot
            task.status = .running
            task.progressFraction = 0
            task.progressText = startingProgressText(for: snapshot.mode)
            task.result = nil
            task.completedAt = nil
        }
        activeQueuedTaskID = reusingQueuedTaskID

        return reusingQueuedTaskID
    }

    private func startNextQueuedTaskIfPossible() {
        guard !isRunning, passwordPrompt == nil else {
            return
        }

        guard let nextTask = taskQueue.first(where: { task in
            task.status == .waiting && task.id != passwordRetryQueuedTaskID
        }) else {
            return
        }

        startQueuedTask(id: nextTask.id)
    }

    private func trimTaskQueueIfNeeded() {
        while taskQueue.count > 20 {
            guard let index = taskQueue.firstIndex(where: { task in
                task.status.isFinished
                    && task.id != activeQueuedTaskID
                    && task.id != passwordRetryQueuedTaskID
            }) else {
                return
            }

            taskQueue.remove(at: index)
        }
    }

    private func startingProgressText(for mode: WorkspaceMode) -> String {
        mode == .compress ? "准备压缩" : "准备解压"
    }

    private func updateQueuedTask(
        id: UUID,
        _ update: (inout ArchiveQueuedTask) -> Void
    ) {
        guard let index = taskQueue.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&taskQueue[index])
    }

    private func updateActiveQueuedTaskProgress() {
        guard let activeQueuedTaskID else {
            return
        }

        updateQueuedTask(id: activeQueuedTaskID) { task in
            task.progressFraction = progressFraction
            task.progressText = progressText
        }
    }

    private func finishQueuedTask(
        id: UUID?,
        status: ArchiveQueuedTaskStatus,
        result: TaskResult
    ) {
        guard let id else {
            return
        }

        updateQueuedTask(id: id) { task in
            task.status = status
            task.progressFraction = status == .succeeded ? 1 : task.progressFraction
            task.progressText = result.title
            task.result = result
            task.completedAt = Date()
            task.snapshot = task.snapshot.withoutPasswords()
        }

        if activeQueuedTaskID == id {
            activeQueuedTaskID = nil
        }

        if passwordRetryQueuedTaskID == id {
            passwordRetryQueuedTaskID = nil
        }
    }

    private func finishQueuedTaskFromCurrentResult(
        id: UUID,
        status: ArchiveQueuedTaskStatus
    ) {
        let result = taskResult ?? TaskResult(
            title: status.title,
            detail: "任务没有完成",
            outputURL: nil,
            iconName: status.iconName
        )
        finishQueuedTask(id: id, status: status, result: result)
    }

    private func compressionPasswordIsValid() -> Bool {
        guard mode == .compress,
              let message = compressionPasswordValidationMessage else {
            return true
        }

        let title = canEncryptCompression ? "需要密码" : "加密压缩不可用"
        taskResult = TaskResult(
            title: title,
            detail: message,
            outputURL: nil,
            iconName: "lock"
        )
        progressFraction = 0
        progressText = "等待密码"
        alert = AppAlert(title: title, message: message)
        return false
    }

    private func outputDirectoryIsReadyForCurrentOperation() -> Bool {
        guard mode == .compress,
              outputDirectory == nil else {
            return true
        }

        let title = "请选择输出目录"
        let message = "压缩前请先选择一个可写入的输出目录"
        taskResult = TaskResult(
            title: title,
            detail: message,
            outputURL: nil,
            iconName: "folder.badge.plus"
        )
        progressFraction = 0
        progressText = "等待输出目录"
        alert = AppAlert(title: title, message: message)
        return false
    }

    private func reportMissingRequiredExternalTool() {
        let toolName = requiresRARCommand ? RARCommandResolver.toolName : ZstdCommandResolver.toolName
        let title = requiresRARCommand ? "RAR 压缩不可用" : "TAR.ZST 压缩不可用"
        let message = ArchiveErrorMessageFormatter.message(
            for: ArchiveError.externalToolUnavailable(toolName)
        )

        taskResult = TaskResult(
            title: title,
            detail: message,
            outputURL: nil,
            iconName: "exclamationmark.triangle"
        )
        progressFraction = 0
        progressText = "等待外部工具"
        alert = AppAlert(title: title, message: message)
    }

    private func reportNoAcceptableFiles(mode: WorkspaceMode) {
        let message = mode == .extract ? "请选择支持的归档文件后重试" : "请选择文件后重试"
        alert = AppAlert(title: "没有可处理的文件", message: message)
    }

    private func reportRejectedArchiveInputs(count: Int, mode: WorkspaceMode) {
        guard mode == .extract, count > 0 else {
            return
        }

        alert = AppAlert(
            title: "已忽略不支持的文件",
            message: "已忽略 \(count) 个不支持解压的文件"
        )
    }

    private func updateDefaultArchiveName() {
        guard mode == .compress else {
            return
        }

        if selectedItems.count == 1, let firstItem = selectedItems.first {
            archiveName = defaultArchiveName(for: firstItem, format: selectedFormat)
        } else if selectedItems.isEmpty {
            archiveName = "归档文件"
        } else {
            archiveName = "批量归档"
        }
    }

    private func updateDefaultArchiveNameAfterFormatChange(from oldFormat: ArchiveFormat) {
        guard mode == .compress,
              selectedItems.count == 1,
              let firstItem = selectedItems.first else {
            return
        }

        let oldDefaultName = defaultArchiveName(for: firstItem, format: oldFormat)
        guard archiveName == oldDefaultName else {
            return
        }

        archiveName = defaultArchiveName(for: firstItem, format: selectedFormat)
    }

    private func defaultArchiveName(for url: URL, format: ArchiveFormat) -> String {
        if format.isSingleFileCompression {
            return url.lastPathComponent
        }

        return url.deletingPathExtension().lastPathComponent
    }

    private func resetProgressIfIdle() {
        guard !isRunning else {
            return
        }

        progressFraction = 0
        progressText = "空闲"
    }

    private func normalizeSelectedItemsForCurrentMode() {
        guard !selectedItems.isEmpty else {
            selectedArchiveEntryPaths.removeAll()
            return
        }

        let filteredItems = ArchiveInputFilter.filter(selectedItems, for: mode).acceptedFileURLs
        let normalizedItems = FileURLListNormalizer.uniqueStandardizedFileURLs(filteredItems)

        guard normalizedItems != selectedItems else {
            return
        }

        selectedItems = normalizedItems
        archiveEntries.removeAll()
        selectedArchiveEntryPaths.removeAll()
        updateDefaultArchiveName()
    }

    private func clearExtractionPassword() {
        extractionPassword = nil
        passwordPrompt = nil
    }

    private func clearCompressionPassword() {
        compressionPassword = ""
        compressionPasswordConfirmation = ""
    }

    private func disableCompressionEncryption() {
        guard encryptCompression else {
            clearCompressionPassword()
            return
        }

        encryptCompression = false
    }

    private func makeConflictDecisionCoordinatorIfNeeded(
        mode: WorkspaceMode,
        overwritePolicy: OverwritePolicy
    ) -> ArchiveConflictDecisionCoordinator? {
        guard mode == .extract, overwritePolicy == .ask else {
            conflictDecisionCoordinator = nil
            conflictPrompt = nil
            return nil
        }

        let coordinator = ArchiveConflictDecisionCoordinator { [weak self] prompt in
            self?.conflictPrompt = prompt
        }
        conflictDecisionCoordinator = coordinator
        conflictPrompt = nil

        return coordinator
    }

    private func normalizeCompressionEncryptionForSelectedFormat() {
        guard !selectedFormat.supportsEncryptedCompression else {
            return
        }

        disableCompressionEncryption()
    }

    private func refreshArchivePreview(preservingSelection preservedSelection: Set<String> = []) {
        previewTask?.cancel()
        archiveEntries.removeAll()
        selectedArchiveEntryPaths = preservedSelection

        guard mode == .extract else {
            selectedArchiveEntryPaths.removeAll()
            previewState = "归档预览"
            return
        }

        guard selectedItems.count == 1, let archiveURL = selectedItems.first else {
            selectedArchiveEntryPaths.removeAll()
            previewState = selectedItems.isEmpty ? "未选择归档" : "一次只能预览一个归档"
            return
        }

        previewState = "正在加载归档"
        let selectedEntryPaths = selectedArchiveEntryPaths
        previewTask = Task.detached { [weak self] in
            do {
                let entries = try await ArchiveService.makeDefault().listEntries(in: archiveURL)
                let rows = entries.map(ArchiveEntryRow.init)

                await self?.applyArchivePreviewRows(
                    rows,
                    preservingSelection: selectedEntryPaths
                )
            } catch {
                await self?.failArchivePreview()
            }
        }
    }

    private func applyArchivePreviewRows(
        _ rows: [ArchiveEntryRow],
        preservingSelection selectedEntryPaths: Set<String>
    ) {
        archiveEntries = rows
        if !selectedEntryPaths.isEmpty {
            let selectablePaths = Set(rows.filter(\.canSelectForExtraction).map(\.path))
            selectedArchiveEntryPaths = selectedEntryPaths.intersection(selectablePaths)
        }
        previewState = rows.isEmpty ? "归档为空" : "\(rows.count) 个条目"
    }

    private func failArchivePreview() {
        archiveEntries = []
        selectedArchiveEntryPaths.removeAll()
        previewState = "预览不可用"
    }

    private func apply(_ progress: ArchiveProgress) {
        if let total = progress.totalUnitCount, total > 0 {
            progressFraction = min(max(Double(progress.completedUnitCount) / Double(total), 0), 1)
            let completedText = ByteCountFormatter.string(
                fromByteCount: progress.completedUnitCount,
                countStyle: .file
            )
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            progressText = "\(completedText) / \(totalText)"
        } else {
            progressFraction = 0
            progressText = progress.currentEntryPath ?? "正在处理"
        }

        updateActiveQueuedTaskProgress()
    }

    private func finishOperation(_ result: TaskResult) {
        let queuedTaskID = activeQueuedTaskID
        isRunning = false
        conflictPrompt = nil
        conflictDecisionCoordinator = nil
        clearExtractionPassword()
        disableCompressionEncryption()
        progressFraction = 1
        progressText = result.title
        taskResult = result
        finishQueuedTask(id: queuedTaskID, status: .succeeded, result: result)
        recordRecentTask(result)
        if settings.taskCompletionNotificationEnabled {
            TaskCompletionNotifier.send(result)
        }
        refreshArchivePreview()
        startNextQueuedTaskIfPossible()
    }

    private func cancelOperationResult(queuedTaskID: UUID? = nil) {
        let queuedTaskID = queuedTaskID ?? activeQueuedTaskID
        let shouldContinueQueue = shouldContinueQueueAfterCancellation
        shouldContinueQueueAfterCancellation = true
        isRunning = false
        conflictPrompt = nil
        conflictDecisionCoordinator = nil
        clearExtractionPassword()
        disableCompressionEncryption()
        progressText = "已取消"
        let result = TaskResult(
            title: "已取消",
            detail: "任务没有完成",
            outputURL: nil,
            iconName: "xmark.circle"
        )
        taskResult = result
        finishQueuedTask(id: queuedTaskID, status: .cancelled, result: result)
        recordRecentTask(result)
        refreshArchivePreview()
        if shouldContinueQueue {
            startNextQueuedTaskIfPossible()
        }
    }

    private func failOperation(_ error: Error, queuedTaskID: UUID? = nil) {
        let queuedTaskID = queuedTaskID ?? activeQueuedTaskID
        isRunning = false
        conflictPrompt = nil
        conflictDecisionCoordinator = nil

        if requestExtractionPasswordIfNeeded(for: error) {
            if let queuedTaskID {
                passwordRetryQueuedTaskID = queuedTaskID
                updateQueuedTask(id: queuedTaskID) { task in
                    task.status = .waiting
                    task.progressFraction = 0
                    task.progressText = progressText
                    task.result = taskResult
                    task.completedAt = nil
                    task.snapshot = task.snapshot.withoutPasswords()
                }

                if activeQueuedTaskID == queuedTaskID {
                    activeQueuedTaskID = nil
                }
            }
            return
        }

        clearExtractionPassword()
        disableCompressionEncryption()
        progressText = "失败"
        let message = ArchiveErrorMessageFormatter.message(for: error)
        let result = TaskResult(
            title: "操作失败",
            detail: message,
            outputURL: nil,
            iconName: "exclamationmark.triangle"
        )
        taskResult = result
        finishQueuedTask(id: queuedTaskID, status: .failed, result: result)
        recordRecentTask(result)
        alert = AppAlert(title: "操作失败", message: message)
        startNextQueuedTaskIfPossible()
    }

    private func requestExtractionPasswordIfNeeded(for error: Error) -> Bool {
        guard mode == .extract,
              selectedItems.count == 1,
              let archiveURL = selectedItems.first,
              let archiveError = error as? ArchiveError else {
            return false
        }

        let isRetry: Bool
        switch archiveError {
        case .encryptedArchive:
            isRetry = false
        case .incorrectArchivePassword:
            isRetry = true
        default:
            return false
        }

        extractionPassword = nil
        passwordPrompt = ArchivePasswordPrompt(archiveURL: archiveURL, isRetry: isRetry)
        progressFraction = 0
        progressText = isRetry ? "等待重新输入密码" : "等待输入密码"
        taskResult = TaskResult(
            title: isRetry ? "密码不正确" : "需要密码",
            detail: isRetry ? "请重新输入归档密码" : "请输入密码后继续解压",
            outputURL: nil,
            iconName: "lock"
        )

        return true
    }

    private func recordRecentTask(_ result: TaskResult) {
        let task = RecentArchiveTask(result: result)
        recentTasks.insert(task, at: 0)
        recentTasks = Array(recentTasks.prefix(RecentArchiveStore.maxTaskCount))
        RecentArchiveStore.saveTasks(recentTasks)

        if let outputURL = result.outputURL {
            recordRecentOutputDirectory(outputDirectory(for: outputURL))
        }
    }

    private func recordRecentOutputDirectory(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let existingDirectory = recentOutputDirectories.first {
            $0.url.standardizedFileURL.path == standardizedURL.path
        }
        let directory = RecentOutputDirectory(
            url: standardizedURL,
            isPinned: existingDirectory?.isPinned ?? false
        )

        recentOutputDirectories.removeAll { $0.id == directory.id }
        recentOutputDirectories.insert(directory, at: 0)
        recentOutputDirectories = RecentArchiveStore.sortedVisibleOutputDirectories(
            recentOutputDirectories
        )
        RecentArchiveStore.saveOutputDirectories(recentOutputDirectories)
    }

    private func outputDirectory(for outputURL: URL) -> URL {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return outputURL
        }

        return outputURL.deletingLastPathComponent()
    }

}
