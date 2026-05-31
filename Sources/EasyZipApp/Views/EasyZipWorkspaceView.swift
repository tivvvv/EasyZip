import EasyZipCore
import SwiftUI
import UniformTypeIdentifiers

struct EasyZipWorkspaceView: View {
    @StateObject private var model = EasyZipAppModel()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(model: model)

            Divider()

            HStack(spacing: 0) {
                FileQueueView(model: model)
                    .frame(width: 300)

                Divider()

                WorkspaceMainView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ProgressDrawerView(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("确定"))
            )
        }
    }
}

private struct WorkspaceToolbar: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("易压缩")
                    .font(.system(size: 20, weight: .semibold))
            }

            Picker("模式", selection: $model.mode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .disabled(model.isRunning)

            Spacer()

            Button {
                model.chooseItems()
            } label: {
                Label("添加", systemImage: "plus")
            }
            .disabled(model.isRunning)

            Button {
                model.chooseOutputDirectory()
            } label: {
                Label("输出", systemImage: "folder")
            }
            .disabled(model.isRunning)

            Button {
                model.startOperation()
            } label: {
                Label(
                    model.primaryActionTitle,
                    systemImage: model.mode == .compress ? "archivebox.fill" : "tray.and.arrow.down.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }
}

private struct FileQueueView: View {
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

private struct WorkspaceMainView: View {
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

private struct OptionsPanelView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选项")
                .font(.headline)

            LabeledContent("输出目录") {
                Button {
                    model.chooseOutputDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text(model.outputLabel)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 190, alignment: .trailing)
                .disabled(model.isRunning)
            }

            if model.mode == .compress {
                LabeledContent("格式") {
                    Picker("格式", selection: $model.selectedFormat) {
                        ForEach(ArchiveFormat.allCases, id: \.self) { format in
                            Text(format.displayExtension).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(model.isRunning)
                }

                if let status = model.formatRequirementStatus {
                    FormatRequirementStatusView(status: status) {
                        model.refreshExternalToolAvailability()
                    }
                }

                LabeledContent("名称") {
                    TextField("归档文件", text: $model.archiveName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .disabled(model.isRunning)
                }

                Toggle("包含隐藏文件", isOn: $model.includeHiddenFiles)
                    .disabled(model.isRunning)
                Toggle("保留父目录", isOn: $model.preserveParentDirectory)
                    .disabled(model.isRunning)
                Toggle("保留元数据", isOn: $model.preserveMetadata)
                    .disabled(model.isRunning)
            } else {
                LabeledContent("冲突处理") {
                    Picker("冲突处理", selection: $model.overwritePolicy) {
                        Text("自动重命名").tag(OverwritePolicy.rename)
                        Text("覆盖").tag(OverwritePolicy.overwrite)
                        Text("跳过").tag(OverwritePolicy.skip)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(model.isRunning)
                }
            }

            if let taskResult = model.taskResult {
                TaskResultView(model: model, result: taskResult)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FormatRequirementStatusView: View {
    let status: (title: String, detail: String, iconName: String, isBlocking: Bool)
    let refreshAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.iconName)
                .foregroundStyle(status.isBlocking ? .orange : .green)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: refreshAction) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新检测")
        }
    }
}

private struct TaskResultView: View {
    @ObservedObject var model: EasyZipAppModel
    let result: TaskResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("任务结果")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Image(systemName: result.iconName)
                    .foregroundStyle(resultColor)

                Text(result.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Text(result.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if result.outputURL != nil {
                Button {
                    model.revealOutputInFinder()
                } label: {
                    Label("定位输出", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canRevealOutput)
            }
        }
    }

    private var resultColor: Color {
        switch result.title {
        case "压缩完成", "解压完成":
            .green
        case "操作失败":
            .red
        default:
            .secondary
        }
    }
}

private struct ArchivePreviewView: View {
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

private struct ProgressDrawerView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ProgressView(value: model.progressFraction)
                    .progressViewStyle(.linear)

                Text(model.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 180, alignment: .trailing)

                Button {
                    model.cancelOperation()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("取消")
                .disabled(!model.isRunning)

                Button {
                    model.revealOutputInFinder()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("定位")
                .disabled(!model.canRevealOutput)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
