import Foundation

/// 归档业务入口.
public final class ArchiveService: Sendable {
    private let registry: ArchiveEngineRegistry
    private let formatDetector: any ArchiveFormatDetecting

    public init(
        registry: ArchiveEngineRegistry,
        formatDetector: any ArchiveFormatDetecting = DefaultArchiveFormatDetector()
    ) {
        self.registry = registry
        self.formatDetector = formatDetector
    }

    public static func makeDefault() -> ArchiveService {
        ArchiveService(
            registry: ArchiveEngineRegistry(
                engines: [
                    LibArchiveEngine()
                ]
            )
        )
    }

    public func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry] {
        let format = try formatDetector.detectFormat(for: archiveURL)
        let engine = try await registry.engine(for: format, operation: .list)

        return try await engine.listEntries(in: archiveURL)
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        let format = try formatDetector.detectFormat(for: request.archiveURL)
        let engine = try await registry.engine(for: format, operation: .extract)

        try await engine.extract(request, progress: progress)
    }

    public func create(
        _ request: CompressionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        let engine = try await registry.engine(for: request.format, operation: .create)

        try await engine.create(request, progress: progress)
    }
}
