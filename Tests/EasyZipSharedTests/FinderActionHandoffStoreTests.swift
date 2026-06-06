import XCTest
@testable import EasyZipShared

final class FinderActionHandoffStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testWritesReadsAndRemovesHandoff() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
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

    func testRejectsInvalidIdentifier() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let store = FinderActionHandoffStore(directoryURL: workspaceURL)

        XCTAssertThrowsError(try store.readAndRemove(id: "../unsafe")) { error in
            XCTAssertEqual(error as? FinderActionHandoffStore.StoreError, .invalidIdentifier)
        }
    }

    func testRejectsExpiredHandoff() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
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

    private func makeWorkspaceURL() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("EasyZipHandoffTests-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
