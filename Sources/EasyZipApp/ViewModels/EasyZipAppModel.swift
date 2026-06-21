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
    @Published private(set) var rarCommandAvailability = RARCommandResolver().availability()
    @Published private(set) var zstdCommandAvailability = ZstdCommandResolver().availability()
    @Published private(set) var recentTasks = RecentArchiveStore.loadTasks()
    @Published private(set) var recentOutputDirectories = RecentArchiveStore.loadOutputDirectories()
    @Published private(set) var pendingExternalSelection: PendingExternalSelection?
    @Published var passwordPrompt: ArchivePasswordPrompt?
    @Published var alert: AppAlert?

    private var operationTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private let settings: EasyZipAppSettings
    private let rarCommandResolver: RARCommandResolver
    private let zstdCommandResolver: ZstdCommandResolver
    private var settingsCancellables: Set<AnyCancellable> = []
    private var extractionPassword: String?

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
        guard !isRunning else {
            noteSelectionBlocked(mode: mode)
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = mode == .compress ? "选择要压缩的项目" : "选择要解压的归档"
        panel.message = mode == .compress ? "可以选择文件或文件夹" : "请选择支持的归档文件"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = mode == .compress
        panel.allowedContentTypes = mode == .extract
            ? ArchiveFormat.supportedPathExtensions.compactMap { UTType(filenameExtension: $0) }
            : []

        if panel.runModal() == .OK {
            addFileURLs(panel.urls)
        }
    }

    func chooseOutputDirectory() {
        guard !isRunning else {
            alert = AppAlert(title: "任务进行中", message: "当前任务完成后再调整输出目录")
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.message = "任务结果将保存到这里"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            recordRecentOutputDirectory(url)
        }
    }

    func addFileURLs(_ urls: [URL]) {
        guard !isRunning else {
            return
        }

        clearExtractionPassword()
        let filteredURLs = urls.filter { url in
            if mode == .compress {
                return true
            }

            return ArchiveFormat.isSupportedArchiveFilename(url.lastPathComponent)
        }
        selectedItems = FileURLListNormalizer.uniqueStandardizedFileURLs(selectedItems + filteredURLs)
        resetProgressIfIdle()
        updateDefaultArchiveName()
        refreshArchivePreview()
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
        let acceptedFileURLs = acceptableFileURLs(fileURLs, for: mode)

        guard !acceptedFileURLs.isEmpty else {
            alert = AppAlert(title: "没有可处理的文件", message: "请选择支持的文件后重试")
            return
        }

        guard !isRunning else {
            deferExternalSelection(mode: mode, fileURLs: acceptedFileURLs)
            return
        }

        applyExternalSelection(mode: mode, fileURLs: acceptedFileURLs)
    }

    func applyPendingExternalSelection() {
        guard let pendingExternalSelection, !isRunning else {
            return
        }

        self.pendingExternalSelection = nil
        applyExternalSelection(
            mode: pendingExternalSelection.mode,
            fileURLs: pendingExternalSelection.fileURLs
        )
    }

    func clearPendingExternalSelection() {
        pendingExternalSelection = nil
    }

    func submitExtractionPassword(_ password: String) {
        guard !password.isEmpty else {
            return
        }

        extractionPassword = password
        passwordPrompt = nil
        startOperation()
    }

    func cancelExtractionPasswordPrompt() {
        clearExtractionPassword()
        progressText = "已取消"
        taskResult = TaskResult(
            title: "已取消",
            detail: "未输入归档密码",
            outputURL: nil,
            iconName: "xmark.circle"
        )
    }

    func noteSelectionBlocked(mode: WorkspaceMode) {
        alert = AppAlert(
            title: "任务进行中",
            message: "当前任务完成后再选择\(mode.rawValue)文件"
        )
    }

    private func applyExternalSelection(mode: WorkspaceMode, fileURLs: [URL]) {
        let shouldMerge = self.mode == mode && !selectedItems.isEmpty

        pendingExternalSelection = nil
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

    private func deferExternalSelection(mode: WorkspaceMode, fileURLs: [URL]) {
        let mergedFileURLs: [URL]

        if let pendingExternalSelection, pendingExternalSelection.mode == mode {
            mergedFileURLs = FileURLListNormalizer.uniqueStandardizedFileURLs(
                pendingExternalSelection.fileURLs + fileURLs
            )
        } else {
            mergedFileURLs = fileURLs
        }

        pendingExternalSelection = PendingExternalSelection(mode: mode, fileURLs: mergedFileURLs)
        alert = AppAlert(
            title: "已暂存新选择",
            message: "当前任务完成后可应用 \(mergedFileURLs.count) 项\(mode.rawValue)文件"
        )
    }

    private func acceptableFileURLs(_ urls: [URL], for mode: WorkspaceMode) -> [URL] {
        let filteredURLs = urls.filter { url in
            if mode == .compress {
                return true
            }

            return ArchiveFormat.isSupportedArchiveFilename(url.lastPathComponent)
        }

        return FileURLListNormalizer.uniqueStandardizedFileURLs(filteredURLs)
    }

    func startOperation() {
        guard canRun else {
            return
        }

        refreshExternalToolAvailability()

        guard requiredExternalToolsAreAvailable else {
            reportMissingRequiredExternalTool()
            return
        }

        guard compressionPasswordIsValid() else {
            return
        }

        isRunning = true
        progressFraction = 0
        progressText = mode == .compress ? "准备压缩" : "准备解压"
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
                        progressHandler: { progress in
                            Task { @MainActor in
                                self?.apply(progress)
                            }
                        }
                    )
                }

                await self?.finishOperation(result)
            } catch is CancellationError {
                await self?.cancelOperationResult()
            } catch {
                await self?.failOperation(error)
            }
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
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

    private func normalizeCompressionEncryptionForSelectedFormat() {
        guard !selectedFormat.supportsEncryptedCompression else {
            return
        }

        disableCompressionEncryption()
    }

    private func refreshArchivePreview() {
        previewTask?.cancel()
        archiveEntries.removeAll()
        selectedArchiveEntryPaths.removeAll()

        guard mode == .extract else {
            previewState = "归档预览"
            return
        }

        guard selectedItems.count == 1, let archiveURL = selectedItems.first else {
            previewState = selectedItems.isEmpty ? "未选择归档" : "一次只能预览一个归档"
            return
        }

        previewState = "正在加载归档"
        previewTask = Task.detached { [weak self] in
            do {
                let entries = try await ArchiveService.makeDefault().listEntries(in: archiveURL)
                let rows = entries.map(ArchiveEntryRow.init)

                await MainActor.run {
                    self?.archiveEntries = rows
                    self?.previewState = rows.isEmpty ? "归档为空" : "\(rows.count) 个条目"
                }
            } catch {
                await MainActor.run {
                    self?.archiveEntries = []
                    self?.previewState = "预览不可用"
                }
            }
        }
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
    }

    private func finishOperation(_ result: TaskResult) {
        isRunning = false
        clearExtractionPassword()
        disableCompressionEncryption()
        progressFraction = 1
        progressText = result.title
        taskResult = result
        recordRecentTask(result)
        if settings.taskCompletionNotificationEnabled {
            TaskCompletionNotifier.send(result)
        }
        refreshArchivePreview()
    }

    private func cancelOperationResult() {
        isRunning = false
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
        recordRecentTask(result)
        refreshArchivePreview()
    }

    private func failOperation(_ error: Error) {
        isRunning = false

        if requestExtractionPasswordIfNeeded(for: error) {
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
        recordRecentTask(result)
        alert = AppAlert(title: "操作失败", message: message)
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
