import Foundation

/// 归档引擎能力声明.
public struct ArchiveEngineCapabilities: Equatable, Sendable {
    public let readableFormats: Set<ArchiveFormat>
    public let writableFormats: Set<ArchiveFormat>

    public init(
        readableFormats: Set<ArchiveFormat>,
        writableFormats: Set<ArchiveFormat>
    ) {
        self.readableFormats = readableFormats
        self.writableFormats = writableFormats
    }

    public func supports(format: ArchiveFormat, operation: ArchiveOperation) -> Bool {
        switch operation {
        case .list, .extract:
            readableFormats.contains(format)
        case .create:
            writableFormats.contains(format)
        }
    }
}

/// 归档引擎协议.
public protocol ArchiveEngine: Sendable {
    var identifier: String { get }
    var capabilities: ArchiveEngineCapabilities { get }

    func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry]
    func extract(_ request: ExtractionRequest, progress: ArchiveProgressHandler?) async throws
    func create(_ request: CompressionRequest, progress: ArchiveProgressHandler?) async throws
}

extension ArchiveEngine {
    public func canHandle(format: ArchiveFormat, operation: ArchiveOperation) -> Bool {
        capabilities.supports(format: format, operation: operation)
    }
}
