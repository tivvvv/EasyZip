import Foundation

/// 表示外部工具的可用状态.
public struct ExternalToolAvailability: Equatable, Sendable {
    public let name: String
    public let executableURL: URL?

    public var isAvailable: Bool {
        executableURL != nil
    }

    public init(name: String, executableURL: URL?) {
        self.name = name
        self.executableURL = executableURL
    }
}

/// 查找可执行的外部 `rar` 命令.
public struct RARCommandResolver: Sendable {
    public static let toolName = "rar"
    public static let defaultCandidatePaths = [
        "/opt/homebrew/bin/rar",
        "/usr/local/bin/rar",
        "/usr/bin/rar"
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
