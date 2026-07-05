import SwiftUI

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
