import SwiftUI

struct ProgressDrawerView: View {
    @ObservedObject var model: EasyZipAppModel

    var body: some View {
        VStack(spacing: 8) {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
