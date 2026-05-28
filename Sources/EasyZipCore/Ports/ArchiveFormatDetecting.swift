import Foundation

/// 归档格式识别协议.
public protocol ArchiveFormatDetecting: Sendable {
    func detectFormat(for archiveURL: URL) throws -> ArchiveFormat
}
