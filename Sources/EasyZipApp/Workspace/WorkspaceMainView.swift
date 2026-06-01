import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceMainView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(spacing: 18) {
            DropZoneView(model: model)

            HStack(alignment: .top, spacing: 18) {
                OptionsPanelView(model: model)
                    .frame(width: 320)

                ArchivePreviewView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
    }
}

private struct DropZoneView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(model.isDropTargeted ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        model.isDropTargeted ? Color.blue : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: model.mode == .compress ? "square.and.arrow.down.on.square" : "doc.zipper")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.blue)

                    Text(model.mode == .compress ? "拖入文件或文件夹" : "拖入支持的归档文件")
                        .font(.system(size: 18, weight: .semibold))

                    Text(model.selectedItems.isEmpty ? "等待添加" : "已选择 \(model.selectedItems.count) 项")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 190)
            .opacity(model.isRunning ? 0.65 : 1)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $model.isDropTargeted,
                perform: model.handleDrop(providers:)
            )
    }
}
