import SwiftUI

struct PendingExternalSelectionBanner: View {
    @ObservedObject var model: EasyZipAppModel
    let selection: PendingExternalSelection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("已暂存新的\(selection.mode.rawValue)选择")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text("\(selection.itemCountText), \(model.isRunning ? "当前任务完成后可应用" : "现在可以应用")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.applyPendingExternalSelection()
            } label: {
                Label("应用", systemImage: "checkmark.circle")
            }
            .disabled(model.isRunning)

            Button {
                model.clearPendingExternalSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("忽略")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.08))
    }
}

struct WorkspaceToolbar: View {
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
