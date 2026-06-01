import EasyZipCore
import SwiftUI

struct FileQueueView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("队列")
                    .font(.headline)

                Spacer()

                Button {
                    model.clearItems()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空")
                .disabled(model.selectedItems.isEmpty || model.isRunning)
            }

            if model.selectedItems.isEmpty {
                EmptyQueueView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.selectedItems, id: \.self) { url in
                            QueueRow(url: url, isDisabled: model.isRunning) {
                                model.removeItem(url)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("暂无文件")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QueueRow: View {
    let url: URL
    let isDisabled: Bool
    let removeAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 22)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(url.displayName)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .medium))

                Text(url.deletingLastPathComponent().displayPath)
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: removeAction) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("移除")
            .disabled(isDisabled)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        ArchiveFormat.isSupportedArchiveFilename(url.lastPathComponent) ? "doc.zipper" : "doc"
    }
}
