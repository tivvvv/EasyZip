import Foundation

/// 规划安全的归档输出写入, 避免提前删除已有目标.
struct CompressionDestinationPlanner: Sendable {
    private var fileManager: FileManager {
        .default
    }

    func validate(destinationURL: URL, sourceURLs: [URL]) throws {
        let destinationURL = destinationURL.standardizedFileURL
        let destinationPath = destinationURL.path

        for sourceURL in sourceURLs {
            let standardizedSourceURL = sourceURL.standardizedFileURL
            var isDirectory = ObjCBool(false)

            guard fileManager.fileExists(atPath: standardizedSourceURL.path, isDirectory: &isDirectory) else {
                throw ArchiveError.invalidSource(sourceURL)
            }

            guard standardizedSourceURL.path != destinationPath else {
                throw ArchiveError.invalidDestination(destinationURL)
            }

            if isDirectory.boolValue,
               destinationPath.hasPrefix(standardizedSourceURL.path + "/") {
                throw ArchiveError.invalidDestination(destinationURL)
            }
        }

        try validateReplaceableDestination(destinationURL)
    }

    func makeTemporaryDestinationURL(for destinationURL: URL) throws -> URL {
        let destinationURL = destinationURL.standardizedFileURL
        let parentURL = destinationURL.deletingLastPathComponent()

        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        var candidateURL: URL

        repeat {
            candidateURL = parentURL.appendingPathComponent(
                ".\(destinationURL.lastPathComponent).easyzip-\(UUID().uuidString).tmp"
            )
        } while fileManager.fileExists(atPath: candidateURL.path)

        return candidateURL
    }

    func finalizeTemporaryDestination(_ temporaryURL: URL, destinationURL: URL) throws {
        let destinationURL = destinationURL.standardizedFileURL

        try validateReplaceableDestination(destinationURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    func removeTemporaryDestination(_ temporaryURL: URL) {
        try? fileManager.removeItem(at: temporaryURL)
    }

    private func validateReplaceableDestination(_ destinationURL: URL) throws {
        var isDirectory = ObjCBool(false)

        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) else {
            return
        }

        guard !isDirectory.boolValue, !isSymbolicLink(destinationURL) else {
            throw ArchiveError.invalidDestination(destinationURL)
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
