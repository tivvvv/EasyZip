/// 管理可用归档引擎.
public actor ArchiveEngineRegistry {
    private var engines: [any ArchiveEngine]

    public init(engines: [any ArchiveEngine] = []) {
        self.engines = engines
    }

    public func register(_ engine: any ArchiveEngine) {
        engines.append(engine)
    }

    public func engine(for format: ArchiveFormat, operation: ArchiveOperation) throws -> any ArchiveEngine {
        guard let engine = engines.first(where: { $0.canHandle(format: format, operation: operation) }) else {
            throw ArchiveError.unsupportedOperation(format: format, operation: operation)
        }

        return engine
    }
}
