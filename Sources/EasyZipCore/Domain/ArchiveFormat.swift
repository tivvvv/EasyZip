/// EasyZip 支持的归档格式.
public enum ArchiveFormat: CaseIterable, Hashable, Sendable {
    case zip
    case sevenZip
    case tar
    case tarGzip
    case tarBzip2
    case tarXz

    public var fileExtension: String {
        fileExtensions[0]
    }

    public var fileExtensions: [String] {
        switch self {
        case .zip:
            ["zip"]
        case .sevenZip:
            ["7z"]
        case .tar:
            ["tar"]
        case .tarGzip:
            ["tar.gz", "tgz"]
        case .tarBzip2:
            ["tar.bz2", "tbz2", "tbz"]
        case .tarXz:
            ["tar.xz", "txz"]
        }
    }

    public var displayName: String {
        switch self {
        case .zip:
            "ZIP"
        case .sevenZip:
            "7z"
        case .tar:
            "TAR"
        case .tarGzip:
            "TAR.GZ"
        case .tarBzip2:
            "TAR.BZ2"
        case .tarXz:
            "TAR.XZ"
        }
    }

    public var displayExtension: String {
        ".\(fileExtension)"
    }

    public static var supportedFileExtensions: [String] {
        allCases.flatMap(\.fileExtensions)
    }

    public static var supportedPathExtensions: [String] {
        let extensions = supportedFileExtensions.compactMap { fileExtension in
            fileExtension.split(separator: ".").last.map(String.init)
        }

        return Array(Set(extensions)).sorted()
    }

    public static func matching(filename: String) -> ArchiveFormat? {
        let normalizedFilename = filename.lowercased()

        return allCases.first { format in
            format.fileExtensions.contains { fileExtension in
                normalizedFilename.hasSuffix(".\(fileExtension)")
            }
        }
    }

    public static func isSupportedArchiveFilename(_ filename: String) -> Bool {
        matching(filename: filename) != nil
    }

    public static func removingArchiveExtension(from filename: String) -> String {
        guard let format = matching(filename: filename) else {
            return filename
        }

        let normalizedFilename = filename.lowercased()
        guard let matchedExtension = format.fileExtensions.first(where: { fileExtension in
            normalizedFilename.hasSuffix(".\(fileExtension)")
        }) else {
            return filename
        }

        return String(filename.dropLast(matchedExtension.count + 1))
    }
}

/// 归档操作类型.
public enum ArchiveOperation: String, Hashable, Sendable {
    case list
    case extract
    case create
}
