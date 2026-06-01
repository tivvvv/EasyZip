import Foundation

/// 通过已安装的外部 `rar` 命令创建 RAR 归档.
public struct RARCommandCompressionEngine: ArchiveEngine {
    public let identifier = "rar-command"

    public let capabilities = ArchiveEngineCapabilities(
        readableFormats: [],
        writableFormats: [.rar]
    )

    private let commandResolver: RARCommandResolver

    private var fileManager: FileManager {
        .default
    }

    public init(commandResolver: RARCommandResolver = RARCommandResolver()) {
        self.commandResolver = commandResolver
    }

    public init(executableURL: URL?) {
        self.commandResolver = RARCommandResolver(executableURL: executableURL)
    }

    public func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry] {
        throw ArchiveError.unsupportedOperation(format: .rar, operation: .list)
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        throw ArchiveError.unsupportedOperation(format: .rar, operation: .extract)
    }

    public func create(
        _ request: CompressionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        guard request.format == .rar else {
            throw ArchiveError.unsupportedOperation(format: request.format, operation: .create)
        }

        guard !request.sourceURLs.isEmpty else {
            throw ArchiveError.invalidSource(request.destinationURL)
        }

        let destinationPlanner = CompressionDestinationPlanner()
        try destinationPlanner.validate(
            destinationURL: request.destinationURL,
            sourceURLs: request.sourceURLs
        )

        let executableURL = try commandResolver.executableURL()
        let temporaryDestinationURL = try destinationPlanner.makeTemporaryDestinationURL(
            for: request.destinationURL
        )
        var didFinalizeDestination = false
        defer {
            if !didFinalizeDestination {
                destinationPlanner.removeTemporaryDestination(temporaryDestinationURL)
            }
        }

        let totalByteCount = try regularFileByteCount(in: request.sourceURLs)
        progress?(
            ArchiveProgress(
                phase: .compressing,
                completedUnitCount: 0,
                totalUnitCount: totalByteCount
            )
        )

        try Task.checkCancellation()
        try await runRAR(
            executableURL: executableURL,
            arguments: makeArguments(
                for: request,
                temporaryDestinationURL: temporaryDestinationURL
            )
        )
        try Task.checkCancellation()

        try destinationPlanner.finalizeTemporaryDestination(
            temporaryDestinationURL,
            destinationURL: request.destinationURL
        )
        didFinalizeDestination = true

        progress?(
            ArchiveProgress(
                phase: .finishing,
                completedUnitCount: totalByteCount ?? 0,
                totalUnitCount: totalByteCount
            )
        )
    }
}

private final class RARProcessBox: @unchecked Sendable {
    let process = Process()
    let standardError = Pipe()
    let standardOutput = Pipe()

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

private extension RARCommandCompressionEngine {
    func makeArguments(
        for request: CompressionRequest,
        temporaryDestinationURL: URL
    ) throws -> [String] {
        var arguments = [
            "a",
            "-idq",
            "-y",
            "-ep1",
            compressionLevelArgument(for: request.options.compressionLevel)
        ]

        if !request.options.includeHiddenFiles {
            arguments.append(contentsOf: ["-x.*", "-x*/.*"])
        }

        arguments.append(temporaryDestinationURL.path)
        arguments.append(contentsOf: try sourceArguments(for: request))
        return arguments
    }

    func sourceArguments(for request: CompressionRequest) throws -> [String] {
        guard !request.options.preserveParentDirectory,
              request.sourceURLs.count == 1,
              let sourceURL = request.sourceURLs.first,
              isDirectory(sourceURL) else {
            return request.sourceURLs.map(\.path)
        }

        let childURLs = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil
        ).filter { request.options.includeHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }

        guard !childURLs.isEmpty else {
            return [sourceURL.path]
        }

        return childURLs.map(\.path)
    }

    func compressionLevelArgument(for level: CompressionLevel) -> String {
        switch level {
        case .fastest:
            "-m1"
        case .balanced:
            "-m3"
        case .maximum:
            "-m5"
        case .custom(let value):
            "-m\(min(max(value, 0), 5))"
        }
    }

    func runRAR(executableURL: URL, arguments: [String]) async throws {
        let processBox = RARProcessBox()

        processBox.process.executableURL = executableURL
        processBox.process.arguments = arguments
        processBox.process.standardError = processBox.standardError
        processBox.process.standardOutput = processBox.standardOutput

        let terminationStatus: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                processBox.process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }

                do {
                    try processBox.process.run()
                } catch {
                    continuation.resume(
                        throwing: ArchiveError.externalToolUnavailable(RARCommandResolver.toolName)
                    )
                }
            }
        } onCancel: {
            processBox.terminate()
        }

        try Task.checkCancellation()

        guard terminationStatus == 0 else {
            let errorData = processBox.standardError.fileHandleForReading.readDataToEndOfFile()
            let outputData = processBox.standardOutput.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData + outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: message?.isEmpty == false ? message! : "rar exited with status \(terminationStatus)"
            )
        }
    }

    func regularFileByteCount(in urls: [URL]) throws -> Int64? {
        try urls.reduce(Int64(0)) { partialResult, url in
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileType = attributes[.type] as? FileAttributeType

            if fileType == .typeDirectory {
                return try partialResult + (regularFileByteCount(inDirectory: url) ?? 0)
            }

            if fileType == .typeRegular {
                let size = attributes[.size] as? NSNumber
                return partialResult + (size?.int64Value ?? 0)
            }

            return partialResult
        }
    }

    func regularFileByteCount(inDirectory directoryURL: URL) throws -> Int64? {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        return try regularFileByteCount(in: childURLs)
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }
}
