import Foundation

/// EasyZip 核心层错误.
public enum ArchiveError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case unsupportedOperation(format: ArchiveFormat, operation: ArchiveOperation)
    case invalidSource(URL)
    case invalidDestination(URL)
    case encryptedArchive(URL)
    case externalToolUnavailable(String)
    case conflictRequiresDecision(URL)
    case unsupportedEntryType(path: String, type: String)
    case unsafeEntryPath(String)
    case extractionResourceLimitExceeded(ExtractionResourceLimitViolation)
    case engineFailure(engine: String, message: String)
    case cancelled
}

/// 解压资源限制违规详情.
public enum ExtractionResourceLimitViolation: Equatable, Sendable {
    case entryCount(limit: Int, actual: Int)
    case totalUncompressedSize(limit: Int64, actual: Int64)
    case singleFileUncompressedSize(path: String, limit: Int64, actual: Int64)
    case directoryDepth(path: String, limit: Int, actual: Int)
}

extension ArchiveError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedFormat(let value):
            "Unsupported archive format: \(value)"
        case .unsupportedOperation(let format, let operation):
            "Unsupported operation \(operation.rawValue) for format \(format.fileExtension)"
        case .invalidSource(let url):
            "Invalid source: \(url.path)"
        case .invalidDestination(let url):
            "Invalid destination: \(url.path)"
        case .encryptedArchive(let url):
            "Encrypted archive is not supported: \(url.path)"
        case .externalToolUnavailable(let toolName):
            "External archive tool is unavailable: \(toolName)"
        case .conflictRequiresDecision(let url):
            "Archive entry conflict requires a decision: \(url.path)"
        case .unsupportedEntryType(let path, let type):
            "Unsupported archive entry type \(type): \(path)"
        case .unsafeEntryPath(let path):
            "Unsafe archive entry path: \(path)"
        case .extractionResourceLimitExceeded(let violation):
            "Extraction resource limit exceeded: \(violation)"
        case .engineFailure(let engine, let message):
            "Archive engine \(engine) failed: \(message)"
        case .cancelled:
            "Archive task cancelled"
        }
    }
}
