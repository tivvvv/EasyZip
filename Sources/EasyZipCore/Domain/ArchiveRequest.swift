import Foundation

/// 解压请求.
public struct ExtractionRequest: Sendable {
    public let archiveURL: URL
    public let destinationURL: URL
    public let options: ExtractionOptions

    public init(
        archiveURL: URL,
        destinationURL: URL,
        options: ExtractionOptions = .init()
    ) {
        self.archiveURL = archiveURL
        self.destinationURL = destinationURL
        self.options = options
    }
}

/// 解压选项.
public struct ExtractionOptions: Sendable {
    public let overwritePolicy: OverwritePolicy
    public let shouldCreateContainingDirectory: Bool
    public let preservePermissions: Bool
    public let validateEntryPaths: Bool
    public let conflictResolver: ArchiveConflictResolver?

    public init(
        overwritePolicy: OverwritePolicy = .ask,
        shouldCreateContainingDirectory: Bool = true,
        preservePermissions: Bool = true,
        validateEntryPaths: Bool = true,
        conflictResolver: ArchiveConflictResolver? = nil
    ) {
        self.overwritePolicy = overwritePolicy
        self.shouldCreateContainingDirectory = shouldCreateContainingDirectory
        self.preservePermissions = preservePermissions
        self.validateEntryPaths = validateEntryPaths
        self.conflictResolver = conflictResolver
    }
}

/// 压缩请求.
public struct CompressionRequest: Equatable, Sendable {
    public let sourceURLs: [URL]
    public let destinationURL: URL
    public let format: ArchiveFormat
    public let options: CompressionOptions

    public init(
        sourceURLs: [URL],
        destinationURL: URL,
        format: ArchiveFormat,
        options: CompressionOptions = .init()
    ) {
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.format = format
        self.options = options
    }
}

/// 压缩选项.
public struct CompressionOptions: Equatable, Sendable {
    public let compressionLevel: CompressionLevel
    public let includeHiddenFiles: Bool
    public let preserveMetadata: Bool
    public let preserveParentDirectory: Bool

    public init(
        compressionLevel: CompressionLevel = .balanced,
        includeHiddenFiles: Bool = false,
        preserveMetadata: Bool = true,
        preserveParentDirectory: Bool = true
    ) {
        self.compressionLevel = compressionLevel
        self.includeHiddenFiles = includeHiddenFiles
        self.preserveMetadata = preserveMetadata
        self.preserveParentDirectory = preserveParentDirectory
    }
}

/// 覆盖策略.
public enum OverwritePolicy: Equatable, Sendable {
    case ask
    case skip
    case overwrite
    case rename
}

/// 表示解压目标已存在时的冲突信息.
public struct ArchiveConflict: Equatable, Sendable {
    public let entryPath: String
    public let destinationURL: URL
    public let existingItemIsDirectory: Bool
    public let incomingItemIsDirectory: Bool

    public init(
        entryPath: String,
        destinationURL: URL,
        existingItemIsDirectory: Bool,
        incomingItemIsDirectory: Bool
    ) {
        self.entryPath = entryPath
        self.destinationURL = destinationURL
        self.existingItemIsDirectory = existingItemIsDirectory
        self.incomingItemIsDirectory = incomingItemIsDirectory
    }
}

public typealias ArchiveConflictResolver = @Sendable (ArchiveConflict) -> OverwritePolicy

/// 压缩等级.
public enum CompressionLevel: Equatable, Sendable {
    case fastest
    case balanced
    case maximum
    case custom(Int)
}
