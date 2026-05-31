import Foundation

struct RecentArchiveTask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String
    let outputURL: URL?
    let iconName: String
    let completedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        outputURL: URL?,
        iconName: String,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.outputURL = outputURL
        self.iconName = iconName
        self.completedAt = completedAt
    }

    init(result: TaskResult, completedAt: Date = Date()) {
        self.init(
            title: result.title,
            detail: result.detail,
            outputURL: result.outputURL,
            iconName: result.iconName,
            completedAt: completedAt
        )
    }
}

enum RecentArchiveStore {
    static let maxTaskCount = 6
    static let maxOutputDirectoryCount = 5

    private static let tasksKey = "easyzip.recentTasks"
    private static let outputDirectoriesKey = "easyzip.recentOutputDirectories"

    static func loadTasks() -> [RecentArchiveTask] {
        guard let data = UserDefaults.standard.data(forKey: tasksKey),
              let tasks = try? JSONDecoder().decode([RecentArchiveTask].self, from: data) else {
            return []
        }

        return Array(tasks.prefix(maxTaskCount))
    }

    static func saveTasks(_ tasks: [RecentArchiveTask]) {
        guard let data = try? JSONEncoder().encode(Array(tasks.prefix(maxTaskCount))) else {
            return
        }

        UserDefaults.standard.set(data, forKey: tasksKey)
    }

    static func loadOutputDirectories() -> [URL] {
        let values = UserDefaults.standard.stringArray(forKey: outputDirectoriesKey) ?? []

        let urls: [URL] = values.compactMap { value in
            guard let url = URL(string: value), url.isFileURL else {
                return nil
            }

            return url
        }

        return Array(urls.prefix(maxOutputDirectoryCount))
    }

    static func saveOutputDirectories(_ urls: [URL]) {
        let values = urls
            .prefix(maxOutputDirectoryCount)
            .map(\.absoluteString)

        UserDefaults.standard.set(Array(values), forKey: outputDirectoriesKey)
    }
}
