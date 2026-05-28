/// 归档任务进度.
public struct ArchiveProgress: Equatable, Sendable {
    public let phase: ArchiveProgressPhase
    public let completedUnitCount: Int64
    public let totalUnitCount: Int64?
    public let currentEntryPath: String?

    public init(
        phase: ArchiveProgressPhase,
        completedUnitCount: Int64,
        totalUnitCount: Int64? = nil,
        currentEntryPath: String? = nil
    ) {
        self.phase = phase
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.currentEntryPath = currentEntryPath
    }
}

/// 归档任务阶段.
public enum ArchiveProgressPhase: Equatable, Sendable {
    case scanning
    case reading
    case writing
    case extracting
    case compressing
    case finishing
}

public typealias ArchiveProgressHandler = @Sendable (ArchiveProgress) -> Void
