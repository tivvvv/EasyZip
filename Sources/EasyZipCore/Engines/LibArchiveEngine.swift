import Foundation

/// 基于 libarchive 的归档引擎.
public struct LibArchiveEngine: ArchiveEngine {
    public let identifier = "libarchive"

    public let capabilities = ArchiveEngineCapabilities(
        readableFormats: [.zip, .sevenZip],
        writableFormats: [.zip, .sevenZip]
    )

    private let bufferSize: Int

    private var fileManager: FileManager {
        .default
    }

    public init(bufferSize: Int = 64 * 1024) {
        self.bufferSize = bufferSize
    }

    public func listEntries(in archiveURL: URL) async throws -> [ArchiveEntry] {
        let archive = try makeReader(for: archiveURL)
        defer {
            _ = archive_read_close(archive)
            _ = archive_read_free(archive)
        }

        var entries: [ArchiveEntry] = []
        var rawEntry: OpaquePointer?

        while true {
            try Task.checkCancellation()

            let status = archive_read_next_header(archive, &rawEntry)
            if status == LibArchiveStatus.eof {
                break
            }

            try require(status, archive: archive, operation: "read header")

            guard let rawEntry else {
                throw engineFailure(archive: archive, operation: "read header")
            }

            entries.append(makeArchiveEntry(from: rawEntry))
            try skipEntryData(in: archive)
        }

        return entries
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        try fileManager.createDirectory(
            at: request.destinationURL,
            withIntermediateDirectories: true
        )

        let archive = try makeReader(for: request.archiveURL)
        defer {
            _ = archive_read_close(archive)
            _ = archive_read_free(archive)
        }

        let pathValidator = ArchivePathValidator(destinationURL: request.destinationURL)
        var completedCount: Int64 = 0
        var rawEntry: OpaquePointer?

        progress?(
            ArchiveProgress(
                phase: .extracting,
                completedUnitCount: completedCount
            )
        )

        while true {
            try Task.checkCancellation()

            let status = archive_read_next_header(archive, &rawEntry)
            if status == LibArchiveStatus.eof {
                break
            }

            try require(status, archive: archive, operation: "read header")

            guard let rawEntry else {
                throw engineFailure(archive: archive, operation: "read header")
            }

            let entryPath = try pathname(for: rawEntry)
            let destinationURL = try destinationURL(
                for: entryPath,
                baseURL: request.destinationURL,
                validator: pathValidator,
                shouldValidate: request.options.validateEntryPaths
            )

            try extractEntry(
                rawEntry,
                from: archive,
                to: destinationURL,
                options: request.options
            )

            completedCount += 1
            progress?(
                ArchiveProgress(
                    phase: .extracting,
                    completedUnitCount: completedCount,
                    currentEntryPath: entryPath
                )
            )
        }

        progress?(
            ArchiveProgress(
                phase: .finishing,
                completedUnitCount: completedCount
            )
        )
    }

    public func create(
        _ request: CompressionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        guard !request.sourceURLs.isEmpty else {
            throw ArchiveError.invalidSource(request.destinationURL)
        }

        try prepareDestinationForCreation(request.destinationURL)

        let archive = try makeWriter(for: request)
        var didCloseArchive = false
        defer {
            if !didCloseArchive {
                _ = archive_write_close(archive)
            }
            _ = archive_write_free(archive)
        }

        let sourceItems = try makeSourceItems(for: request)
        var completedCount: Int64 = 0

        progress?(
            ArchiveProgress(
                phase: .compressing,
                completedUnitCount: completedCount,
                totalUnitCount: Int64(sourceItems.count)
            )
        )

        for sourceItem in sourceItems {
            try Task.checkCancellation()

            try write(sourceItem, to: archive, options: request.options)
            completedCount += 1

            progress?(
                ArchiveProgress(
                    phase: .compressing,
                    completedUnitCount: completedCount,
                    totalUnitCount: Int64(sourceItems.count),
                    currentEntryPath: sourceItem.archivePath
                )
            )
        }

        try require(
            archive_write_close(archive),
            archive: archive,
            operation: "close archive"
        )
        didCloseArchive = true

        progress?(
            ArchiveProgress(
                phase: .finishing,
                completedUnitCount: completedCount,
                totalUnitCount: Int64(sourceItems.count)
            )
        )
    }
}

private extension LibArchiveEngine {
    struct SourceItem {
        let fileURL: URL
        let archivePath: String
        let attributes: [FileAttributeKey: Any]

        var fileType: FileAttributeType? {
            attributes[.type] as? FileAttributeType
        }
    }

    func makeReader(for archiveURL: URL) throws -> OpaquePointer {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw ArchiveError.invalidSource(archiveURL)
        }

        guard let archive = archive_read_new() else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Failed to allocate archive reader."
            )
        }

        do {
            try require(
                archive_read_support_filter_all(archive),
                archive: archive,
                operation: "enable filters"
            )
            try require(
                archive_read_support_format_zip(archive),
                archive: archive,
                operation: "enable zip reader"
            )
            try require(
                archive_read_support_format_7zip(archive),
                archive: archive,
                operation: "enable 7z reader"
            )
            try archiveURL.path.withCString { path in
                try require(
                    archive_read_open_filename(archive, path, bufferSize),
                    archive: archive,
                    operation: "open archive"
                )
            }

            return archive
        } catch {
            _ = archive_read_free(archive)
            throw error
        }
    }

    func makeWriter(for request: CompressionRequest) throws -> OpaquePointer {
        guard let archive = archive_write_new() else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Failed to allocate archive writer."
            )
        }

        do {
            switch request.format {
            case .zip:
                try require(
                    archive_write_set_format_zip(archive),
                    archive: archive,
                    operation: "enable zip writer"
                )
            case .sevenZip:
                try require(
                    archive_write_set_format_7zip(archive),
                    archive: archive,
                    operation: "enable 7z writer"
                )
            }

            try request.destinationURL.path.withCString { path in
                try require(
                    archive_write_open_filename(archive, path),
                    archive: archive,
                    operation: "open archive writer"
                )
            }

            return archive
        } catch {
            _ = archive_write_free(archive)
            throw error
        }
    }

    func makeArchiveEntry(from rawEntry: OpaquePointer) -> ArchiveEntry {
        let path = stringValue(
            archive_entry_pathname_utf8(rawEntry)
        ) ?? stringValue(
            archive_entry_pathname(rawEntry)
        ) ?? ""

        let symlinkTarget = stringValue(
            archive_entry_symlink_utf8(rawEntry)
        ) ?? stringValue(
            archive_entry_symlink(rawEntry)
        )

        let kind = entryKind(fileType: archive_entry_filetype(rawEntry), symlinkTarget: symlinkTarget)
        let uncompressedSize = archive_entry_size_is_set(rawEntry) == 0
            ? nil
            : archive_entry_size(rawEntry)
        let modifiedAt = archive_entry_mtime_is_set(rawEntry) == 0
            ? nil
            : Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(rawEntry)))

        return ArchiveEntry(
            path: path,
            kind: kind,
            uncompressedSize: uncompressedSize,
            modifiedAt: modifiedAt,
            permissions: UInt16(archive_entry_perm(rawEntry))
        )
    }

    func entryKind(fileType: UInt32, symlinkTarget: String?) -> ArchiveEntryKind {
        switch fileType {
        case LibArchiveFileType.regular:
            return .file
        case LibArchiveFileType.directory:
            return .directory
        case LibArchiveFileType.symbolicLink:
            return .symbolicLink(target: symlinkTarget)
        default:
            return .other
        }
    }

    func destinationURL(
        for entryPath: String,
        baseURL: URL,
        validator: ArchivePathValidator,
        shouldValidate: Bool
    ) throws -> URL {
        if shouldValidate {
            return try validator.validatedDestination(for: entryPath)
        }

        return baseURL.appendingPathComponent(entryPath)
    }

    func extractEntry(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        to destinationURL: URL,
        options: ExtractionOptions
    ) throws {
        switch archive_entry_filetype(rawEntry) {
        case LibArchiveFileType.directory:
            try createDirectory(at: destinationURL)
            try skipEntryData(in: archive)
        case LibArchiveFileType.symbolicLink:
            try extractSymbolicLink(rawEntry, from: archive, to: destinationURL, options: options)
        case LibArchiveFileType.regular:
            try extractFile(rawEntry, from: archive, to: destinationURL, options: options)
        default:
            try skipEntryData(in: archive)
        }
    }

    func extractFile(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        to destinationURL: URL,
        options: ExtractionOptions
    ) throws {
        guard try shouldWrite(to: destinationURL, options: options) else {
            try skipEntryData(in: archive)
            return
        }

        try createDirectory(at: destinationURL.deletingLastPathComponent())
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ArchiveError.invalidDestination(destinationURL)
        }

        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            fileHandle.closeFile()
        }

        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let readCount = archive_read_data(archive, &buffer, buffer.count)
            if readCount == 0 {
                break
            }

            guard readCount > 0 else {
                throw engineFailure(archive: archive, operation: "read file data")
            }

            fileHandle.write(Data(buffer.prefix(readCount)))
        }

        if options.preservePermissions {
            try applyPermissions(from: rawEntry, to: destinationURL)
        }
    }

    func extractSymbolicLink(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        to destinationURL: URL,
        options: ExtractionOptions
    ) throws {
        guard let target = stringValue(archive_entry_symlink_utf8(rawEntry))
            ?? stringValue(archive_entry_symlink(rawEntry)) else {
            try skipEntryData(in: archive)
            return
        }

        try validateSymbolicLinkTarget(target)

        guard try shouldWrite(to: destinationURL, options: options) else {
            try skipEntryData(in: archive)
            return
        }

        try createDirectory(at: destinationURL.deletingLastPathComponent())
        try fileManager.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: target)
        try skipEntryData(in: archive)
    }

    func shouldWrite(to destinationURL: URL, options: ExtractionOptions) throws -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return true
        }

        switch options.overwritePolicy {
        case .overwrite:
            try fileManager.removeItem(at: destinationURL)
            return true
        case .skip, .ask:
            return false
        case .rename:
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Rename overwrite policy is not supported by LibArchiveEngine."
            )
        }
    }

    func validateSymbolicLinkTarget(_ target: String) throws {
        let normalizedTarget = target.replacingOccurrences(of: "\\", with: "/")

        guard !normalizedTarget.hasPrefix("/") else {
            throw ArchiveError.unsafeEntryPath(target)
        }

        let components = normalizedTarget.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveError.unsafeEntryPath(target)
        }
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func applyPermissions(from rawEntry: OpaquePointer, to destinationURL: URL) throws {
        let permissions = archive_entry_perm(rawEntry)
        guard permissions > 0 else {
            return
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: destinationURL.path
        )
    }

    func prepareDestinationForCreation(_ destinationURL: URL) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        try createDirectory(at: parentURL)

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }

        try fileManager.removeItem(at: destinationURL)
    }

    func makeSourceItems(for request: CompressionRequest) throws -> [SourceItem] {
        let destinationPath = request.destinationURL.standardizedFileURL.path
        var items: [SourceItem] = []

        for sourceURL in request.sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw ArchiveError.invalidSource(sourceURL)
            }

            guard request.options.includeHiddenFiles || !isHidden(sourceURL) else {
                continue
            }

            let baseURL = request.options.preserveParentDirectory
                ? sourceURL.deletingLastPathComponent()
                : sourceURL

            if request.options.preserveParentDirectory || !isDirectory(sourceURL) {
                try appendSourceItem(
                    sourceURL,
                    baseURL: baseURL,
                    destinationPath: destinationPath,
                    to: &items
                )
            }

            if isDirectory(sourceURL) {
                try appendChildSourceItems(
                    sourceURL,
                    baseURL: baseURL,
                    destinationPath: destinationPath,
                    options: request.options,
                    to: &items
                )
            }
        }

        return items.sorted { $0.archivePath < $1.archivePath }
    }

    func appendChildSourceItems(
        _ directoryURL: URL,
        baseURL: URL,
        destinationPath: String,
        options: CompressionOptions,
        to items: inout [SourceItem]
    ) throws {
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for childURL in childURLs {
            guard options.includeHiddenFiles || !isHidden(childURL) else {
                continue
            }

            try appendSourceItem(
                childURL,
                baseURL: baseURL,
                destinationPath: destinationPath,
                to: &items
            )

            if isDirectory(childURL) {
                try appendChildSourceItems(
                    childURL,
                    baseURL: baseURL,
                    destinationPath: destinationPath,
                    options: options,
                    to: &items
                )
            }
        }
    }

    func appendSourceItem(
        _ fileURL: URL,
        baseURL: URL,
        destinationPath: String,
        to items: inout [SourceItem]
    ) throws {
        let standardizedURL = fileURL.standardizedFileURL

        guard standardizedURL.path != destinationPath else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: standardizedURL.path)
        let fileType = attributes[.type] as? FileAttributeType

        guard fileType == .typeRegular || fileType == .typeDirectory || fileType == .typeSymbolicLink else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Unsupported source file type: \(standardizedURL.path)"
            )
        }

        let archivePath = try archivePath(for: standardizedURL, baseURL: baseURL)

        items.append(
            SourceItem(
                fileURL: standardizedURL,
                archivePath: archivePath,
                attributes: attributes
            )
        )
    }

    func archivePath(for fileURL: URL, baseURL: URL) throws -> String {
        let filePath = fileURL.standardizedFileURL.path
        let basePath = baseURL.standardizedFileURL.path

        if filePath == basePath {
            return fileURL.lastPathComponent
        }

        guard filePath.hasPrefix(basePath + "/") else {
            throw ArchiveError.invalidSource(fileURL)
        }

        return String(filePath.dropFirst(basePath.count + 1))
    }

    func write(
        _ sourceItem: SourceItem,
        to archive: OpaquePointer,
        options: CompressionOptions
    ) throws {
        guard let entry = archive_entry_new() else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Failed to allocate archive entry."
            )
        }
        defer {
            archive_entry_free(entry)
        }

        try configure(entry, for: sourceItem, options: options)

        try require(
            archive_write_header(archive, entry),
            archive: archive,
            operation: "write header"
        )

        if sourceItem.fileType == .typeRegular {
            try writeFileData(from: sourceItem.fileURL, to: archive)
        }

        try require(
            archive_write_finish_entry(archive),
            archive: archive,
            operation: "finish entry"
        )
    }

    func configure(
        _ entry: OpaquePointer,
        for sourceItem: SourceItem,
        options: CompressionOptions
    ) throws {
        sourceItem.archivePath.withCString { path in
            archive_entry_copy_pathname(entry, path)
        }

        let permissions = UInt32(
            sourceItem.attributes[.posixPermissions] as? Int ?? defaultPermissions(for: sourceItem)
        )
        archive_entry_set_perm(entry, permissions)

        if let modifiedAt = sourceItem.attributes[.modificationDate] as? Date {
            archive_entry_set_mtime(entry, Int64(modifiedAt.timeIntervalSince1970), 0)
        }

        switch sourceItem.fileType {
        case .typeDirectory:
            archive_entry_set_filetype(entry, LibArchiveFileType.directory)
            archive_entry_set_size(entry, 0)
        case .typeSymbolicLink:
            archive_entry_set_filetype(entry, LibArchiveFileType.symbolicLink)
            archive_entry_set_size(entry, 0)
            try linkDestination(for: sourceItem.fileURL).withCString { target in
                archive_entry_copy_symlink(entry, target)
            }
        case .typeRegular:
            archive_entry_set_filetype(entry, LibArchiveFileType.regular)
            archive_entry_set_size(entry, fileSize(for: sourceItem))
        default:
            archive_entry_set_filetype(entry, LibArchiveFileType.regular)
            archive_entry_set_size(entry, fileSize(for: sourceItem))
        }
    }

    func writeFileData(from fileURL: URL, to archive: OpaquePointer) throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            fileHandle.closeFile()
        }

        while true {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty {
                break
            }

            try data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return
                }

                let writtenCount = archive_write_data(archive, baseAddress, buffer.count)
                guard writtenCount >= 0 else {
                    throw engineFailure(archive: archive, operation: "write file data")
                }
            }
        }
    }

    func linkDestination(for fileURL: URL) throws -> String {
        let target = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
        try validateSymbolicLinkTarget(target)
        return target
    }

    func fileSize(for sourceItem: SourceItem) -> Int64 {
        let size = sourceItem.attributes[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    func defaultPermissions(for sourceItem: SourceItem) -> Int {
        sourceItem.fileType == .typeDirectory ? 0o755 : 0o644
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
    }

    func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".")
    }

    func pathname(for rawEntry: OpaquePointer) throws -> String {
        guard let path = stringValue(archive_entry_pathname_utf8(rawEntry))
            ?? stringValue(archive_entry_pathname(rawEntry)),
            !path.isEmpty else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Archive entry has no path."
            )
        }

        return path
    }

    func skipEntryData(in archive: OpaquePointer) throws {
        try require(
            archive_read_data_skip(archive),
            archive: archive,
            operation: "skip entry data"
        )
    }

    func require(
        _ status: Int32,
        archive: OpaquePointer,
        operation: String
    ) throws {
        guard status == LibArchiveStatus.ok else {
            throw engineFailure(archive: archive, operation: operation)
        }
    }

    func engineFailure(archive: OpaquePointer?, operation: String) -> ArchiveError {
        let message = stringValue(archive_error_string(archive)) ?? "Unknown libarchive error."

        return .engineFailure(
            engine: identifier,
            message: "\(operation): \(message)"
        )
    }

    func stringValue(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }
}
