import Foundation

struct ArchivePasswordPrompt: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let isRetry: Bool

    var title: String {
        isRetry ? "密码不正确" : "需要密码"
    }

    var message: String {
        if isRetry {
            return "请重新输入 \(archiveURL.lastPathComponent) 的密码"
        }

        return "\(archiveURL.lastPathComponent) 是加密归档"
    }
}
