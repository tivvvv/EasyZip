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
    public static let bookmarkQueryItemName = "bookmark"
    public static let appGroupIdentifierInfoKey = "EZAppGroupIdentifier"
    public static let defaultAppGroupIdentifier = "group.com.tiv.easyzip"
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
        directoryURL: URL = Self.defaultDirectoryURL(),
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

    public static func defaultDirectoryURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL {
        appGroupDirectoryURL(
            groupIdentifier: configuredAppGroupIdentifier(bundle: bundle),
            fileManager: fileManager
        ) ?? directoryURL(appGroupContainerURL: nil, fileManager: fileManager)
    }

    public static func configuredAppGroupIdentifier(bundle: Bundle = .main) -> String {
        if let value = bundle.object(forInfoDictionaryKey: appGroupIdentifierInfoKey) as? String {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedValue.isEmpty {
                return trimmedValue
            }
        }

        return defaultAppGroupIdentifier
    }

    public static func directoryURL(
        appGroupContainerURL: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        (appGroupContainerURL ?? fileManager.temporaryDirectory)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func appGroupDirectoryURL(
        groupIdentifier: String,
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public func write(fileURLs: [URL], action: String? = nil) throws -> String {
        let uniqueFileURLs = FileURLListNormalizer.uniqueStandardizedFileURLs(fileURLs)
        try validateFileURLs(uniqueFileURLs)

        let payload = Payload(
            version: Self.payloadVersion,
            createdAt: now(),
            fileURLStrings: uniqueFileURLs.map(\.absoluteString),
            securityScopedBookmarks: action == nil
                ? Self.securityScopedBookmarks(for: uniqueFileURLs)
                : nil,
            action: action
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

        let fileURLs = fileURLs(from: payload)

        guard !fileURLs.isEmpty else {
            throw StoreError.unreadablePayload
        }

        let uniqueFileURLs = FileURLListNormalizer.uniqueStandardizedFileURLs(fileURLs)
        try validateFileURLs(uniqueFileURLs)
        return uniqueFileURLs
    }

    public func readAndRemoveAction(matching fileURLs: [URL]) -> String? {
        let normalizedFileURLs = FileURLListNormalizer.uniqueStandardizedFileURLs(fileURLs)
        guard !normalizedFileURLs.isEmpty,
              let handoffURLs = try? fileManager.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        let expectedPaths = Set(normalizedFileURLs.map(\.path))
        let candidates = handoffURLs.compactMap { handoffURL -> (URL, Payload)? in
            guard handoffURL.pathExtension == Self.fileExtension,
                  let data = try? Data(contentsOf: handoffURL),
                  data.count <= maxPayloadSize,
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  payload.version == Self.payloadVersion,
                  now().timeIntervalSince(payload.createdAt) <= maxAge,
                  payload.action != nil else {
                return nil
            }

            let payloadPaths = Set(
                payload.fileURLStrings
                    .compactMap(URL.init(string:))
                    .filter(\.isFileURL)
                    .map { $0.standardizedFileURL.path }
            )

            guard payloadPaths == expectedPaths else {
                return nil
            }

            return (handoffURL, payload)
        }

        guard let candidate = candidates.max(by: { $0.1.createdAt < $1.1.createdAt }) else {
            return nil
        }

        try? fileManager.removeItem(at: candidate.0)
        return candidate.1.action
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

    public static func stopAccessingSecurityScopedResources() {
        securityScopedResourceAccessStore.stopAccessingAll()
    }

    public static func retainSecurityScopedAccess(to urls: [URL]) {
        for url in urls where url.startAccessingSecurityScopedResource() {
            securityScopedResourceAccessStore.retain(url)
        }
    }

    public static func securityScopedBookmarks(for urls: [URL]) -> [Data]? {
        let bookmarks = try? urls.map { url in
            try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        return bookmarks?.isEmpty == false ? bookmarks : nil
    }

    public static func fileURLs(fromSecurityScopedBookmarks bookmarks: [Data]?) -> [URL]? {
        guard let bookmarks, !bookmarks.isEmpty else {
            return nil
        }

        let urls: [URL] = bookmarks.compactMap { bookmark in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else {
                return nil
            }

            return url
        }

        guard urls.count == bookmarks.count else {
            return nil
        }

        var accessedURLs: [URL] = []

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                for accessedURL in accessedURLs {
                    accessedURL.stopAccessingSecurityScopedResource()
                }
                return nil
            }

            accessedURLs.append(url)
        }

        for url in accessedURLs {
            securityScopedResourceAccessStore.retain(url)
        }

        return urls
    }

    public static func fileURLs(
        fromBase64SecurityScopedBookmarks values: [String]
    ) throws -> [URL]? {
        guard !values.isEmpty else {
            return nil
        }

        let bookmarks = values.compactMap { Data(base64Encoded: $0) }
        guard bookmarks.count == values.count,
              let fileURLs = fileURLs(fromSecurityScopedBookmarks: bookmarks),
              fileURLs.count == values.count else {
            throw StoreError.unreadablePayload
        }

        return fileURLs
    }

    private static let securityScopedResourceAccessStore = SecurityScopedResourceAccessStore()

    private func fileURLs(from payload: Payload) -> [URL] {
        if let bookmarkURLs = Self.fileURLs(
            fromSecurityScopedBookmarks: payload.securityScopedBookmarks
        ),
           !bookmarkURLs.isEmpty {
            return bookmarkURLs
        }

        return payload.fileURLStrings
            .compactMap(URL.init(string:))
            .filter(\.isFileURL)
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

}

private struct Payload: Codable {
    let version: Int
    let createdAt: Date
    let fileURLStrings: [String]
    let securityScopedBookmarks: [Data]?
    let action: String?
}

private final class SecurityScopedResourceAccessStore: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func retain(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func stopAccessingAll() {
        lock.lock()
        let retainedURLs = urls
        urls.removeAll()
        lock.unlock()

        for url in retainedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
