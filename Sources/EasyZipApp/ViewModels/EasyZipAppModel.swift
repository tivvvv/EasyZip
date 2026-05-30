import AppKit
import EasyZipCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class EasyZipAppModel: ObservableObject {
    @Published var mode: WorkspaceMode = .compress {
        didSet {
            resetProgressIfIdle()
            refreshArchivePreview()
        }
    }
    @Published var selectedItems: [URL] = []
    @Published var outputDirectory: URL? {
        didSet {
            resetProgressIfIdle()
        }
    }
    @Published var selectedFormat: ArchiveFormat = .zip {
        didSet {
            resetProgressIfIdle()
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
    @Published var alert: AppAlert?

    private var operationTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    var primaryActionTitle: String {
        mode == .compress ? "开始压缩" : "开始解压"
    }

    var canRun: Bool {
        !selectedItems.isEmpty && !isRunning
    }

    var outputLabel: String {
        outputDirectory?.displayPath ?? "选择输出目录"
    }

    func chooseItems() {
        let panel = NSOpenPanel()
        panel.title = mode == .compress ? "选择要压缩的项目" : "选择要解压的归档"
        panel.message = mode == .compress ? "可以选择文件或文件夹" : "请选择 .zip 或 .7z 归档"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = mode == .compress
        panel.allowedContentTypes = mode == .extract ? [.zip, UTType(filenameExtension: "7z")].compactMap { $0 } : []

        if panel.runModal() == .OK {
            addFileURLs(panel.urls)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.message = "任务结果将保存到这里"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    func addFileURLs(_ urls: [URL]) {
        let filteredURLs = urls.filter { url in
            if mode == .compress {
                return true
            }

            return url.pathExtension.lowercased() == "zip" || url.pathExtension.lowercased() == "7z"
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
        selectedItems.removeAll { $0 == url }
        resetProgressIfIdle()
        updateDefaultArchiveName()
        refreshArchivePreview()
    }

    func clearItems() {
        selectedItems.removeAll()
        archiveEntries.removeAll()
        previewState = "未选择归档"
        resetProgressIfIdle()
        updateDefaultArchiveName()
    }

    func startOperation() {
        guard canRun else {
            return
        }

        isRunning = true
        progressFraction = 0
        progressText = mode == .compress ? "准备压缩" : "准备解压"

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
                switch mode {
                case .compress:
                    try await Self.compress(
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
                    try await Self.extract(
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

                await self?.finishOperation(message: "\(mode.rawValue)完成")
            } catch is CancellationError {
                await self?.finishOperation(message: "已取消")
            } catch {
                await self?.failOperation(error)
            }
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
    }

    func revealOutputInFinder() {
        guard let outputDirectory else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([outputDirectory])
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
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

    private func finishOperation(message: String) {
        isRunning = false
        progressFraction = 1
        progressText = message
        refreshArchivePreview()
    }

    private func failOperation(_ error: Error) {
        isRunning = false
        progressText = "失败"
        alert = AppAlert(title: "操作失败", message: userFacingErrorMessage(for: error))
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
    ) async throws {
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
    }

    private static func extract(
        archiveURLs: [URL],
        outputDirectory: URL?,
        overwritePolicy: OverwritePolicy,
        progressHandler: ArchiveProgressHandler?
    ) async throws {
        let service = ArchiveService.makeDefault()

        for archiveURL in archiveURLs {
            try Task.checkCancellation()

            let destinationURL = extractionDestinationURL(
                archiveURL: archiveURL,
                archiveCount: archiveURLs.count,
                outputDirectory: outputDirectory
            )
            let request = ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: destinationURL,
                options: ExtractionOptions(overwritePolicy: overwritePolicy)
            )

            try await service.extract(request, progress: progressHandler)
        }
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
        let cleanName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "归档文件" : cleanName
        let fileName = baseName.hasSuffix(".\(format.fileExtension)")
            ? baseName
            : "\(baseName).\(format.fileExtension)"

        return directoryURL.appendingPathComponent(fileName)
    }

    private static func extractionDestinationURL(
        archiveURL: URL,
        archiveCount: Int,
        outputDirectory: URL?
    ) -> URL {
        let baseDirectory = outputDirectory
            ?? archiveURL.deletingLastPathComponent()

        if archiveCount == 1 {
            return baseDirectory
        }

        return baseDirectory.appendingPathComponent(
            archiveURL.deletingPathExtension().lastPathComponent,
            isDirectory: true
        )
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
        case .unsafeEntryPath(let path):
            return "归档内包含不安全路径: \(path)"
        case .engineFailure:
            return "归档引擎执行失败"
        case .cancelled:
            return "任务已取消"
        }
    }
}
