import SwiftUI

struct EasyZipDiagnosticsActions {
    let perform: (EasyZipDiagnosticAction) -> Void
}

struct EasyZipDiagnosticsView: View {
    @StateObject private var model: EasyZipDiagnosticsModel
    let actions: EasyZipDiagnosticsActions
    private let quickActionColumns = [
        GridItem(.adaptive(minimum: 132), spacing: 8)
    ]

    init(
        model: EasyZipDiagnosticsModel,
        actions: EasyZipDiagnosticsActions
    ) {
        _model = StateObject(wrappedValue: model)
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summaryPanel
            quickActionsPanel
            diagnosticsList
            footer
        }
        .padding(24)
        .frame(width: 680, height: 680)
        .task {
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text("环境诊断")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("检查安装位置, Finder 扩展, 沙盒授权, 通知权限和外部工具状态.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: summarySystemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(summaryColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.summaryTitle)
                    .font(.headline)
                Text(model.summaryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var summarySystemImage: String {
        if model.items.isEmpty {
            return "clock"
        }

        return model.needsActionCount > 0 ? "exclamationmark.triangle" : "checkmark.seal"
    }

    private var summaryColor: Color {
        if model.items.isEmpty {
            return .secondary
        }

        return model.needsActionCount > 0 ? .orange : .green
    }

    private var quickActionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快速修复")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(columns: quickActionColumns, alignment: .leading, spacing: 8) {
                ForEach(model.quickActions) { action in
                    Button {
                        perform(action.action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var diagnosticsList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(model.items) { item in
                    diagnosticRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if model.items.isEmpty {
                ProgressView()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Finder Sync 启用状态需要在 System Settings 中确认.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button {
                Task {
                    await model.refresh()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing)
        }
    }

    private func diagnosticRow(_ item: EasyZipDiagnosticItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color(for: item.status))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(item.status.title)
                        .font(.caption)
                        .foregroundStyle(color(for: item.status))
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let action = item.action,
               let actionTitle = item.actionTitle {
                Button {
                    perform(action)
                } label: {
                    Text(actionTitle)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func perform(_ action: EasyZipDiagnosticAction) {
        actions.perform(action)

        guard action == .requestNotificationAuthorization ||
              action == .restartFinder else {
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await model.refresh()
        }
    }

    private func color(for status: EasyZipDiagnosticStatus) -> Color {
        switch status {
        case .normal:
            .green
        case .needsAction:
            .orange
        case .unsupported:
            .secondary
        }
    }
}
