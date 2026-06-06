import Foundation

public struct FinderActionHandoffStore {
    public enum StoreError: Error, Equatable {
        case invalidIdentifier
        case missingHandoff
        case expiredHandoff
        case unreadablePayload
    }

    public static let handoffQueryItemName = "handoff"
    public static let defaultMaxAge: TimeInterval = 10 * 60

    private static let directoryName = "com.tiv.easyzip.finder-handoff"
    private static let fileExtension = "json"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private let now: () -> Date

    public init(
        directoryURL: URL = Self.defaultDirectoryURL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval = Self.defaultMaxAge,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.maxAge = maxAge
        self.now = now
    }

    public static var defaultDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public func write(fileURLs: [URL]) throws -> String {
        let uniqueFileURLs = uniqueFileURLs(fileURLs)
        let payload = Payload(
            version: 1,
            createdAt: now(),
            fileURLStrings: uniqueFileURLs.map(\.absoluteString)
        )
        let handoffId = UUID().uuidString
        let fileURL = try handoffFileURL(for: handoffId)
        let data = try JSONEncoder().encode(payload)

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        removeExpiredFiles()
        try data.write(to: fileURL, options: .atomic)
        return handoffId
    }

    public func readAndRemove(id: String) throws -> [URL] {
        let fileURL = try handoffFileURL(for: id)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw StoreError.missingHandoff
        }

        defer {
            try? fileManager.removeItem(at: fileURL)
        }

        let data = try Data(contentsOf: fileURL)
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        guard now().timeIntervalSince(payload.createdAt) <= maxAge else {
            throw StoreError.expiredHandoff
        }

        let fileURLs = payload.fileURLStrings
            .compactMap(URL.init(string:))
            .filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            throw StoreError.unreadablePayload
        }

        return uniqueFileURLs(fileURLs)
    }

    public func removeExpiredFiles() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        let expirationDate = now().addingTimeInterval(-maxAge)

        for fileURL in fileURLs where fileURL.pathExtension == Self.fileExtension {
            guard let modifiedAt = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate else {
                continue
            }

            if modifiedAt < expirationDate {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func handoffFileURL(for id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else {
            throw StoreError.invalidIdentifier
        }

        return directoryURL
            .appendingPathComponent(uuid.uuidString, isDirectory: false)
            .appendingPathExtension(Self.fileExtension)
    }

    private func uniqueFileURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            uniqueURLs.append(standardizedURL)
        }

        return uniqueURLs
    }
}

private struct Payload: Codable {
    let version: Int
    let createdAt: Date
    let fileURLStrings: [String]
}
