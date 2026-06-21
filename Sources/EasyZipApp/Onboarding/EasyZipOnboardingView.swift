import SwiftUI

struct EasyZipOnboardingActions {
    let complete: () -> Void
    let openWorkspace: () -> Void
    let openFinderExtensionSettings: () -> Void
    let requestNotificationAuthorization: () -> Void
}

struct EasyZipOnboardingView: View {
    let actions: EasyZipOnboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            steps
            actionButtons
            completionButton
        }
        .padding(26)
        .frame(width: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44, alignment: .leading)

            Text("欢迎使用易压缩")
                .font(.title2)
                .fontWeight(.semibold)

            Text("应用已在菜单栏运行, 点击右上角图标即可打开状态面板.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepRow(
                systemName: "menubar.rectangle",
                title: "菜单栏常驻",
                detail: "状态面板可查看进度, 最近任务和最近输出目录."
            )
            stepRow(
                systemName: "puzzlepiece.extension",
                title: "Finder 右键菜单",
                detail: "启用 Finder Extension 后, 可从右键菜单直接压缩或解压."
            )
            stepRow(
                systemName: "bell.badge",
                title: "任务完成通知",
                detail: "允许通知后, 后台任务完成时会发送系统通知."
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                actions.openFinderExtensionSettings()
            } label: {
                Label("扩展设置", systemImage: "puzzlepiece.extension")
            }
            .buttonStyle(.bordered)

            Button {
                actions.requestNotificationAuthorization()
            } label: {
                Label("允许通知", systemImage: "bell")
            }
            .buttonStyle(.bordered)

            Button {
                actions.openWorkspace()
            } label: {
                Label("打开工作台", systemImage: "macwindow")
            }
            .buttonStyle(.bordered)
        }
    }

    private var completionButton: some View {
        HStack {
            Spacer()
            Button {
                actions.complete()
            } label: {
                Label("完成", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func stepRow(
        systemName: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
