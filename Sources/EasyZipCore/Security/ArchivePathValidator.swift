import Foundation

/// 校验归档条目的目标路径, 防止路径逃逸.
public struct ArchivePathValidator: Sendable {
    private let destinationURL: URL

    public init(destinationURL: URL) {
        self.destinationURL = destinationURL.standardizedFileURL
    }

    public func validatedDestination(for entryPath: String) throws -> URL {
        let normalizedPath = entryPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !normalizedPath.isEmpty else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        guard !entryPath.hasPrefix("/") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        guard !normalizedPath.contains("\0") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        let components = normalizedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        if let firstComponent = components.first,
           firstComponent.count == 2,
           firstComponent.last == ":",
           firstComponent.first?.isLetter == true {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        let candidateURL = components.reduce(destinationURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }.standardizedFileURL

        let basePath = destinationURL.path
        let candidatePath = candidateURL.path

        guard candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        return candidateURL
    }
}
