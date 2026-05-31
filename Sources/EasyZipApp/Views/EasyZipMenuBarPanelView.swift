import SwiftUI

struct MenuBarPanelActions {
    let openWorkspace: () -> Void
    let chooseCompression: () -> Void
    let chooseExtraction: () -> Void
    let revealURL: (URL) -> Void
    let openURL: (URL) -> Void
    let quit: () -> Void
}

struct EasyZipMenuBarPanelView: View {
    @ObservedObject var model: EasyZipAppModel
    let actions: MenuBarPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            actionsRow
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    recentTasksSection
                    Divider()
                    recentOutputsSection
                }
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: model.isRunning ? "clock.arrow.circlepath" : statusIconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(model.isRunning ? .blue : .primary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if model.isRunning {
                ProgressView(value: model.progressFraction)
                    .progressViewStyle(.linear)
            }
        }
        .padding(16)
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            actionButton(
                title: "工作台",
                systemName: "macwindow",
                action: actions.openWorkspace
            )
            actionButton(
                title: "压缩",
                systemName: "archivebox",
                action: actions.chooseCompression
            )
            actionButton(
                title: "解压",
                systemName: "arrow.down.doc",
                action: actions.chooseExtraction
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recentTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("最近任务")

            if model.recentTasks.isEmpty {
                emptyText("暂无最近任务")
            } else {
                ForEach(model.recentTasks.prefix(4)) { task in
                    recentTaskRow(task)
                }
            }
        }
        .padding(16)
    }

    private var recentOutputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("最近输出目录")

            if model.recentOutputDirectories.isEmpty {
                emptyText("暂无输出目录")
            } else {
                ForEach(Array(model.recentOutputDirectories.prefix(4)), id: \.path) { url in
                    outputDirectoryRow(url)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button {
                actions.quit()
            } label: {
                Label("退出易压缩", systemImage: "power")
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusTitle: String {
        if model.isRunning {
            return "任务进行中"
        }

        return model.taskResult?.title ?? "易压缩"
    }

    private var statusDetail: String {
        if model.isRunning {
            return model.progressText
        }

        return model.taskResult?.detail ?? "准备处理压缩和解压任务"
    }

    private var statusIconName: String {
        model.taskResult?.iconName ?? "archivebox"
    }

    private func actionButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .disabled(model.isRunning)
    }

    private func recentTaskRow(_ task: RecentArchiveTask) -> some View {
        Button {
            if let outputURL = task.outputURL {
                actions.revealURL(outputURL)
            } else {
                actions.openWorkspace()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: task.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(dateText(task.completedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func outputDirectoryRow(_ url: URL) -> some View {
        Button {
            actions.openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func dateText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}
