import EasyZipCore
import SwiftUI

struct ArchivePreviewView: View {
    @ObservedObject var model: EasyZipAppModel
    @State private var searchText = ""
    @State private var sortField: ArchivePreviewSortField = .name
    @State private var sortDescending = false
    @State private var focusedEntryPath: String?

    private var visibleRows: [ArchiveEntryRow] {
        sortedRows(model.archiveEntries.filter { $0.matches(searchText) })
    }

    private var visibleSelectableRows: [ArchiveEntryRow] {
        visibleRows.filter(\.canSelectForExtraction)
    }

    private var visibleFileRows: [ArchiveEntryRow] {
        visibleRows.filter(\.isFile)
    }

    private var visibleDirectoryRows: [ArchiveEntryRow] {
        visibleRows.filter(\.isDirectory)
    }

    private var visibleRiskRows: [ArchiveEntryRow] {
        visibleRows.filter { $0.risk != nil && $0.canSelectForExtraction }
    }

    private var focusedRow: ArchiveEntryRow? {
        if let focusedEntryPath,
           let row = model.archiveEntries.first(where: { $0.path == focusedEntryPath }) {
            return row
        }

        if let selectedPath = model.selectedArchiveEntryPaths.sorted().first {
            return model.archiveEntries.first { $0.path == selectedPath }
        }

        return nil
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
                        if let focusedRow {
                            Divider()
                            entryDetailPanel(focusedRow)
                        }
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

            Menu {
                Button {
                    model.replaceArchiveEntrySelection(with: visibleRows)
                } label: {
                    Label("选择当前结果", systemImage: "checkmark.square")
                }
                .disabled(visibleSelectableRows.isEmpty)

                Button {
                    model.selectArchiveEntries(visibleRows)
                } label: {
                    Label("追加当前结果", systemImage: "plus.square.on.square")
                }
                .disabled(visibleSelectableRows.isEmpty)

                Button {
                    model.invertArchiveEntrySelection(in: visibleRows)
                } label: {
                    Label("反选当前结果", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(visibleSelectableRows.isEmpty)

                Divider()

                Button {
                    model.replaceArchiveEntrySelectionWithFiles(in: visibleRows)
                } label: {
                    Label("只选文件", systemImage: "doc")
                }
                .disabled(visibleFileRows.isEmpty)

                Button {
                    model.replaceArchiveEntrySelectionWithDirectories(in: visibleRows)
                } label: {
                    Label("只选目录", systemImage: "folder")
                }
                .disabled(visibleDirectoryRows.isEmpty)

                Button {
                    model.replaceArchiveEntrySelectionWithRiskEntries(in: visibleRows)
                } label: {
                    Label("只选风险项", systemImage: "exclamationmark.triangle")
                }
                .disabled(visibleRiskRows.isEmpty)

                Divider()

                Button {
                    model.clearArchiveEntrySelection()
                } label: {
                    Label("清空选择", systemImage: "xmark.square")
                }
                .disabled(model.selectedArchiveEntryCount == 0)
            } label: {
                Label("选择", systemImage: "checklist")
            }
            .disabled(model.isRunning || (visibleSelectableRows.isEmpty && model.selectedArchiveEntryCount == 0))
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
                            focusedEntryPath = row.path
                            model.setArchiveEntrySelection(row, isSelected: isSelected)
                        }
                    )
                )
                .labelsHidden()
                .disabled(!row.canSelectForExtraction || model.isRunning)
                .help(row.selectionDisabledReason ?? "选择条目")
            }
            .width(36)

            TableColumn("") { row in
                Button {
                    focusedEntryPath = row.path
                } label: {
                    Image(systemName: focusedEntryPath == row.path ? "info.circle.fill" : "info.circle")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("查看详情")
            }
            .width(34)

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

    private func entryDetailPanel(_ row: ArchiveEntryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("条目详情", systemImage: "info.circle")
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                if row.canSelectForExtraction {
                    Button {
                        let shouldSelect = !model.isArchiveEntrySelected(row)
                        focusedEntryPath = row.path
                        model.setArchiveEntrySelection(row, isSelected: shouldSelect)
                    } label: {
                        Label(
                            model.isArchiveEntrySelected(row) ? "取消选择" : "选择条目",
                            systemImage: model.isArchiveEntrySelected(row)
                                ? "minus.circle"
                                : "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isRunning)
                }
            }

            EntryDetailLine(title: "路径", value: row.path, isMonospaced: true)
            EntryDetailLine(title: "类型", value: row.kindTitle)
            EntryDetailLine(title: "大小", value: row.detail)
            EntryDetailLine(title: "修改时间", value: row.modifiedText)

            if let linkTarget = row.linkTarget {
                EntryDetailLine(title: "链接目标", value: linkTarget, isMonospaced: true)
            }

            if let risk = row.risk {
                Label(risk.detail, systemImage: risk.iconName)
                    .foregroundStyle(risk.sortOrder == 1 ? .orange : .red)
                    .lineLimit(2)
            }
        }
        .font(.caption)
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

private struct EntryDetailLine: View {
    let title: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
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
