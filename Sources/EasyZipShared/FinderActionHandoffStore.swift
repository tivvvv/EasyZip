import Foundation

public struct FinderActionHandoffStore {
    public enum StoreError: Error, Equatable {
        case invalidIdentifier
        case missingHandoff
        case expiredHandoff
        case unreadablePayload
        case tooManyItems(maximum: Int)
        case payloadTooLarge(maximumBytes: Int)
    }

    public static let handoffQueryItemName = "handoff"
    public static let defaultMaxAge: TimeInterval = 10 * 60
    public static let defaultMaxFileCount = 10_000
    public static let defaultMaxPayloadSize = 4 * 1024 * 1024

    private static let directoryName = "com.tiv.easyzip.finder-handoff"
    private static let fileExtension = "json"
    private static let payloadVersion = 1
    private static let directoryPermissions: NSNumber = 0o700
    private static let filePermissions: NSNumber = 0o600

    private let directoryURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private let maxFileCount: Int
    private let maxPayloadSize: Int
    private let now: () -> Date

    public init(
        directoryURL: URL = Self.defaultDirectoryURL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval = Self.defaultMaxAge,
        maxFileCount: Int = Self.defaultMaxFileCount,
        maxPayloadSize: Int = Self.defaultMaxPayloadSize,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.maxAge = maxAge
        self.maxFileCount = maxFileCount
        self.maxPayloadSize = maxPayloadSize
        self.now = now
    }

    public static var defaultDirectoryURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func appGroupDirectoryURL(groupIdentifier: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public func write(fileURLs: [URL]) throws -> String {
        let uniqueFileURLs = uniqueFileURLs(fileURLs)
        try validateFileURLs(uniqueFileURLs)

        let payload = Payload(
            version: Self.payloadVersion,
            createdAt: now(),
            fileURLStrings: uniqueFileURLs.map(\.absoluteString)
        )
        let handoffId = UUID().uuidString
        let fileURL = try handoffFileURL(for: handoffId)
        let data = try JSONEncoder().encode(payload)
        try validatePayloadSize(UInt64(data.count))

        try prepareDirectory()
        removeExpiredFiles()

        do {
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: Self.filePermissions],
                ofItemAtPath: fileURL.path
            )
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }

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

        let attributes: [FileAttributeKey: Any]

        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch {
            throw StoreError.unreadablePayload
        }

        guard let fileSize = attributes[.size] as? NSNumber else {
            throw StoreError.unreadablePayload
        }
        try validatePayloadSize(fileSize.uint64Value)

        let data: Data
        let payload: Payload

        do {
            data = try Data(contentsOf: fileURL)
            try validatePayloadSize(UInt64(data.count))
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.unreadablePayload
        }

        guard payload.version == Self.payloadVersion else {
            throw StoreError.unreadablePayload
        }

        guard now().timeIntervalSince(payload.createdAt) <= maxAge else {
            throw StoreError.expiredHandoff
        }

        let fileURLs = payload.fileURLStrings
            .compactMap(URL.init(string:))
            .filter(\.isFileURL)

        guard !fileURLs.isEmpty else {
            throw StoreError.unreadablePayload
        }

        let uniqueFileURLs = uniqueFileURLs(fileURLs)
        try validateFileURLs(uniqueFileURLs)
        return uniqueFileURLs
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

    private func prepareDirectory() throws {
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw StoreError.unreadablePayload
            }
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        try fileManager.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directoryURL.path
        )
    }

    private func validateFileURLs(_ urls: [URL]) throws {
        guard !urls.isEmpty else {
            throw StoreError.unreadablePayload
        }

        guard urls.count <= maxFileCount else {
            throw StoreError.tooManyItems(maximum: maxFileCount)
        }
    }

    private func validatePayloadSize(_ byteCount: UInt64) throws {
        guard byteCount <= UInt64(maxPayloadSize) else {
            throw StoreError.payloadTooLarge(maximumBytes: maxPayloadSize)
        }
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
