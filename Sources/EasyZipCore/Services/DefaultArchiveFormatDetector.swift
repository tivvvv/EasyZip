import Foundation

/// 默认格式识别器.
public struct DefaultArchiveFormatDetector: ArchiveFormatDetecting {
    public init() {}

    public func detectFormat(for archiveURL: URL) throws -> ArchiveFormat {
        let ext = archiveURL.pathExtension.lowercased()

        switch ext {
        case "zip":
            return .zip
        case "7z":
            return .sevenZip
        default:
            throw ArchiveError.unsupportedFormat(ext)
        }
    }
}
