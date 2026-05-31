import XCTest
@testable import EasyZipCore

final class RARCommandResolverTests: XCTestCase {
    private let fileManager = FileManager.default

    func testReportsExplicitExecutableAvailability() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let executableURL = workspaceURL.appendingPathComponent("rar")
        try Data().write(to: executableURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let resolver = RARCommandResolver(
            executableURL: executableURL,
            candidatePaths: [],
            pathValue: ""
        )
        let availability = resolver.availability()

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(availability.name, "rar")
        XCTAssertEqual(availability.executableURL?.path, executableURL.path)
        XCTAssertEqual(try resolver.executableURL().path, executableURL.path)
    }

    func testFindsExecutableFromPathValue() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let binURL = workspaceURL.appendingPathComponent("bin", isDirectory: true)
        let executableURL = binURL.appendingPathComponent("rar")

        try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
        try Data().write(to: executableURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let resolver = RARCommandResolver(candidatePaths: [], pathValue: binURL.path)

        XCTAssertEqual(resolver.availability().executableURL?.path, executableURL.path)
    }

    func testReportsUnavailableWhenExecutableIsMissing() throws {
        let workspaceURL = try makeWorkspaceURL()
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let resolver = RARCommandResolver(
            executableURL: workspaceURL.appendingPathComponent("missing-rar"),
            candidatePaths: [],
            pathValue: ""
        )

        XCTAssertFalse(resolver.availability().isAvailable)
        XCTAssertThrowsError(try resolver.executableURL()) { error in
            XCTAssertEqual(error as? ArchiveError, .externalToolUnavailable("rar"))
        }
    }

    private func makeWorkspaceURL() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("EasyZipResolverTests-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
