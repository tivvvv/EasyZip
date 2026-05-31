import Foundation

struct PendingExternalSelection: Identifiable, Equatable, Sendable {
    let id = UUID()
    let mode: WorkspaceMode
    let fileURLs: [URL]
    let receivedAt: Date

    init(mode: WorkspaceMode, fileURLs: [URL], receivedAt: Date = Date()) {
        self.mode = mode
        self.fileURLs = fileURLs
        self.receivedAt = receivedAt
    }

    var itemCountText: String {
        "\(fileURLs.count) 项"
    }
}
