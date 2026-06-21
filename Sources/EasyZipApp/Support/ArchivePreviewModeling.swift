import Foundation

enum ArchivePreviewSortField: String, CaseIterable, Identifiable {
    case name
    case type
    case size
    case modifiedAt
    case risk

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .name:
            "名称"
        case .type:
            "类型"
        case .size:
            "大小"
        case .modifiedAt:
            "修改时间"
        case .risk:
            "标记"
        }
    }
}

struct ArchivePreviewSummary {
    let totalCount: Int
    let visibleCount: Int
    let riskCount: Int
    let totalSizeText: String

    init(rows: [ArchiveEntryRow], visibleCount: Int) {
        let totalSize = rows.reduce(Int64(0)) { partialResult, row in
            partialResult + max(row.uncompressedSize ?? 0, 0)
        }

        totalCount = rows.count
        self.visibleCount = visibleCount
        riskCount = rows.filter { $0.risk != nil }.count
        totalSizeText = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

enum ArchivePreviewSorter {
    static func sortedRows(
        _ rows: [ArchiveEntryRow],
        field: ArchivePreviewSortField,
        descending: Bool
    ) -> [ArchiveEntryRow] {
        rows.sorted { first, second in
            let result = compare(first, second, field: field)

            if result == .orderedSame {
                return first.path.localizedStandardCompare(second.path) == .orderedAscending
            }

            return descending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private static func compare(
        _ first: ArchiveEntryRow,
        _ second: ArchiveEntryRow,
        field: ArchivePreviewSortField
    ) -> ComparisonResult {
        switch field {
        case .name:
            first.path.localizedStandardCompare(second.path)
        case .type:
            compare(first.typeSortOrder, second.typeSortOrder)
        case .size:
            compare(first.uncompressedSize, second.uncompressedSize)
        case .modifiedAt:
            compare(first.modifiedAt, second.modifiedAt)
        case .risk:
            compare(first.riskSortOrder, second.riskSortOrder)
        }
    }

    private static func compare(_ first: Int, _ second: Int) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private static func compare(_ first: Int64?, _ second: Int64?) -> ComparisonResult {
        switch (first, second) {
        case let (first?, second?):
            if first == second {
                return .orderedSame
            }

            return first < second ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private static func compare(_ first: Date?, _ second: Date?) -> ComparisonResult {
        switch (first, second) {
        case let (first?, second?):
            if first == second {
                return .orderedSame
            }

            return first < second ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }
}
