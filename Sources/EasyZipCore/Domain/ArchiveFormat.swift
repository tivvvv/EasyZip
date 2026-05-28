/// EasyZip 第一期支持的归档格式.
public enum ArchiveFormat: Hashable, Sendable {
    case zip
    case sevenZip

    public var fileExtension: String {
        switch self {
        case .zip:
            "zip"
        case .sevenZip:
            "7z"
        }
    }

    public var displayName: String {
        switch self {
        case .zip:
            "ZIP"
        case .sevenZip:
            "7z"
        }
    }
}

/// 归档操作类型.
public enum ArchiveOperation: String, Hashable, Sendable {
    case list
    case extract
    case create
}
