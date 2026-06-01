import EasyZipCore
import SwiftUI

struct ArchivePreviewView: View {
    @ObservedObject var model: EasyZipAppModel

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
                    Table(model.archiveEntries) {
                        TableColumn("名称") { row in
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: row.kind))
                                    .foregroundStyle(.blue)
                                Text(row.name)
                                    .lineLimit(1)
                            }
                        }
                        TableColumn("大小") { row in
                            Text(row.detail)
                                .foregroundStyle(.secondary)
                        }
                        .width(90)
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
