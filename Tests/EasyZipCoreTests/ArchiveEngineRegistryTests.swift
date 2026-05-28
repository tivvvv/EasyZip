import XCTest
@testable import EasyZipCore

final class ArchiveEngineRegistryTests: XCTestCase {
    func testReturnsRegisteredEngineForSupportedOperation() async throws {
        let registry = ArchiveEngineRegistry()
        let engine = StubArchiveEngine(
            identifier: "stub",
            capabilities: .init(
                readableFormats: [.zip],
                writableFormats: [.sevenZip]
            )
        )

        await registry.register(engine)

        let selectedEngine = try await registry.engine(for: .zip, operation: .extract)

        XCTAssertEqual(selectedEngine.identifier, "stub")
    }

    func testThrowsWhenNoEngineSupportsOperation() async throws {
        let registry = ArchiveEngineRegistry()

        do {
            _ = try await registry.engine(for: .sevenZip, operation: .create)
            XCTFail("Expected unsupported operation error.")
        } catch ArchiveError.unsupportedOperation(let format, let operation) {
            XCTAssertEqual(format, .sevenZip)
            XCTAssertEqual(operation, .create)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubArchiveEngine: ArchiveEngine {
    let identifier: String
    let capabilities: ArchiveEngineCapabilities

    func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry] {
        []
    }

    func extract(
        _ request: ExtractionRequest,
        progress: ArchiveProgressHandler?
    ) async throws {}

    func create(
        _ request: CompressionRequest,
        progress: ArchiveProgressHandler?
    ) async throws {}
}
