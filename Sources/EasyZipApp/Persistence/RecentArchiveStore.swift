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

struct RecentOutputDirectory: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let url: URL
    var isPinned: Bool
    var updatedAt: Date

    init(url: URL, isPinned: Bool = false, updatedAt: Date = Date()) {
        let standardizedURL = url.standardizedFileURL

        self.id = standardizedURL.path
        self.url = standardizedURL
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

enum RecentArchiveStore {
    static let maxTaskCount = 6
    static let maxOutputDirectoryCount = 5

    private static let tasksKey = "easyzip.recentTasks"
    private static let outputDirectoriesKey = "easyzip.recentOutputDirectories"
    private static let outputDirectoryItemsKey = "easyzip.recentOutputDirectoryItems"

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

    static func loadOutputDirectories() -> [RecentOutputDirectory] {
        if let data = UserDefaults.standard.data(forKey: outputDirectoryItemsKey),
           let directories = try? JSONDecoder().decode([RecentOutputDirectory].self, from: data) {
            return sortedVisibleOutputDirectories(directories)
        }

        let values = UserDefaults.standard.stringArray(forKey: outputDirectoriesKey) ?? []

        let directories: [RecentOutputDirectory] = values.compactMap { value in
            guard let url = URL(string: value), url.isFileURL else {
                return nil
            }

            return RecentOutputDirectory(url: url)
        }

        return sortedVisibleOutputDirectories(directories)
    }

    static func saveOutputDirectories(_ directories: [RecentOutputDirectory]) {
        let values = sortedVisibleOutputDirectories(directories)

        guard let data = try? JSONEncoder().encode(values) else {
            return
        }

        UserDefaults.standard.set(data, forKey: outputDirectoryItemsKey)
    }

    static func sortedVisibleOutputDirectories(
        _ directories: [RecentOutputDirectory]
    ) -> [RecentOutputDirectory] {
        let uniqueDirectories = uniqueOutputDirectories(directories)
        let pinnedDirectories = uniqueDirectories
            .filter(\.isPinned)
            .sorted { $0.updatedAt > $1.updatedAt }
        let recentDirectories = uniqueDirectories
            .filter { !$0.isPinned }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxOutputDirectoryCount)

        return pinnedDirectories + Array(recentDirectories)
    }

    private static func uniqueOutputDirectories(
        _ directories: [RecentOutputDirectory]
    ) -> [RecentOutputDirectory] {
        var seenPaths: Set<String> = []
        var uniqueDirectories: [RecentOutputDirectory] = []

        for directory in directories {
            guard seenPaths.insert(directory.id).inserted else {
                continue
            }

            uniqueDirectories.append(directory)
        }

        return uniqueDirectories
    }
}
