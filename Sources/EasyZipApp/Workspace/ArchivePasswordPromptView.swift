import SwiftUI

struct ArchivePasswordPromptView: View {
    let prompt: ArchivePasswordPrompt
    let submit: (String) -> Void
    let cancel: () -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title)
                        .font(.headline)
                    Text(prompt.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(submitPassword)

            HStack {
                Spacer()

                Button("取消") {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("继续解压") {
                    submitPassword()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private func submitPassword() {
        guard !password.isEmpty else {
            return
        }

        submit(password)
    }
}
