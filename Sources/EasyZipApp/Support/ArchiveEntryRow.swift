import EasyZipCore
import Foundation

struct ArchiveEntryRow: Identifiable, Sendable {
    let id: String
    let path: String
    let name: String
    let parentPath: String
    let detail: String
    let kind: ArchiveEntryKind
    let kindTitle: String
    let linkTarget: String?
    let uncompressedSize: Int64?
    let modifiedAt: Date?
    let modifiedText: String
    let depth: Int
    let risk: ArchiveEntryRisk?

    init(entry: ArchiveEntry) {
        id = entry.path
        path = entry.path
        let pathComponents = entry.path.split(separator: "/").map(String.init)
        name = pathComponents.last ?? entry.path
        parentPath = pathComponents.dropLast().joined(separator: "/")
        kind = entry.kind
        linkTarget = entry.kind.linkTarget
        uncompressedSize = entry.uncompressedSize
        modifiedAt = entry.modifiedAt
        modifiedText = entry.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "-"
        depth = max(pathComponents.count - 1, 0)
        kindTitle = entry.kind.displayTitle
        risk = ArchiveEntryRisk(kind: entry.kind)

        if let size = entry.uncompressedSize {
            detail = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            detail = "-"
        }
    }

    var searchText: String {
        [
            path,
            name,
            parentPath,
            kindTitle,
            linkTarget,
            risk?.title
        ]
            .compactMap(\.self)
            .joined(separator: " ")
            .lowercased()
    }

    var typeSortOrder: Int {
        kind.sortOrder
    }

    var riskSortOrder: Int {
        risk?.sortOrder ?? 0
    }

    var isFile: Bool {
        if case .file = kind {
            return true
        }

        return false
    }

    var isDirectory: Bool {
        if case .directory = kind {
            return true
        }

        return false
    }

    var canSelectForExtraction: Bool {
        switch kind {
        case .file, .directory, .symbolicLink:
            true
        case .hardLink, .other:
            false
        }
    }

    var selectionDisabledReason: String? {
        guard !canSelectForExtraction else {
            return nil
        }

        return "此条目类型不能解压"
    }

    func matches(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return true
        }

        return searchText.contains(trimmedQuery.lowercased())
    }
}

struct ArchiveEntryRisk: Equatable, Sendable {
    let title: String
    let detail: String
    let iconName: String
    let sortOrder: Int

    init?(kind: ArchiveEntryKind) {
        switch kind {
        case .symbolicLink(let target):
            title = "链接"
            detail = target.map { "符号链接 -> \($0)" } ?? "符号链接"
            iconName = "link"
            sortOrder = 1
        case .hardLink(let target):
            title = "高风险"
            detail = target.map { "硬链接 -> \($0)" } ?? "硬链接"
            iconName = "exclamationmark.triangle"
            sortOrder = 2
        case .other:
            title = "高风险"
            detail = "特殊条目"
            iconName = "exclamationmark.triangle"
            sortOrder = 3
        case .file, .directory:
            return nil
        }
    }
}

private extension ArchiveEntryKind {
    var displayTitle: String {
        switch self {
        case .file:
            "文件"
        case .directory:
            "目录"
        case .symbolicLink:
            "符号链接"
        case .hardLink:
            "硬链接"
        case .other:
            "其他"
        }
    }

    var linkTarget: String? {
        switch self {
        case .symbolicLink(let target), .hardLink(let target):
            target
        case .file, .directory, .other:
            nil
        }
    }

    var sortOrder: Int {
        switch self {
        case .directory:
            0
        case .file:
            1
        case .symbolicLink:
            2
        case .hardLink:
            3
        case .other:
            4
        }
    }
}
