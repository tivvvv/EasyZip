import EasyZipCore
import Foundation

enum ArchiveQueuedTaskStatus: String, Sendable {
    case running
    case waiting
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .running:
            "进行中"
        case .waiting:
            "等待处理"
        case .succeeded:
            "已完成"
        case .failed:
            "失败"
        case .cancelled:
            "已取消"
        }
    }

    var iconName: String {
        switch self {
        case .running:
            "clock.arrow.circlepath"
        case .waiting:
            "pause.circle"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        }
    }

    var allowsRetry: Bool {
        switch self {
        case .failed, .cancelled:
            true
        case .running, .waiting, .succeeded:
            false
        }
    }

    var allowsCancel: Bool {
        switch self {
        case .running, .waiting:
            true
        case .succeeded, .failed, .cancelled:
            false
        }
    }

    var isFinished: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            true
        case .running, .waiting:
            false
        }
    }
}

struct ArchiveTaskSnapshot: Sendable {
    let mode: WorkspaceMode
    let sourceURLs: [URL]
    var outputDirectory: URL?
    let requiresExplicitOutputDirectory: Bool
    let selectedFormat: ArchiveFormat
    let overwritePolicy: OverwritePolicy
    let archiveName: String
    let includeHiddenFiles: Bool
    let preserveParentDirectory: Bool
    let preserveMetadata: Bool
    let shouldCreateContainingDirectory: Bool
    let selectedEntryPaths: Set<String>
    let encryptCompression: Bool
    let compressionPassword: String?
    let extractionPassword: String?

    var title: String {
        switch mode {
        case .compress:
            "压缩 \(itemCountText)"
        case .extract:
            selectedEntryPaths.isEmpty ? "解压 \(itemCountText)" : "解压所选"
        }
    }

    var detail: String {
        switch mode {
        case .compress:
            "\(selectedFormat.displayExtension), \(archiveName)"
        case .extract:
            selectedEntryPaths.isEmpty ? itemNamesText : "\(selectedEntryPaths.count) 个条目"
        }
    }

    private var itemCountText: String {
        "\(sourceURLs.count) 项"
    }

    private var itemNamesText: String {
        guard sourceURLs.count == 1, let sourceURL = sourceURLs.first else {
            return itemCountText
        }

        return sourceURL.lastPathComponent
    }

    func withoutPasswords() -> ArchiveTaskSnapshot {
        ArchiveTaskSnapshot(
            mode: mode,
            sourceURLs: sourceURLs,
            outputDirectory: outputDirectory,
            requiresExplicitOutputDirectory: requiresExplicitOutputDirectory,
            selectedFormat: selectedFormat,
            overwritePolicy: overwritePolicy,
            archiveName: archiveName,
            includeHiddenFiles: includeHiddenFiles,
            preserveParentDirectory: preserveParentDirectory,
            preserveMetadata: preserveMetadata,
            shouldCreateContainingDirectory: shouldCreateContainingDirectory,
            selectedEntryPaths: selectedEntryPaths,
            encryptCompression: encryptCompression,
            compressionPassword: nil,
            extractionPassword: nil
        )
    }
}

struct ArchiveQueuedTask: Identifiable, Sendable {
    let id: UUID
    var snapshot: ArchiveTaskSnapshot
    var status: ArchiveQueuedTaskStatus
    var progressFraction: Double
    var progressText: String
    var result: TaskResult?
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        snapshot: ArchiveTaskSnapshot,
        status: ArchiveQueuedTaskStatus = .running,
        progressFraction: Double = 0,
        progressText: String,
        result: TaskResult? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.snapshot = snapshot
        self.status = status
        self.progressFraction = progressFraction
        self.progressText = progressText
        self.result = result
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var title: String {
        result?.title ?? snapshot.title
    }

    var detail: String {
        result?.detail ?? snapshot.detail
    }

    var outputURL: URL? {
        result?.outputURL
    }
}
