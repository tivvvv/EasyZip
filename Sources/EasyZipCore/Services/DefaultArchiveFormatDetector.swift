import Foundation

/// 默认格式识别器.
public struct DefaultArchiveFormatDetector: ArchiveFormatDetecting {
    public init() {}

    public func detectFormat(for archiveURL: URL) throws -> ArchiveFormat {
        if let format = ArchiveFormat.matching(filename: archiveURL.lastPathComponent) {
            return format
        }

        let ext = archiveURL.pathExtension.lowercased()
        let unsupportedValue = ext.isEmpty ? archiveURL.lastPathComponent : ext

        throw ArchiveError.unsupportedFormat(unsupportedValue)
    }
}
