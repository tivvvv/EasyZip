import EasyZipCore
import Foundation

enum ArchiveTaskRunner {
    static func compress(
        sourceURLs: [URL],
        outputDirectory: URL?,
        format: ArchiveFormat,
        archiveName: String,
        includeHiddenFiles: Bool,
        preserveParentDirectory: Bool,
        preserveMetadata: Bool,
        progressHandler: ArchiveProgressHandler?
    ) async throws -> TaskResult {
        let destinationURL = compressionDestinationURL(
            sourceURLs: sourceURLs,
            outputDirectory: outputDirectory,
            format: format,
            archiveName: archiveName
        )
        let request = CompressionRequest(
            sourceURLs: sourceURLs,
            destinationURL: destinationURL,
            format: format,
            options: CompressionOptions(
                includeHiddenFiles: includeHiddenFiles,
                preserveMetadata: preserveMetadata,
                preserveParentDirectory: preserveParentDirectory
            )
        )

        try await ArchiveService.makeDefault().create(request, progress: progressHandler)

        return TaskResult(
            title: "压缩完成",
            detail: "已生成 \(destinationURL.lastPathComponent)",
            outputURL: destinationURL,
            iconName: "checkmark.circle"
        )
    }

    static func extract(
        archiveURLs: [URL],
        outputDirectory: URL?,
        overwritePolicy: OverwritePolicy,
        progressHandler: ArchiveProgressHandler?
    ) async throws -> TaskResult {
        let service = ArchiveService.makeDefault()
        var destinationURLs: [URL] = []

        for archiveURL in archiveURLs {
            try Task.checkCancellation()

            let destinationURL = extractionDestinationURL(
                archiveURL: archiveURL,
                outputDirectory: outputDirectory
            )
            destinationURLs.append(destinationURL)

            let request = ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: baseDestinationURL(
                    archiveURL: archiveURL,
                    outputDirectory: outputDirectory
                ),
                options: ExtractionOptions(overwritePolicy: overwritePolicy)
            )

            try await service.extract(request, progress: progressHandler)
        }

        return TaskResult(
            title: "解压完成",
            detail: extractionResultDetail(archiveURLs: archiveURLs),
            outputURL: extractionRevealURL(
                archiveURLs: archiveURLs,
                destinationURLs: destinationURLs,
                outputDirectory: outputDirectory
            ),
            iconName: "checkmark.circle"
        )
    }

    static func compressionFileName(format: ArchiveFormat, archiveName: String) -> String {
        let cleanName = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "归档文件" : cleanName
        let normalizedBaseName = baseName.lowercased()

        if format.fileExtensions.contains(where: { normalizedBaseName.hasSuffix(".\($0)") }) {
            return baseName
        }

        return "\(baseName).\(format.fileExtension)"
    }

    private static func compressionDestinationURL(
        sourceURLs: [URL],
        outputDirectory: URL?,
        format: ArchiveFormat,
        archiveName: String
    ) -> URL {
        let directoryURL = outputDirectory
            ?? sourceURLs.first?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        let fileName = compressionFileName(format: format, archiveName: archiveName)

        return directoryURL.appendingPathComponent(fileName)
    }

    private static func extractionDestinationURL(
        archiveURL: URL,
        outputDirectory: URL?
    ) -> URL {
        let baseDirectory = baseDestinationURL(archiveURL: archiveURL, outputDirectory: outputDirectory)
        let directoryName = extractionContainingDirectoryName(for: archiveURL)

        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func extractionContainingDirectoryName(for archiveURL: URL) -> String {
        let directoryName = ArchiveFormat.removingArchiveExtension(from: archiveURL.lastPathComponent)

        return directoryName.isEmpty ? "归档内容" : directoryName
    }

    private static func baseDestinationURL(
        archiveURL: URL,
        outputDirectory: URL?
    ) -> URL {
        outputDirectory ?? archiveURL.deletingLastPathComponent()
    }

    private static func extractionResultDetail(archiveURLs: [URL]) -> String {
        guard archiveURLs.count == 1, let archiveURL = archiveURLs.first else {
            return "已处理 \(archiveURLs.count) 个归档"
        }

        return "已解压 \(archiveURL.lastPathComponent)"
    }

    private static func extractionRevealURL(
        archiveURLs: [URL],
        destinationURLs: [URL],
        outputDirectory: URL?
    ) -> URL? {
        if archiveURLs.count == 1 {
            return destinationURLs.first
        }

        if let outputDirectory {
            return outputDirectory
        }

        return archiveURLs.first?.deletingLastPathComponent()
    }
}
