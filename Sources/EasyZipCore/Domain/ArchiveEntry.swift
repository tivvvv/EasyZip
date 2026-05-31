import Foundation

/// 表示归档内的一个条目.
public struct ArchiveEntry: Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let kind: ArchiveEntryKind
    public let uncompressedSize: Int64?
    public let compressedSize: Int64?
    public let modifiedAt: Date?
    public let permissions: UInt16?

    public init(
        path: String,
        kind: ArchiveEntryKind,
        uncompressedSize: Int64? = nil,
        compressedSize: Int64? = nil,
        modifiedAt: Date? = nil,
        permissions: UInt16? = nil
    ) {
        self.id = path
        self.path = path
        self.kind = kind
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.modifiedAt = modifiedAt
        self.permissions = permissions
    }
}

/// 表示归档条目的类型.
public enum ArchiveEntryKind: Equatable, Sendable {
    case file
    case directory
    case symbolicLink(target: String?)
    case hardLink(target: String?)
    case other
}
