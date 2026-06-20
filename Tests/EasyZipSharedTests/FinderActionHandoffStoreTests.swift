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
