import EasyZipCore
import SwiftUI

struct ArchiveConflictPromptView: View {
    let prompt: ArchiveConflictPrompt
    let resolve: (ArchiveConflictPrompt, OverwritePolicy, Bool) -> Void

    @State private var appliesToRemainingConflicts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("归档条目") {
                    Text(prompt.entryPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                LabeledContent("目标位置") {
                    Text(prompt.destinationPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack(spacing: 8) {
                    Label(prompt.existingKindText, systemImage: prompt.existingKindIconName)
                    Label(prompt.incomingKindText, systemImage: prompt.incomingKindIconName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Toggle("应用到后续冲突", isOn: $appliesToRemainingConflicts)

            HStack {
                Button {
                    submit(.skip)
                } label: {
                    Label("跳过", systemImage: "forward")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    submit(.rename)
                } label: {
                    Label("重命名", systemImage: "text.insert")
                }
                .keyboardShortcut(.defaultAction)

                Button(role: .destructive) {
                    submit(.overwrite)
                } label: {
                    Label("覆盖", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("目标已存在")
                    .font(.headline)
                Text("请选择如何处理这个冲突")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func submit(_ policy: OverwritePolicy) {
        resolve(prompt, policy, appliesToRemainingConflicts)
    }
}
