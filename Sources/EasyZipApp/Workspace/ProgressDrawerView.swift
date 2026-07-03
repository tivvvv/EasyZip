import SwiftUI

struct ProgressDrawerView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(spacing: 10) {
            currentTaskRow

            if !model.visibleTaskQueue.isEmpty {
                Divider()
                taskQueueRows
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var currentTaskRow: some View {
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

    private var taskQueueRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("任务队列")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.clearFinishedQueuedTasks()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清理已结束任务")
                .disabled(!model.hasFinishedQueuedTasks)
            }

            ForEach(model.visibleTaskQueue) { task in
                TaskQueueRow(model: model, task: task)
            }
        }
    }
}

private struct TaskQueueRow: View {
    @ObservedObject var model: EasyZipAppModel
    let task: ArchiveQueuedTask

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status.iconName)
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(task.status.title)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }

                ProgressView(value: task.progressFraction)
                    .progressViewStyle(.linear)
                    .opacity(task.status == .running ? 1 : 0.35)

                Text("\(task.detail), \(task.progressText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                model.cancelQueuedTask(task)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("取消")
            .disabled(!task.status.allowsCancel)

            Button {
                model.retryQueuedTask(task)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重试")
            .disabled(!task.status.allowsRetry || model.isRunning)

            Button {
                model.revealQueuedTaskOutput(task)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("定位输出")
            .disabled(task.outputURL == nil)
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .running:
            .blue
        case .waiting:
            .orange
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        }
    }
}
