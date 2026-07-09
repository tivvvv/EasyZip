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
        password: String?,
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
                preserveParentDirectory: preserveParentDirectory,
                password: password
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
        shouldCreateContainingDirectory: Bool,
        selectedEntryPaths: Set<String> = [],
        password: String? = nil,
        conflictResolver: ArchiveConflictResolver? = nil,
        progressHandler: ArchiveProgressHandler?
    ) async throws -> TaskResult {
        let service = ArchiveService.makeDefault()
        var destinationURLs: [URL] = []

        for archiveURL in archiveURLs {
            try Task.checkCancellation()

            let selectedEntriesIncludeContainingDirectory = selectedEntriesIncludeContainingDirectory(
                archiveURL: archiveURL,
                selectedEntryPaths: selectedEntryPaths
            )
            let effectiveShouldCreateContainingDirectory = shouldCreateContainingDirectory
                && !selectedEntriesIncludeContainingDirectory
            let destinationURL = extractionDestinationURL(
                archiveURL: archiveURL,
                outputDirectory: outputDirectory,
                shouldCreateContainingDirectory: shouldCreateContainingDirectory
                    || selectedEntriesIncludeContainingDirectory
            )
            destinationURLs.append(destinationURL)

            let request = ExtractionRequest(
                archiveURL: archiveURL,
                destinationURL: baseDestinationURL(
                    archiveURL: archiveURL,
                    outputDirectory: outputDirectory
                ),
                options: ExtractionOptions(
                    overwritePolicy: overwritePolicy,
                    shouldCreateContainingDirectory: effectiveShouldCreateContainingDirectory,
                    conflictResolver: conflictResolver,
                    selectedEntryPaths: selectedEntryPaths,
                    password: password
                )
            )

            try await service.extract(request, progress: progressHandler)
        }

        return TaskResult(
            title: "解压完成",
            detail: extractionResultDetail(
                archiveURLs: archiveURLs,
                selectedEntryCount: selectedEntryPaths.count
            ),
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
        outputDirectory: URL?,
        shouldCreateContainingDirectory: Bool
    ) -> URL {
        let baseDirectory = baseDestinationURL(archiveURL: archiveURL, outputDirectory: outputDirectory)

        guard shouldCreateContainingDirectory else {
            return baseDirectory
        }

        if isSingleFileCompressionArchive(archiveURL) {
            return baseDirectory
        }

        let directoryName = extractionContainingDirectoryName(for: archiveURL)

        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func isSingleFileCompressionArchive(_ archiveURL: URL) -> Bool {
        ArchiveFormat.matching(filename: archiveURL.lastPathComponent)?.isSingleFileCompression == true
    }

    private static func extractionContainingDirectoryName(for archiveURL: URL) -> String {
        let directoryName = ArchiveFormat.removingArchiveExtension(from: archiveURL.lastPathComponent)

        return directoryName.isEmpty ? "归档内容" : directoryName
    }

    private static func selectedEntriesIncludeContainingDirectory(
        archiveURL: URL,
        selectedEntryPaths: Set<String>
    ) -> Bool {
        guard !selectedEntryPaths.isEmpty,
              !isSingleFileCompressionArchive(archiveURL) else {
            return false
        }

        let directoryName = extractionContainingDirectoryName(for: archiveURL)
        let selectedTopLevelNames = Set(selectedEntryPaths.compactMap(topLevelPathComponent))

        return selectedTopLevelNames == [directoryName]
    }

    private static func topLevelPathComponent(in path: String) -> String? {
        path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    private static func baseDestinationURL(
        archiveURL: URL,
        outputDirectory: URL?
    ) -> URL {
        outputDirectory ?? archiveURL.deletingLastPathComponent()
    }

    private static func extractionResultDetail(
        archiveURLs: [URL],
        selectedEntryCount: Int
    ) -> String {
        if selectedEntryCount > 0 {
            return "已解压 \(selectedEntryCount) 项所选内容"
        }

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
