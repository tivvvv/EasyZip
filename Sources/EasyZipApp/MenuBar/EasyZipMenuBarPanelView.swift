import SwiftUI

struct EasyZipMenuBarPanelView: View {
    @ObservedObject var model: EasyZipAppModel
    let actions: MenuBarPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            actionsRow
            if let pendingSelection = model.pendingExternalSelection {
                Divider()
                pendingSelectionCard(pendingSelection)
            }
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
                    .foregroundStyle(statusColor)
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
            HStack {
                sectionTitle("最近任务")
                Spacer()
                if !model.recentTasks.isEmpty {
                    iconButton(
                        systemName: "trash",
                        help: "清空最近任务",
                        action: model.clearRecentTasks
                    )
                }
            }

            if model.recentTasks.isEmpty {
                emptyText("暂无最近任务")
            } else {
                ForEach(model.recentTasks) { task in
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
                ForEach(model.recentOutputDirectories) { directory in
                    outputDirectoryRow(directory)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Button {
                actions.openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

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

    private func pendingSelectionCard(_ selection: PendingExternalSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("待处理选择")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(selection.mode.rawValue) \(selection.itemCountText), \(dateText(selection.receivedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    model.applyPendingExternalSelection()
                } label: {
                    Label("应用", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning)

                Button {
                    model.clearPendingExternalSelection()
                } label: {
                    Label("忽略", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.06))
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

        guard let task = model.recentTasks.first else {
            return model.taskResult?.detail ?? "准备处理压缩和解压任务"
        }

        return "\(task.detail)  \(dateText(task.completedAt))"
    }

    private var statusIconName: String {
        model.taskResult?.iconName ?? "archivebox"
    }

    private var statusColor: Color {
        if model.isRunning {
            return .blue
        }

        switch statusIconName {
        case "checkmark.circle":
            return .green
        case "exclamationmark.triangle":
            return .orange
        case "xmark.circle":
            return .secondary
        default:
            return .primary
        }
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
                Image(systemName: task.outputURL == nil ? "macwindow" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func outputDirectoryRow(_ directory: RecentOutputDirectory) -> some View {
        HStack(spacing: 8) {
            Button {
                actions.openURL(directory.url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: directory.isPinned ? "pin.fill" : "folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(directory.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(directoryTitle(for: directory.url))
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(directoryParentPath(for: directory.url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            iconButton(
                systemName: directory.isPinned ? "pin.slash" : "pin",
                help: directory.isPinned ? "取消固定" : "固定目录"
            ) {
                model.toggleRecentOutputDirectoryPin(directory)
            }

            iconButton(systemName: "xmark", help: "移除目录") {
                model.removeRecentOutputDirectory(directory)
            }
        }
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

    private func directoryTitle(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func directoryParentPath(for url: URL) -> String {
        url.deletingLastPathComponent().path
    }

    private func iconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
