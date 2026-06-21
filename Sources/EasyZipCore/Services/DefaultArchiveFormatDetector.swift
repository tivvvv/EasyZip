import Foundation

/// 默认格式识别器.
public struct DefaultArchiveFormatDetector: ArchiveFormatDetecting {
    public init() {}

    public func detectFormat(for archiveURL: URL) throws -> ArchiveFormat {
        if let format = try detectFormatByMagicNumber(for: archiveURL) {
            return format
        }

        if let format = ArchiveFormat.matching(filename: archiveURL.lastPathComponent) {
            return format
        }

        let ext = archiveURL.pathExtension.lowercased()
        let unsupportedValue = ext.isEmpty ? archiveURL.lastPathComponent : ext

        throw ArchiveError.unsupportedFormat(unsupportedValue)
    }

    private func detectFormatByMagicNumber(for archiveURL: URL) throws -> ArchiveFormat? {
        guard let data = try? headerData(for: archiveURL) else {
            return nil
        }

        if data.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
            || data.starts(with: [0x50, 0x4B, 0x07, 0x08]) {
            return .zip
        }

        if data.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            return .sevenZip
        }

        if data.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
            || data.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) {
            return .rar
        }

        if data.starts(with: [0x1F, 0x8B]) {
            return .tarGzip
        }

        if data.starts(with: [0x42, 0x5A, 0x68]) {
            return .tarBzip2
        }

        if data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            return .tarXz
        }

        if data.starts(with: [0x28, 0xB5, 0x2F, 0xFD]) {
            return .tarZstd
        }

        if data.count >= 262 {
            let marker = data[257..<262]
            if marker.elementsEqual([0x75, 0x73, 0x74, 0x61, 0x72]) {
                return .tar
            }
        }

        return nil
    }

    private func headerData(for archiveURL: URL) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: archiveURL)
        defer {
            try? fileHandle.close()
        }

        return try fileHandle.read(upToCount: 512) ?? Data()
    }
}
