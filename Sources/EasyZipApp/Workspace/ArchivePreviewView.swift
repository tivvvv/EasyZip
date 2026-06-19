import EasyZipCore
import SwiftUI

struct ArchivePreviewView: View {
    @ObservedObject var model: EasyZipAppModel
    @State private var searchText = ""
    @State private var sortField: ArchivePreviewSortField = .name
    @State private var sortDescending = false

    private var visibleRows: [ArchiveEntryRow] {
        sortedRows(model.archiveEntries.filter { $0.matches(searchText) })
    }

    private var visibleSelectableRows: [ArchiveEntryRow] {
        visibleRows.filter(\.canSelectForExtraction)
    }

    private var summary: ArchivePreviewSummary {
        ArchivePreviewSummary(rows: model.archiveEntries, visibleCount: visibleRows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.mode == .extract ? "归档预览" : "任务摘要")
                    .font(.headline)

                Spacer()

                Text(model.mode == .extract ? model.previewState : "\(model.selectedItems.count) 个项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.mode == .extract {
                if model.archiveEntries.isEmpty {
                    PreviewEmptyState(text: model.previewState)
                } else {
                    previewToolbar
                    previewSummary

                    if visibleRows.isEmpty {
                        PreviewEmptyState(text: "没有匹配条目")
                    } else {
                        previewTable
                    }
                }
            } else {
                CompressionSummaryView(model: model)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var previewToolbar: some View {
        HStack(spacing: 8) {
            TextField("搜索条目", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)

            Picker("排序", selection: $sortField) {
                ForEach(ArchivePreviewSortField.allCases) { field in
                    Text(field.title).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .labelsHidden()

            Button {
                sortDescending.toggle()
            } label: {
                Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
            }
            .help(sortDescending ? "降序" : "升序")

            Button {
                model.selectArchiveEntries(visibleRows)
            } label: {
                Image(systemName: "checkmark.square")
            }
            .disabled(visibleSelectableRows.isEmpty || model.isRunning)
            .help("选择当前结果")

            Button {
                model.clearArchiveEntrySelection()
            } label: {
                Image(systemName: "xmark.square")
            }
            .disabled(model.selectedArchiveEntryCount == 0 || model.isRunning)
            .help("清空选择")
        }
    }

    private var previewSummary: some View {
        HStack(spacing: 12) {
            SummaryBadge(title: "显示", value: "\(summary.visibleCount) / \(summary.totalCount)")
            SummaryBadge(title: "大小", value: summary.totalSizeText)

            if summary.riskCount > 0 {
                SummaryBadge(title: "风险", value: "\(summary.riskCount)")
                    .foregroundStyle(.orange)
            }

            if model.selectedArchiveEntryCount > 0 {
                SummaryBadge(
                    title: "已选",
                    value: "\(model.selectedArchiveEntryCount), \(model.selectedArchiveEntrySizeText)"
                )
                .foregroundStyle(.blue)
            }

            Spacer()
        }
        .font(.caption)
    }

    private var previewTable: some View {
        Table(visibleRows) {
            TableColumn("") { row in
                Toggle(
                    "",
                    isOn: Binding(
                        get: {
                            model.isArchiveEntrySelected(row)
                        },
                        set: { isSelected in
                            model.setArchiveEntrySelection(row, isSelected: isSelected)
                        }
                    )
                )
                .labelsHidden()
                .disabled(!row.canSelectForExtraction || model.isRunning)
                .help(row.selectionDisabledReason ?? "选择条目")
            }
            .width(36)

            TableColumn("名称") { row in
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: CGFloat(min(row.depth, 6) * 14))

                    Image(systemName: iconName(for: row.kind))
                        .foregroundStyle(iconColor(for: row.kind))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .lineLimit(1)

                        if !row.parentPath.isEmpty {
                            Text(row.parentPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let risk = row.risk {
                        Image(systemName: risk.iconName)
                            .foregroundStyle(risk.sortOrder == 1 ? .orange : .red)
                            .help(risk.detail)
                    }
                }
            }

            TableColumn("类型") { row in
                Text(row.kindTitle)
                    .foregroundStyle(.secondary)
            }
            .width(78)

            TableColumn("大小") { row in
                Text(row.detail)
                    .foregroundStyle(.secondary)
            }
            .width(90)

            TableColumn("修改时间") { row in
                Text(row.modifiedText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(130)

            TableColumn("标记") { row in
                if let risk = row.risk {
                    Text(risk.title)
                        .foregroundStyle(.orange)
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }
            }
            .width(70)
        }
    }

    private func iconName(for kind: ArchiveEntryKind) -> String {
        switch kind {
        case .directory:
            "folder"
        case .symbolicLink:
            "link"
        case .hardLink:
            "link.badge.plus"
        case .file:
            "doc"
        case .other:
            "questionmark.square"
        }
    }

    private func iconColor(for kind: ArchiveEntryKind) -> Color {
        switch kind {
        case .directory:
            .blue
        case .symbolicLink:
            .orange
        case .hardLink, .other:
            .red
        case .file:
            .secondary
        }
    }

    private func sortedRows(_ rows: [ArchiveEntryRow]) -> [ArchiveEntryRow] {
        rows.sorted { first, second in
            let result = compare(first, second)

            if result == .orderedSame {
                return first.path.localizedStandardCompare(second.path) == .orderedAscending
            }

            return sortDescending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private func compare(_ first: ArchiveEntryRow, _ second: ArchiveEntryRow) -> ComparisonResult {
        switch sortField {
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

    private func compare(_ first: Int, _ second: Int) -> ComparisonResult {
        if first == second {
            return .orderedSame
        }

        return first < second ? .orderedAscending : .orderedDescending
    }

    private func compare(_ first: Int64?, _ second: Int64?) -> ComparisonResult {
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

    private func compare(_ first: Date?, _ second: Date?) -> ComparisonResult {
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

private enum ArchivePreviewSortField: String, CaseIterable, Identifiable {
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

private struct ArchivePreviewSummary {
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

private struct SummaryBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .separatorColor).opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PreviewEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompressionSummaryView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummaryRow(title: "格式", value: model.selectedFormat.displayExtension)
            SummaryRow(title: "归档文件", value: model.archiveFileNamePreview)
            SummaryRow(title: "隐藏文件", value: model.includeHiddenFiles ? "包含" : "跳过")
            SummaryRow(title: "父目录", value: model.preserveParentDirectory ? "保留" : "不保留")

            Spacer()
        }
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.callout)
    }
}
