import Foundation

struct TaskResult: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let outputURL: URL?
    let iconName: String
}
