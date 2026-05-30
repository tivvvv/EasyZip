import Foundation

/// EasyZip 核心层错误.
public enum ArchiveError: Error, Equatable, Sendable {
    case unsupportedFormat(String)
    case unsupportedOperation(format: ArchiveFormat, operation: ArchiveOperation)
    case invalidSource(URL)
    case invalidDestination(URL)
    case encryptedArchive(URL)
    case unsafeEntryPath(String)
    case engineFailure(engine: String, message: String)
    case cancelled
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
        case .unsafeEntryPath(let path):
            "Unsafe archive entry path: \(path)"
        case .engineFailure(let engine, let message):
            "Archive engine \(engine) failed: \(message)"
        case .cancelled:
            "Archive task cancelled"
        }
    }
}
