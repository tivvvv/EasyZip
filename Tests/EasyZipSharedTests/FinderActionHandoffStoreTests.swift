import XCTest
import EasyZipTestSupport
@testable import EasyZipShared

final class FinderActionHandoffStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testWritesReadsAndRemovesHandoff() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)
        let firstURL = URL(fileURLWithPath: "/tmp/example.txt")
        let handoffId = try store.write(fileURLs: [firstURL, firstURL])
        let fileURLs = try store.readAndRemove(id: handoffId)

        XCTAssertEqual(fileURLs.map(\.path), [firstURL.path])
        XCTAssertThrowsError(try store.readAndRemove(id: handoffId)) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .missingHandoff)
        }
    }

    func testReadsAndRemovesMatchingAction() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        _ = try store.write(fileURLs: [firstURL], action: "compress")
        let matchingId = try store.write(fileURLs: [secondURL], action: "extract")

        XCTAssertEqual(store.readAndRemoveAction(matching: [secondURL]), "extract")
        XCTAssertNil(store.readAndRemoveAction(matching: [secondURL]))
        XCTAssertThrowsError(try store.readAndRemove(id: matchingId)) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .missingHandoff)
        }
        XCTAssertEqual(store.readAndRemoveAction(matching: [firstURL]), "compress")
    }

    func testDoesNotMatchActionForPartialFileSelection() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        _ = try store.write(fileURLs: [firstURL, secondURL], action: "compress")

        XCTAssertNil(store.readAndRemoveAction(matching: [firstURL]))
    }

    func testWritesActionWithoutSecurityScopedBookmarks() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sourceURL = workspaceURL.appendingPathComponent("example.txt")
        try "example".write(to: sourceURL, atomically: true, encoding: .utf8)
        let store = FinderActionHandoffStore(directoryURL: workspaceURL)

        let handoffId = try store.write(fileURLs: [sourceURL], action: "compress")
        let handoffURL = workspaceURL
            .appendingPathComponent(handoffId)
            .appendingPathExtension("json")
        let data = try Data(contentsOf: handoffURL)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["action"] as? String, "compress")
        XCTAssertNil(payload["securityScopedBookmarks"])
    }

    func testDoesNotMatchExpiredAction() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        var currentDate = Date()
        let store = FinderActionHandoffStore(
            directoryURL: workspaceURL,
            maxAge: 10,
            now: { currentDate }
        )
        let sourceURL = URL(fileURLWithPath: "/tmp/example.txt")
        _ = try store.write(fileURLs: [sourceURL], action: "compress")
        currentDate = currentDate.addingTimeInterval(11)

        XCTAssertNil(store.readAndRemoveAction(matching: [sourceURL]))
    }

    func testWritesHandoffWithPrivatePermissions() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)
        let handoffId = try store.write(fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")])
        let handoffURL = workspaceURL
            .appendingPathComponent(handoffId)
            .appendingPathExtension("json")

        let directoryAttributes = try fileManager.attributesOfItem(atPath: workspaceURL.path)
        let handoffAttributes = try fileManager.attributesOfItem(atPath: handoffURL.path)

        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (handoffAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testWritesSecurityScopedBookmarkForExistingFiles() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sourceURL = workspaceURL.appendingPathComponent("example.txt")
        try "example".write(to: sourceURL, atomically: true, encoding: .utf8)

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)
        let handoffId = try store.write(fileURLs: [sourceURL])
        let handoffURL = workspaceURL
            .appendingPathComponent(handoffId)
            .appendingPathExtension("json")
        let data = try Data(contentsOf: handoffURL)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let bookmarks = try XCTUnwrap(payload["securityScopedBookmarks"] as? [String])

        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertFalse(bookmarks[0].isEmpty)
    }

    func testCreatesAndResolvesSecurityScopedBookmarks() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            FinderActionHandoffStore.stopAccessingSecurityScopedResources()
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sourceURL = workspaceURL.appendingPathComponent("example.txt")
        try "example".write(to: sourceURL, atomically: true, encoding: .utf8)

        let bookmarks = try XCTUnwrap(
            FinderActionHandoffStore.securityScopedBookmarks(for: [sourceURL])
        )
        let fileURLs = try XCTUnwrap(
            FinderActionHandoffStore.fileURLs(fromSecurityScopedBookmarks: bookmarks)
        )

        XCTAssertEqual(fileURLs.map(\.standardizedFileURL), [sourceURL.standardizedFileURL])
    }

    func testRejectsPartialSecurityScopedBookmarkResolution() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            FinderActionHandoffStore.stopAccessingSecurityScopedResources()
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sourceURL = workspaceURL.appendingPathComponent("example.txt")
        try "example".write(to: sourceURL, atomically: true, encoding: .utf8)
        let bookmarks = try XCTUnwrap(
            FinderActionHandoffStore.securityScopedBookmarks(for: [sourceURL])
        )

        XCTAssertNil(
            FinderActionHandoffStore.fileURLs(
                fromSecurityScopedBookmarks: bookmarks + [Data("invalid".utf8)]
            )
        )
    }

    func testResolvesBase64SecurityScopedBookmarks() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            FinderActionHandoffStore.stopAccessingSecurityScopedResources()
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let sourceURL = workspaceURL.appendingPathComponent("example.txt")
        try "example".write(to: sourceURL, atomically: true, encoding: .utf8)
        let bookmarks = try XCTUnwrap(
            FinderActionHandoffStore.securityScopedBookmarks(for: [sourceURL])
        )

        let fileURLs = try FinderActionHandoffStore.fileURLs(
            fromBase64SecurityScopedBookmarks: bookmarks.map { $0.base64EncodedString() }
        )

        XCTAssertEqual(fileURLs?.map(\.standardizedFileURL), [sourceURL.standardizedFileURL])
    }

    func testRejectsMalformedBase64SecurityScopedBookmark() {
        XCTAssertThrowsError(
            try FinderActionHandoffStore.fileURLs(
                fromBase64SecurityScopedBookmarks: ["invalid"]
            )
        ) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .unreadablePayload)
        }
    }

    func testBuildsDirectoryURLFromAppGroupContainer() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let directoryURL = FinderActionHandoffStore.directoryURL(
            appGroupContainerURL: workspaceURL,
            fileManager: fileManager
        )

        XCTAssertEqual(
            directoryURL.path,
            workspaceURL.appendingPathComponent("com.tiv.easyzip.finder-handoff").path
        )
    }

    func testDefaultDirectoryURLUsesAppGroupHandoffDirectoryWithoutDuplicateComponent() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }
        let appGroupFileManager = AppGroupFileManager(containerURL: workspaceURL)

        let directoryURL = FinderActionHandoffStore.defaultDirectoryURL(
            fileManager: appGroupFileManager
        )

        XCTAssertEqual(
            directoryURL.path,
            workspaceURL.appendingPathComponent("com.tiv.easyzip.finder-handoff").path
        )
    }

    func testBuildsDirectoryURLFromTemporaryDirectoryWhenAppGroupIsUnavailable() {
        let directoryURL = FinderActionHandoffStore.directoryURL(
            appGroupContainerURL: nil,
            fileManager: fileManager
        )

        XCTAssertEqual(
            directoryURL.path,
            fileManager.temporaryDirectory
                .appendingPathComponent("com.tiv.easyzip.finder-handoff")
                .path
        )
    }

    func testRejectsInvalidIdentifier() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)

        XCTAssertThrowsError(try store.readAndRemove(id: "../unsafe")) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .invalidIdentifier)
        }
    }

    func testRejectsExpiredHandoff() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        var currentDate = Date()
        let store = FinderActionHandoffStore(
            directoryURL: workspaceURL,
            maxAge: 10,
            now: { currentDate }
        )
        let handoffId = try store.write(fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")])
        currentDate = currentDate.addingTimeInterval(11)

        XCTAssertThrowsError(try store.readAndRemove(id: handoffId)) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .expiredHandoff)
        }
    }

    func testRejectsTooManyFileURLsWhenWriting() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL, maxFileCount: 1)
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.txt")
        ]

        XCTAssertThrowsError(try store.write(fileURLs: fileURLs)) { error in
            XCTAssertEqual(
                error as? FinderActionHandoffStore.StoreError,
                .tooManyItems(maximum: 1)
            )
        }
    }

    func testRejectsOversizedPayloadWhenWriting() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let store = FinderActionHandoffStore(
            directoryURL: workspaceURL,
            maxPayloadSize: 64
        )

        XCTAssertThrowsError(
            try store.write(fileURLs: [URL(fileURLWithPath: "/tmp/example.txt")])
        ) { error in
            XCTAssertEqual(
                error as? FinderActionHandoffStore.StoreError,
                .payloadTooLarge(maximumBytes: 64)
            )
        }
    }

    func testRejectsOversizedPayloadWhenReading() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        let handoffId = UUID().uuidString
        let handoffURL = workspaceURL
            .appendingPathComponent(handoffId)
            .appendingPathExtension("json")
        try Data(repeating: 0, count: 128).write(to: handoffURL)

        let store = FinderActionHandoffStore(
            directoryURL: workspaceURL,
            maxPayloadSize: 64
        )

        XCTAssertThrowsError(try store.readAndRemove(id: handoffId)) { error in
            XCTAssertEqual(
                error as? FinderActionHandoffStore.StoreError,
                .payloadTooLarge(maximumBytes: 64)
            )
        }
        XCTAssertFalse(fileManager.fileExists(atPath: handoffURL.path))
    }

    func testRemovesExpiredHandoffFiles() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            TemporaryWorkspace.remove(workspaceURL, fileManager: fileManager)
        }

        var currentDate = Date()
        let store = FinderActionHandoffStore(
            directoryURL: workspaceURL,
            maxAge: 10,
            now: { currentDate }
        )
        let expiredId = try store.write(fileURLs: [URL(fileURLWithPath: "/tmp/expired.txt")])
        let activeId = try store.write(fileURLs: [URL(fileURLWithPath: "/tmp/active.txt")])
        let expiredURL = workspaceURL
            .appendingPathComponent(expiredId)
            .appendingPathExtension("json")
        let activeURL = workspaceURL
            .appendingPathComponent(activeId)
            .appendingPathExtension("json")
        currentDate = currentDate.addingTimeInterval(11)

        try fileManager.setAttributes(
            [.modificationDate: currentDate.addingTimeInterval(-11)],
            ofItemAtPath: expiredURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: currentDate],
            ofItemAtPath: activeURL.path
        )

        store.removeExpiredFiles()

        XCTAssertFalse(fileManager.fileExists(atPath: expiredURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: activeURL.path))
    }

    private func makeWorkspaceURL() throws -> URL {
        try TemporaryWorkspace.makeURL(prefix: "EasyZipHandoffTests", fileManager: fileManager)
    }
}

private final class AppGroupFileManager: FileManager {
    private let containerURL: URL

    init(containerURL: URL) {
        self.containerURL = containerURL
        super.init()
    }

    override func containerURL(
        forSecurityApplicationGroupIdentifier groupIdentifier: String
    ) -> URL? {
        containerURL
    }
}
