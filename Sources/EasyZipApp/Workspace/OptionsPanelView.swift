import EasyZipCore
import SwiftUI

struct OptionsPanelView: View {
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
