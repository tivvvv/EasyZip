import Foundation

/// 查找可执行的外部 `zstd` 命令.
public struct ZstdCommandResolver: Sendable {
    public static let toolName = "zstd"
    public static let defaultCandidatePaths = [
        "/opt/homebrew/bin/zstd",
        "/usr/local/bin/zstd",
        "/usr/bin/zstd"
    ]

    private let explicitExecutableURL: URL?
    private let candidatePaths: [String]
    private let pathValue: String

    private var fileManager: FileManager {
        .default
    }

    public init(
        executableURL: URL? = nil,
        candidatePaths: [String] = Self.defaultCandidatePaths,
        pathValue: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.explicitExecutableURL = executableURL
        self.candidatePaths = candidatePaths
        self.pathValue = pathValue
    }

    public func availability() -> ExternalToolAvailability {
        ExternalToolAvailability(
            name: Self.toolName,
            executableURL: firstExecutableURL()
        )
    }

    public func executableURL() throws -> URL {
        guard let executableURL = firstExecutableURL() else {
            throw ArchiveError.externalToolUnavailable(Self.toolName)
        }

        return executableURL
    }

    private func firstExecutableURL() -> URL? {
        if let explicitExecutableURL {
            return fileManager.isExecutableFile(atPath: explicitExecutableURL.path)
                ? explicitExecutableURL
                : nil
        }

        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        for directory in pathValue.split(separator: ":").map(String.init) {
            let candidateURL = URL(fileURLWithPath: directory)
                .appendingPathComponent(Self.toolName)

            if fileManager.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }
}
