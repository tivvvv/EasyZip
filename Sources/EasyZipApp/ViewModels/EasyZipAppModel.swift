import AppKit
import EasyZipCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EasyZipAppModel: ObservableObject {
    @Published var mode: WorkspaceMode = .compress {
        didSet {
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
            resetProgressIfIdle()
            refreshExternalToolAvailability()
        }
    }
    @Published var overwritePolicy: OverwritePolicy = .rename
    @Published var archiveName = "归档文件"
    @Published var includeHiddenFiles = false
    @Published var preserveParentDirectory = true
    @Published var preserveMetadata = true
    @Published var archiveEntries: [ArchiveEntryRow] = []
    @Published var previewState = "未选择归档"
    @Published var progressFraction = 0.0
    @Published var progressText = "空闲"
    @Published var isRunning = false
    @Published var isDropTargeted = false
    @Published var taskResult: TaskResult?
    @Published private(set) var rarCommandAvailability = RARCommandResolver().availability()
    @Published private(set) var recentTasks = RecentArchiveStore.loadTasks()
    @Published private(set) var recentOutputDirectories = RecentArchiveStore.loadOutputDirectories()
    @Published var alert: AppAlert?

    private var operationTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private let rarCommandResolver = RARCommandResolver()

    var primaryActionTitle: String {
        mode == .compress ? "开始压缩" : "开始解压"
    }

    var canRun: Bool {
        !selectedItems.isEmpty && !isRunning
    }

    var formatRequirementStatus: (title: String, detail: String, iconName: String, isBlocking: Bool)? {
        guard requiresRARCommand else {
            return nil
        }

        if let executableURL = rarCommandAvailability.executableURL {
            return (
                title: "RAR 命令可用",
                detail: executableURL.path,
                iconName: "checkmark.circle",
                isBlocking: false
            )
        }

        return (
            title: "需要安装 rar 命令",
            detail: "安装 RAR 命令行工具后可创建 .rar 归档",
            iconName: "exclamationmark.triangle",
            isBlocking: true
        )
    }

    var outputLabel: String {
        outputDirectory?.displayPath ?? "选择输出目录"
    }

    var archiveFileNamePreview: String {
        Self.compressionFileName(format: selectedFormat, archiveName: archiveName)
    }

    var canRevealOutput: Bool {
        revealTargetURL != nil
    }

    func chooseItems() {
        guard !isRunning else {
            return
        }

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
            return
        }

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

        let filteredURLs = urls.filter { url in
            if mode == .compress {
                return true
            }

            return ArchiveFormat.isSupportedArchiveFilename(url.lastPathComponent)
        }
        var mergedURLs = selectedItems

        for url in filteredURLs where !mergedURLs.contains(url) {
            mergedURLs.append(url)
        }

        selectedItems = mergedURLs
        resetProgressIfIdle()
        updateDefaultArchiveName()
        refreshArchivePreview()
    }

    func removeItem(_ url: URL) {
        guard !isRunning else {
            return
        }

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
        previewState = "未选择归档"
        resetProgressIfIdle()
        updateDefaultArchiveName()
    }

    func prepareExternalSelection(mode: WorkspaceMode, fileURLs: [URL]) {
        guard !isRunning else {
            alert = AppAlert(title: "任务进行中", message: "请等待当前任务完成后再添加文件")
            return
        }

        self.mode = mode
        selectedItems.removeAll()
        archiveEntries.removeAll()
        previewState = mode == .extract ? "未选择归档" : "归档预览"
        addFileURLs(fileURLs)

        if selectedItems.isEmpty {
            alert = AppAlert(title: "没有可处理的文件", message: "请选择支持的文件后重试")
        }
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
        let archiveName = archiveName
        let includeHiddenFiles = includeHiddenFiles
        let preserveParentDirectory = preserveParentDirectory
        let preserveMetadata = preserveMetadata

        operationTask = Task.detached { [weak self] in
            do {
                let result: TaskResult

                switch mode {
                case .compress:
                    result = try await Self.compress(
                        sourceURLs: selectedItems,
                        outputDirectory: outputDirectory,
                        format: selectedFormat,
                        archiveName: archiveName,
                        includeHiddenFiles: includeHiddenFiles,
                        preserveParentDirectory: preserveParentDirectory,
                        preserveMetadata: preserveMetadata,
                        progressHandler: { progress in
                            Task { @MainActor in
                                self?.apply(progress)
                            }
                        }
                    )
                case .extract:
                    result = try await Self.extract(
                        archiveURLs: selectedItems,
                        outputDirectory: outputDirectory,
                        overwritePolicy: overwritePolicy,
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
    }

    func revealOutputInFinder() {
        guard let revealTargetURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([revealTargetURL])
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

    private var requiresRARCommand: Bool {
        mode == .compress && selectedFormat == .rar
    }

    private var requiredExternalToolsAreAvailable: Bool {
        !requiresRARCommand || rarCommandAvailability.isAvailable
    }

    private func reportMissingRequiredExternalTool() {
        let message = userFacingErrorMessage(
            for: ArchiveError.externalToolUnavailable(RARCommandResolver.toolName)
        )

        taskResult = TaskResult(
            title: "RAR 压缩不可用",
            detail: message,
            outputURL: nil,
            iconName: "exclamationmark.triangle"
        )
        progressFraction = 0
        progressText = "等待外部工具"
        alert = AppAlert(title: "RAR 压缩不可用", message: message)
    }

    private func updateDefaultArchiveName() {
        guard mode == .compress else {
            return
        }

        if selectedItems.count == 1, let firstItem = selectedItems.first {
            archiveName = firstItem.deletingPathExtension().lastPathComponent
        } else if selectedItems.isEmpty {
            archiveName = "归档文件"
        } else {
            archiveName = "批量归档"
        }
    }

    private func resetProgressIfIdle() {
        guard !isRunning else {
            return
        }

        progressFraction = 0
        progressText = "空闲"
    }

    private func refreshArchivePreview() {
        previewTask?.cancel()
        archiveEntries.removeAll()

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
        progressFraction = 1
        progressText = result.title
        taskResult = result
        recordRecentTask(result)
        TaskCompletionNotifier.send(result)
        refreshArchivePreview()
    }

    private func cancelOperationResult() {
        isRunning = false
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
        progressText = "失败"
        let message = userFacingErrorMessage(for: error)
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
        recentOutputDirectories.removeAll { $0.standardizedFileURL.path == standardizedURL.path }
        recentOutputDirectories.insert(standardizedURL, at: 0)
        recentOutputDirectories = Array(
            recentOutputDirectories.prefix(RecentArchiveStore.maxOutputDirectoryCount)
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

    private static func compress(
        sourceURLs: [URL],
        outputDirectory: URL?,
        format: ArchiveFormat,
        archiveName: String,
        includeHiddenFiles: Bool,
        preserveParentDirectory: Bool,
        preserveMetadata: Bool,
        progressHandler: ArchiveProgressHandler?
    ) async throws -> TaskResult {
        let destinationURL = compressionDestinationURL(
            sourceURLs: sourceURLs,
            outputDirectory: outputDirectory,
            format: format,
            archiveName: archiveName
        )
        let request = CompressionRequest(
            sourceURLs: sourceURLs,
            destinationURL: destinationURL,
            format: format,
            options: CompressionOptions(
                includeHiddenFiles: includeHiddenFiles,
                preserveMetadata: preserveMetadata,
                preserveParentDirectory: preserveParentDirectory
            )
        )

        try await ArchiveService.makeDefault().create(request, progress: progressHandler)

        return TaskResult(
            title: "压缩完成",
            detail: "已生成 \(destinationURL.lastPathComponent)",
            outputURL: destinationURL,
            iconName: "checkmark.circle"
        )
    }

    private static func extract(
        archiveURLs: [URL],
        outputDirectory: URL?,
        overwritePolicy: OverwritePolicy,
        progressHandler: ArchiveProgressHandler?
    ) async throws -> TaskResult {
        let service = ArchiveService.makeDefault()
        var destinationURLs: [URL] = []

        for archiveURL in archiveURLs {
            try Task.checkCancellation()

            let destinationURL = extractionDestinationURL(
                archiveURL: archiveURL,
                outputDirectory: outputDirectory
            )
            destinationURLs.append(destinationURL)

            let request = ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: baseDestinationURL(
                    archiveURL: archiveURL,
                    outputDirectory: outputDirectory
                ),
                options: ExtractionOptions(overwritePolicy: overwritePolicy)
            )

            try await service.extract(request, progress: progressHandler)
        }

        return TaskResult(
            title: "解压完成",
            detail: extractionResultDetail(archiveURLs: archiveURLs),
            outputURL: extractionRevealURL(
                archiveURLs: archiveURLs,
                destinationURLs: destinationURLs,
                outputDirectory: outputDirectory
            ),
            iconName: "checkmark.circle"
        )
    }

    private static func compressionDestinationURL(
        sourceURLs: [URL],
        outputDirectory: URL?,
        format: ArchiveFormat,
        archiveName: String
    ) -> URL {
        let directoryURL = outputDirectory
            ?? sourceURLs.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        let fileName = compressionFileName(format: format, archiveName: archiveName)

        return directoryURL.appendingPathComponent(fileName)
    }

    private static func compressionFileName(format: ArchiveFormat, archiveName: String) -> String {
        let cleanName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "归档文件" : cleanName
        let normalizedBaseName = baseName.lowercased()

        if format.fileExtensions.contains(where: { normalizedBaseName.hasSuffix(".\($0)") }) {
            return baseName
        }

        return "\(baseName).\(format.fileExtension)"
    }

    private static func extractionDestinationURL(
        archiveURL: URL,
        outputDirectory: URL?
    ) -> URL {
        let baseDirectory = baseDestinationURL(archiveURL: archiveURL, outputDirectory: outputDirectory)
        let directoryName = extractionContainingDirectoryName(for: archiveURL)

        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func extractionContainingDirectoryName(for archiveURL: URL) -> String {
        let directoryName = ArchiveFormat.removingArchiveExtension(from: archiveURL.lastPathComponent)

        return directoryName.isEmpty ? "归档内容" : directoryName
    }

    private static func baseDestinationURL(
        archiveURL: URL,
        outputDirectory: URL?
    ) -> URL {
        outputDirectory ?? archiveURL.deletingLastPathComponent()
    }

    private static func extractionResultDetail(archiveURLs: [URL]) -> String {
        guard archiveURLs.count == 1, let archiveURL = archiveURLs.first else {
            return "已处理 \(archiveURLs.count) 个归档"
        }

        return "已解压 \(archiveURL.lastPathComponent)"
    }

    private static func extractionRevealURL(
        archiveURLs: [URL],
        destinationURLs: [URL],
        outputDirectory: URL?
    ) -> URL? {
        if archiveURLs.count == 1 {
            return destinationURLs.first
        }

        if let outputDirectory {
            return outputDirectory
        }

        return archiveURLs.first?.deletingLastPathComponent()
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        guard let archiveError = error as? ArchiveError else {
            return "操作未完成, 请检查文件和输出目录"
        }

        switch archiveError {
        case .unsupportedFormat(let value):
            return "暂不支持该归档格式: \(value)"
        case .unsupportedOperation(let format, _):
            return "该格式暂不支持当前操作: .\(format.fileExtension)"
        case .invalidSource(let url):
            return "源文件无效: \(url.path)"
        case .invalidDestination(let url):
            return "输出位置无效: \(url.path)"
        case .encryptedArchive(let url):
            return "暂不支持加密归档: \(url.path)"
        case .externalToolUnavailable(let toolName):
            return "未找到外部工具: \(toolName), RAR 压缩需要安装 RAR 命令行工具"
        case .conflictRequiresDecision(let url):
            return "目标已存在, 需要选择冲突处理方式: \(url.path)"
        case .unsupportedEntryType(let path, let type):
            return "归档内包含暂不支持的条目类型: \(type), \(path)"
        case .unsafeEntryPath(let path):
            return "归档内包含不安全路径: \(path)"
        case .extractionResourceLimitExceeded(let violation):
            return Self.resourceLimitErrorMessage(for: violation)
        case .engineFailure:
            return "归档引擎执行失败"
        case .cancelled:
            return "任务已取消"
        }
    }

    private static func resourceLimitErrorMessage(
        for violation: ExtractionResourceLimitViolation
    ) -> String {
        switch violation {
        case .entryCount(let limit, let actual):
            return "归档条目数量过多: \(actual), 最大允许 \(limit)"
        case .totalUncompressedSize(let limit, let actual):
            return "归档解压后体积过大: \(formatByteCount(actual)), 最大允许 \(formatByteCount(limit))"
        case .singleFileUncompressedSize(let path, let limit, let actual):
            return "归档内单个文件过大: \(path), \(formatByteCount(actual)), 最大允许 \(formatByteCount(limit))"
        case .directoryDepth(let path, let limit, let actual):
            return "归档目录层级过深: \(path), 当前 \(actual), 最大允许 \(limit)"
        }
    }

    private static func formatByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
