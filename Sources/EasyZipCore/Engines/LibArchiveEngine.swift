import Foundation

/// 基于 libarchive 的归档引擎.
public struct LibArchiveEngine: ArchiveEngine {
    public let identifier = "libarchive"

    public let capabilities = ArchiveEngineCapabilities(
        readableFormats: Set(ArchiveFormat.allCases),
        writableFormats: Set(ArchiveFormat.allCases.filter { $0 != .rar })
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

            try validateEntryIsNotEncrypted(rawEntry, archiveURL: archiveURL)
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

        let totalByteCount = try await totalUncompressedByteCount(in: request.archiveURL)
        let archive = try makeReader(for: request.archiveURL)
        defer {
            _ = archive_read_close(archive)
            _ = archive_read_free(archive)
        }

        let pathValidator = ArchivePathValidator(destinationURL: request.destinationURL)
        var completedByteCount: Int64 = 0
        var rawEntry: OpaquePointer?

        progress?(
            ArchiveProgress(
                phase: .extracting,
                completedUnitCount: completedByteCount,
                totalUnitCount: totalByteCount
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

            try validateEntryIsNotEncrypted(rawEntry, archiveURL: request.archiveURL)
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
                baseURL: request.destinationURL,
                options: request.options
            ) { byteCount in
                completedByteCount += byteCount
                progress?(
                    ArchiveProgress(
                        phase: .extracting,
                        completedUnitCount: completedByteCount,
                        totalUnitCount: totalByteCount,
                        currentEntryPath: entryPath
                    )
                )
            }

            progress?(
                ArchiveProgress(
                    phase: .extracting,
                    completedUnitCount: completedByteCount,
                    totalUnitCount: totalByteCount,
                    currentEntryPath: entryPath
                )
            )
        }

        progress?(
            ArchiveProgress(
                phase: .finishing,
                completedUnitCount: completedByteCount,
                totalUnitCount: totalByteCount
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

        let destinationPlanner = CompressionDestinationPlanner()
        try destinationPlanner.validate(
            destinationURL: request.destinationURL,
            sourceURLs: request.sourceURLs
        )

        let sourceItems = try makeSourceItems(for: request)
        let temporaryDestinationURL = try destinationPlanner.makeTemporaryDestinationURL(
            for: request.destinationURL
        )
        let writerRequest = CompressionRequest(
            sourceURLs: request.sourceURLs,
            destinationURL: temporaryDestinationURL,
            format: request.format,
            options: request.options
        )
        var didFinalizeDestination = false
        defer {
            if !didFinalizeDestination {
                destinationPlanner.removeTemporaryDestination(temporaryDestinationURL)
            }
        }

        let archive = try makeWriter(for: writerRequest)
        var didCloseArchive = false
        defer {
            if !didCloseArchive {
                _ = archive_write_close(archive)
            }
            _ = archive_write_free(archive)
        }

        let totalByteCount = sourceItems.reduce(Int64(0)) { partialResult, sourceItem in
            partialResult + sourceItem.byteCount
        }
        var completedByteCount: Int64 = 0

        progress?(
            ArchiveProgress(
                phase: .compressing,
                completedUnitCount: completedByteCount,
                totalUnitCount: totalByteCount
            )
        )

        for sourceItem in sourceItems {
            try Task.checkCancellation()

            try write(sourceItem, to: archive, options: request.options) { byteCount in
                completedByteCount += byteCount
                progress?(
                    ArchiveProgress(
                        phase: .compressing,
                        completedUnitCount: completedByteCount,
                        totalUnitCount: totalByteCount,
                        currentEntryPath: sourceItem.archivePath
                    )
                )
            }

            progress?(
                ArchiveProgress(
                    phase: .compressing,
                    completedUnitCount: completedByteCount,
                    totalUnitCount: totalByteCount,
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

        try destinationPlanner.finalizeTemporaryDestination(
            temporaryDestinationURL,
            destinationURL: request.destinationURL
        )
        didFinalizeDestination = true

        progress?(
            ArchiveProgress(
                phase: .finishing,
                completedUnitCount: completedByteCount,
                totalUnitCount: totalByteCount
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

        var byteCount: Int64 {
            guard fileType == .typeRegular else {
                return 0
            }

            let size = attributes[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
    }

    func totalUncompressedByteCount(in archiveURL: URL) async throws -> Int64? {
        let entries = try await listEntries(in: archiveURL)
        let fileEntries = entries.filter { entry in
            if case .file = entry.kind {
                return true
            }

            return false
        }
        let fileSizes = fileEntries.compactMap(\.uncompressedSize)

        guard fileSizes.count == fileEntries.count else {
            return nil
        }

        return fileSizes.reduce(0, +)
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
            try require(
                archive_read_support_format_rar(archive),
                archive: archive,
                operation: "enable rar reader"
            )
            try require(
                archive_read_support_format_rar5(archive),
                archive: archive,
                operation: "enable rar5 reader"
            )
            try require(
                archive_read_support_format_tar(archive),
                archive: archive,
                operation: "enable tar reader"
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
            try configureWriter(archive, for: request.format)

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

    func configureWriter(_ archive: OpaquePointer, for format: ArchiveFormat) throws {
        switch format {
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
        case .rar:
            throw ArchiveError.unsupportedOperation(format: format, operation: .create)
        case .tar:
            try configureTarWriter(archive, filter: archive_write_add_filter_none, filterName: "none")
        case .tarGzip:
            try configureTarWriter(archive, filter: archive_write_add_filter_gzip, filterName: "gzip")
        case .tarBzip2:
            try configureTarWriter(archive, filter: archive_write_add_filter_bzip2, filterName: "bzip2")
        case .tarXz:
            try configureTarWriter(archive, filter: archive_write_add_filter_xz, filterName: "xz")
        }
    }

    func configureTarWriter(
        _ archive: OpaquePointer,
        filter: (OpaquePointer?) -> Int32,
        filterName: String
    ) throws {
        try require(
            archive_write_set_format_pax_restricted(archive),
            archive: archive,
            operation: "enable tar writer"
        )
        try require(
            filter(archive),
            archive: archive,
            operation: "enable \(filterName) filter"
        )
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

    func validateEntryIsNotEncrypted(_ rawEntry: OpaquePointer, archiveURL: URL) throws {
        guard archive_entry_is_encrypted(rawEntry) == 0,
              archive_entry_is_data_encrypted(rawEntry) == 0,
              archive_entry_is_metadata_encrypted(rawEntry) == 0 else {
            throw ArchiveError.encryptedArchive(archiveURL)
        }
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
        baseURL: URL,
        options: ExtractionOptions,
        onBytesWritten: (Int64) -> Void
    ) throws {
        let fileType = archive_entry_filetype(rawEntry)
        let resolvedDestinationURL = try destinationURLByResolvingCollision(
            destinationURL,
            fileType: fileType,
            options: options
        )

        guard let resolvedDestinationURL else {
            try skipEntryData(in: archive)
            return
        }

        try validateFilesystemDestination(
            resolvedDestinationURL,
            baseURL: baseURL,
            shouldValidate: options.validateEntryPaths
        )

        switch fileType {
        case LibArchiveFileType.directory:
            try createDirectory(at: resolvedDestinationURL)
            try applyMetadata(from: rawEntry, to: resolvedDestinationURL, options: options)
            try skipEntryData(in: archive)
        case LibArchiveFileType.symbolicLink:
            try extractSymbolicLink(rawEntry, from: archive, to: resolvedDestinationURL)
        case LibArchiveFileType.regular:
            try extractFile(
                rawEntry,
                from: archive,
                to: resolvedDestinationURL,
                options: options,
                onBytesWritten: onBytesWritten
            )
        default:
            try skipEntryData(in: archive)
        }
    }

    func extractFile(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        to destinationURL: URL,
        options: ExtractionOptions,
        onBytesWritten: (Int64) -> Void
    ) throws {
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
            try Task.checkCancellation()

            let readCount = archive_read_data(archive, &buffer, buffer.count)
            if readCount == 0 {
                break
            }

            guard readCount > 0 else {
                throw engineFailure(archive: archive, operation: "read file data")
            }

            fileHandle.write(Data(buffer.prefix(readCount)))
            onBytesWritten(Int64(readCount))
        }

        try applyMetadata(from: rawEntry, to: destinationURL, options: options)
    }

    func extractSymbolicLink(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        to destinationURL: URL
    ) throws {
        guard let target = stringValue(archive_entry_symlink_utf8(rawEntry))
            ?? stringValue(archive_entry_symlink(rawEntry)) else {
            try skipEntryData(in: archive)
            return
        }

        try validateSymbolicLinkTarget(target)

        try createDirectory(at: destinationURL.deletingLastPathComponent())
        try fileManager.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: target)
        try skipEntryData(in: archive)
    }

    func destinationURLByResolvingCollision(
        _ destinationURL: URL,
        fileType: UInt32,
        options: ExtractionOptions
    ) throws -> URL? {
        var isDirectory = ObjCBool(false)

        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) else {
            return destinationURL
        }

        switch options.overwritePolicy {
        case .overwrite:
            if fileType == LibArchiveFileType.directory && isDirectory.boolValue {
                return destinationURL
            }

            try fileManager.removeItem(at: destinationURL)
            return destinationURL
        case .skip, .ask:
            return nil
        case .rename:
            if fileType == LibArchiveFileType.directory && isDirectory.boolValue {
                return destinationURL
            }

            return uniqueDestinationURL(for: destinationURL)
        }
    }

    func uniqueDestinationURL(for destinationURL: URL) -> URL {
        let parentURL = destinationURL.deletingLastPathComponent()
        let pathExtension = destinationURL.pathExtension
        let baseName = pathExtension.isEmpty
            ? destinationURL.lastPathComponent
            : destinationURL.deletingPathExtension().lastPathComponent

        var suffix = 2

        while true {
            let fileName = pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            let candidateURL = parentURL.appendingPathComponent(fileName)

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            suffix += 1
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

    func validateFilesystemDestination(
        _ destinationURL: URL,
        baseURL: URL,
        shouldValidate: Bool
    ) throws {
        guard shouldValidate else {
            return
        }

        let basePath = baseURL.standardizedFileURL.resolvingSymlinksInPath().path
        let parentPath = destinationURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        guard parentPath == basePath || parentPath.hasPrefix(basePath + "/") else {
            throw ArchiveError.unsafeEntryPath(destinationURL.path)
        }

        guard !isSymbolicLink(destinationURL) else {
            throw ArchiveError.unsafeEntryPath(destinationURL.path)
        }
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func applyMetadata(
        from rawEntry: OpaquePointer,
        to destinationURL: URL,
        options: ExtractionOptions
    ) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        let permissions = archive_entry_perm(rawEntry)

        if options.preservePermissions && permissions > 0 {
            attributes[.posixPermissions] = NSNumber(value: permissions)
        }

        if archive_entry_mtime_is_set(rawEntry) != 0 {
            attributes[.modificationDate] = Date(
                timeIntervalSince1970: TimeInterval(archive_entry_mtime(rawEntry))
            )
        }

        guard !attributes.isEmpty else {
            return
        }

        try fileManager.setAttributes(attributes, ofItemAtPath: destinationURL.path)
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
            try Task.checkCancellation()

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
            try Task.checkCancellation()

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
        options: CompressionOptions,
        onBytesWritten: (Int64) -> Void
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
            try writeFileData(from: sourceItem.fileURL, to: archive, onBytesWritten: onBytesWritten)
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

        if options.preserveMetadata,
           let modifiedAt = sourceItem.attributes[.modificationDate] as? Date {
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

    func writeFileData(
        from fileURL: URL,
        to archive: OpaquePointer,
        onBytesWritten: (Int64) -> Void
    ) throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            fileHandle.closeFile()
        }

        while true {
            try Task.checkCancellation()

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

                onBytesWritten(Int64(buffer.count))
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

    func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
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
