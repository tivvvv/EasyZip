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

            try requireReadStatus(
                status,
                archive: archive,
                archiveURL: archiveURL,
                operation: "read header"
            )

            guard let rawEntry else {
                throw engineFailure(archive: archive, operation: "read header")
            }

            entries.append(makeArchiveEntry(from: rawEntry))
            try skipEntryData(in: archive, archiveURL: archiveURL)
        }

        return entries
    }

    public func extract(
        _ request: ExtractionRequest,
        progress: ArchiveProgressHandler? = nil
    ) async throws {
        let destinationRootURL = extractionRootURL(for: request)
        progress?(
            ArchiveProgress(
                phase: .scanning,
                completedUnitCount: 0
            )
        )

        let extractionPlan = try await scanExtractionPlan(
            in: request.archiveURL,
            destinationRootURL: destinationRootURL,
            options: request.options
        )

        try fileManager.createDirectory(
            at: destinationRootURL,
            withIntermediateDirectories: true
        )

        let totalByteCount = extractionPlan.totalUncompressedByteCount
        let archive = try makeReader(
            for: request.archiveURL,
            password: request.options.password
        )
        defer {
            _ = archive_read_close(archive)
            _ = archive_read_free(archive)
        }

        let pathValidator = ArchivePathValidator(destinationURL: destinationRootURL)
        let entrySelector = LibArchiveExtractionEntrySelector(
            selectedPaths: request.options.selectedEntryPaths
        )
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

            try requireReadStatus(
                status,
                archive: archive,
                archiveURL: request.archiveURL,
                operation: "read header"
            )

            guard let rawEntry else {
                throw engineFailure(archive: archive, operation: "read header")
            }

            let entryPath = try pathname(for: rawEntry)
            let fileType = archive_entry_filetype(rawEntry)

            guard entrySelector.shouldExtract(entryPath: entryPath, fileType: fileType) else {
                try skipEntryData(in: archive, archiveURL: request.archiveURL)
                continue
            }

            try validateEntryCanBeRead(
                rawEntry,
                archiveURL: request.archiveURL,
                options: request.options
            )
            let destinationURL = try destinationURL(
                for: entryPath,
                baseURL: destinationRootURL,
                validator: pathValidator,
                shouldValidate: request.options.validateEntryPaths
            )
            var completedEntryByteCount: Int64 = 0

            try extractEntry(
                rawEntry,
                from: archive,
                archiveURL: request.archiveURL,
                to: destinationURL,
                baseURL: destinationRootURL,
                entryPath: entryPath,
                options: request.options,
                onBytesWillWrite: { byteCount in
                    try validateResourceLimitsBeforeWriting(
                        byteCount: byteCount,
                        entryPath: entryPath,
                        currentEntryByteCount: completedEntryByteCount,
                        completedByteCount: completedByteCount,
                        limits: request.options.resourceLimits
                    )
                },
                onBytesWritten: { byteCount in
                    completedEntryByteCount += byteCount
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
            )

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

    struct ExtractionPlan {
        let totalUncompressedByteCount: Int64?
    }

    func scanExtractionPlan(
        in archiveURL: URL,
        destinationRootURL: URL,
        options: ExtractionOptions
    ) async throws -> ExtractionPlan {
        let archive = try makeReader(for: archiveURL, password: options.password)
        defer {
            _ = archive_read_close(archive)
            _ = archive_read_free(archive)
        }

        let pathValidator = ArchivePathValidator(destinationURL: destinationRootURL)
        let entrySelector = LibArchiveExtractionEntrySelector(
            selectedPaths: options.selectedEntryPaths
        )
        var entryCount = 0
        var totalUncompressedByteCount: Int64 = 0
        var hasUnknownUncompressedSize = false
        var rawEntry: OpaquePointer?

        while true {
            try Task.checkCancellation()

            let status = archive_read_next_header(archive, &rawEntry)
            if status == LibArchiveStatus.eof {
                break
            }

            try requireReadStatus(
                status,
                archive: archive,
                archiveURL: archiveURL,
                operation: "read header"
            )

            guard let rawEntry else {
                throw engineFailure(archive: archive, operation: "read header")
            }

            let entryPath = try pathname(for: rawEntry)
            let fileType = archive_entry_filetype(rawEntry)

            guard entrySelector.shouldExtract(entryPath: entryPath, fileType: fileType) else {
                try skipEntryData(in: archive, archiveURL: archiveURL)
                continue
            }

            try validateEntryCanBeRead(rawEntry, archiveURL: archiveURL, options: options)
            entryCount += 1

            try validateEntryCount(entryCount, limits: options.resourceLimits)
            if options.validateEntryPaths {
                _ = try pathValidator.validatedDestination(for: entryPath)
            }
            try validateDirectoryDepth(
                entryPath: entryPath,
                fileType: fileType,
                limits: options.resourceLimits
            )
            try validateSupportedEntryForExtraction(
                rawEntry,
                entryPath: entryPath,
                fileType: fileType
            )
            try validateSymbolicLinkTargetIfNeeded(rawEntry, fileType: fileType)

            if fileType == LibArchiveFileType.regular {
                if let entrySize = try uncompressedSize(for: rawEntry, entryPath: entryPath) {
                    try validateSingleFileSize(
                        entrySize,
                        entryPath: entryPath,
                        limits: options.resourceLimits
                    )
                    totalUncompressedByteCount = try checkedLimitedResourceSizeSum(
                        totalUncompressedByteCount,
                        entrySize,
                        limit: options.resourceLimits.maxTotalUncompressedSize
                    ) { limit, actual in
                        .totalUncompressedSize(limit: limit, actual: actual)
                    }
                } else {
                    hasUnknownUncompressedSize = true
                }
            }

            try skipEntryData(in: archive, archiveURL: archiveURL)
        }

        return ExtractionPlan(
            totalUncompressedByteCount: hasUnknownUncompressedSize ? nil : totalUncompressedByteCount
        )
    }

    func extractionRootURL(for request: ExtractionRequest) -> URL {
        guard request.options.shouldCreateContainingDirectory else {
            return request.destinationURL
        }

        let directoryName = ArchiveFormat.removingArchiveExtension(
            from: request.archiveURL.lastPathComponent
        )
        let safeDirectoryName = directoryName.isEmpty ? "归档内容" : directoryName

        return request.destinationURL.appendingPathComponent(safeDirectoryName, isDirectory: true)
    }

    func makeReader(for archiveURL: URL, password: String? = nil) throws -> OpaquePointer {
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
            try addPassword(password, to: archive, archiveURL: archiveURL)
            try archiveURL.path.withCString { path in
                try requireReadStatus(
                    archive_read_open_filename(archive, path, bufferSize),
                    archive: archive,
                    archiveURL: archiveURL,
                    operation: "open archive"
                )
            }

            return archive
        } catch {
            _ = archive_read_free(archive)
            throw error
        }
    }

    func addPassword(
        _ password: String?,
        to archive: OpaquePointer,
        archiveURL: URL
    ) throws {
        guard let password, !password.isEmpty else {
            return
        }

        try password.withCString { passphrase in
            try requireReadStatus(
                archive_read_add_passphrase(archive, passphrase),
                archive: archive,
                archiveURL: archiveURL,
                operation: "add archive password"
            )
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
            try configureWriter(archive, for: request)

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

    func configureWriter(_ archive: OpaquePointer, for request: CompressionRequest) throws {
        switch request.format {
        case .zip:
            try require(
                archive_write_set_format_zip(archive),
                archive: archive,
                operation: "enable zip writer"
            )
            try setFormatCompressionLevel(archive, options: request.options)
        case .sevenZip:
            try require(
                archive_write_set_format_7zip(archive),
                archive: archive,
                operation: "enable 7z writer"
            )
            try setFormatCompressionLevel(archive, options: request.options)
        case .rar:
            throw ArchiveError.unsupportedOperation(format: request.format, operation: .create)
        case .tar:
            try configureTarWriter(archive, filter: archive_write_add_filter_none, filterName: "none")
        case .tarGzip:
            try configureTarWriter(archive, filter: archive_write_add_filter_gzip, filterName: "gzip")
            try setFilterCompressionLevel(archive, options: request.options)
        case .tarBzip2:
            try configureTarWriter(archive, filter: archive_write_add_filter_bzip2, filterName: "bzip2")
            try setFilterCompressionLevel(archive, options: request.options)
        case .tarXz:
            try configureTarWriter(archive, filter: archive_write_add_filter_xz, filterName: "xz")
            try setFilterCompressionLevel(archive, options: request.options)
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

    func setFormatCompressionLevel(
        _ archive: OpaquePointer,
        options: CompressionOptions
    ) throws {
        try setCompressionLevel(
            archive,
            setter: archive_write_set_format_option,
            operation: "set format compression level",
            options: options
        )
    }

    func setFilterCompressionLevel(
        _ archive: OpaquePointer,
        options: CompressionOptions
    ) throws {
        try setCompressionLevel(
            archive,
            setter: archive_write_set_filter_option,
            operation: "set filter compression level",
            options: options
        )
    }

    func setCompressionLevel(
        _ archive: OpaquePointer,
        setter: (
            OpaquePointer?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?,
            UnsafePointer<CChar>?
        ) -> Int32,
        operation: String,
        options: CompressionOptions
    ) throws {
        let level = compressionLevelValue(for: options.compressionLevel)
        try "compression-level".withCString { option in
            try "\(level)".withCString { value in
                try require(
                    setter(archive, nil, option, value),
                    archive: archive,
                    operation: operation
                )
            }
        }
    }

    func compressionLevelValue(for level: CompressionLevel) -> Int {
        switch level {
        case .fastest:
            return 1
        case .balanced:
            return 6
        case .maximum:
            return 9
        case .custom(let value):
            return min(max(value, 0), 9)
        }
    }

    func makeArchiveEntry(from rawEntry: OpaquePointer) -> ArchiveEntry {
        let path = stringValue(
            archive_entry_pathname_utf8(rawEntry)
        ) ?? stringValue(
            archive_entry_pathname(rawEntry)
        ) ?? ""

        let hardLinkTarget = stringValue(
            archive_entry_hardlink_utf8(rawEntry)
        ) ?? stringValue(
            archive_entry_hardlink(rawEntry)
        )

        let symlinkTarget = stringValue(
            archive_entry_symlink_utf8(rawEntry)
        ) ?? stringValue(
            archive_entry_symlink(rawEntry)
        )

        let kind = entryKind(
            fileType: archive_entry_filetype(rawEntry),
            hardLinkTarget: hardLinkTarget,
            symlinkTarget: symlinkTarget
        )
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

    func validateEntryCanBeRead(
        _ rawEntry: OpaquePointer,
        archiveURL: URL,
        options: ExtractionOptions
    ) throws {
        guard archive_entry_is_encrypted(rawEntry) != 0
            || archive_entry_is_data_encrypted(rawEntry) != 0
            || archive_entry_is_metadata_encrypted(rawEntry) != 0 else {
            return
        }

        guard options.password != nil else {
            throw ArchiveError.encryptedArchive(archiveURL)
        }
    }

    func entryKind(
        fileType: UInt32,
        hardLinkTarget: String?,
        symlinkTarget: String?
    ) -> ArchiveEntryKind {
        if hardLinkTarget != nil {
            return .hardLink(target: hardLinkTarget)
        }

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
        archiveURL: URL,
        to destinationURL: URL,
        baseURL: URL,
        entryPath: String,
        options: ExtractionOptions,
        onBytesWillWrite: (Int64) throws -> Void,
        onBytesWritten: (Int64) -> Void
    ) throws {
        let fileType = archive_entry_filetype(rawEntry)
        try validateSupportedEntryForExtraction(
            rawEntry,
            entryPath: entryPath,
            fileType: fileType
        )

        let resolvedDestinationURL = try destinationURLByResolvingCollision(
            destinationURL,
            entryPath: entryPath,
            fileType: fileType,
            options: options
        )

        guard let resolvedDestinationURL else {
            try skipEntryData(in: archive, archiveURL: archiveURL)
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
            try skipEntryData(in: archive, archiveURL: archiveURL)
        case LibArchiveFileType.symbolicLink:
            try extractSymbolicLink(
                rawEntry,
                from: archive,
                archiveURL: archiveURL,
                to: resolvedDestinationURL
            )
        case LibArchiveFileType.regular:
            try extractFile(
                rawEntry,
                from: archive,
                archiveURL: archiveURL,
                to: resolvedDestinationURL,
                options: options,
                onBytesWillWrite: onBytesWillWrite,
                onBytesWritten: onBytesWritten
            )
        default:
            try skipEntryData(in: archive, archiveURL: archiveURL)
        }
    }

    func validateSupportedEntryForExtraction(
        _ rawEntry: OpaquePointer,
        entryPath: String,
        fileType: UInt32
    ) throws {
        if hardLinkTarget(for: rawEntry) != nil {
            throw ArchiveError.unsupportedEntryType(path: entryPath, type: "hard link")
        }

        guard isSupportedExtractionFileType(fileType) else {
            throw ArchiveError.unsupportedEntryType(
                path: entryPath,
                type: entryTypeName(for: fileType)
            )
        }
    }

    func validateEntryCount(_ entryCount: Int, limits: ExtractionResourceLimits) throws {
        guard let limit = limits.maxEntryCount, entryCount > limit else {
            return
        }

        throw ArchiveError.extractionResourceLimitExceeded(
            .entryCount(limit: limit, actual: entryCount)
        )
    }

    func validateDirectoryDepth(
        entryPath: String,
        fileType: UInt32,
        limits: ExtractionResourceLimits
    ) throws {
        guard let limit = limits.maxDirectoryDepth else {
            return
        }

        let actualDepth = directoryDepth(entryPath: entryPath, fileType: fileType)
        guard actualDepth <= limit else {
            throw ArchiveError.extractionResourceLimitExceeded(
                .directoryDepth(path: entryPath, limit: limit, actual: actualDepth)
            )
        }
    }

    func validateSingleFileSize(
        _ byteCount: Int64,
        entryPath: String,
        limits: ExtractionResourceLimits
    ) throws {
        guard let limit = limits.maxSingleFileUncompressedSize, byteCount > limit else {
            return
        }

        throw ArchiveError.extractionResourceLimitExceeded(
            .singleFileUncompressedSize(path: entryPath, limit: limit, actual: byteCount)
        )
    }

    func validateResourceLimitsBeforeWriting(
        byteCount: Int64,
        entryPath: String,
        currentEntryByteCount: Int64,
        completedByteCount: Int64,
        limits: ExtractionResourceLimits
    ) throws {
        _ = try checkedLimitedResourceSizeSum(
            currentEntryByteCount,
            byteCount,
            limit: limits.maxSingleFileUncompressedSize
        ) { limit, actual in
            .singleFileUncompressedSize(path: entryPath, limit: limit, actual: actual)
        }
        _ = try checkedLimitedResourceSizeSum(
            completedByteCount,
            byteCount,
            limit: limits.maxTotalUncompressedSize
        ) { limit, actual in
            .totalUncompressedSize(limit: limit, actual: actual)
        }
    }

    func validateSymbolicLinkTargetIfNeeded(_ rawEntry: OpaquePointer, fileType: UInt32) throws {
        guard fileType == LibArchiveFileType.symbolicLink,
              let target = stringValue(archive_entry_symlink_utf8(rawEntry))
                ?? stringValue(archive_entry_symlink(rawEntry)) else {
            return
        }

        try validateSymbolicLinkTarget(target)
    }

    func hardLinkTarget(for rawEntry: OpaquePointer) -> String? {
        stringValue(archive_entry_hardlink_utf8(rawEntry))
            ?? stringValue(archive_entry_hardlink(rawEntry))
    }

    func isSupportedExtractionFileType(_ fileType: UInt32) -> Bool {
        switch fileType {
        case LibArchiveFileType.directory,
             LibArchiveFileType.symbolicLink,
             LibArchiveFileType.regular:
            return true
        default:
            return false
        }
    }

    func entryTypeName(for fileType: UInt32) -> String {
        switch fileType {
        case LibArchiveFileType.fifo:
            return "fifo"
        case LibArchiveFileType.characterDevice:
            return "character device"
        case LibArchiveFileType.blockDevice:
            return "block device"
        case LibArchiveFileType.socket:
            return "socket"
        default:
            return "unknown"
        }
    }

    func uncompressedSize(for rawEntry: OpaquePointer, entryPath: String) throws -> Int64? {
        guard archive_entry_size_is_set(rawEntry) != 0 else {
            return nil
        }

        let size = archive_entry_size(rawEntry)
        guard size >= 0 else {
            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Archive entry has invalid size: \(entryPath)"
            )
        }

        return size
    }

    func directoryDepth(entryPath: String, fileType: UInt32) -> Int {
        let normalizedPath = entryPath.replacingOccurrences(of: "\\", with: "/")
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true)

        guard fileType != LibArchiveFileType.directory else {
            return components.count
        }

        return max(components.count - 1, 0)
    }

    func checkedLimitedResourceSizeSum(
        _ current: Int64,
        _ addition: Int64,
        limit: Int64?,
        violation: (Int64, Int64) -> ExtractionResourceLimitViolation
    ) throws -> Int64 {
        let result = current.addingReportingOverflow(addition)
        guard !result.overflow else {
            if let limit {
                throw ArchiveError.extractionResourceLimitExceeded(
                    violation(limit, Int64.max)
                )
            }

            throw ArchiveError.engineFailure(
                engine: identifier,
                message: "Archive entry size overflow."
            )
        }

        let actual = result.partialValue
        if let limit, actual > limit {
            throw ArchiveError.extractionResourceLimitExceeded(
                violation(limit, actual)
            )
        }

        return actual
    }

    func extractFile(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        archiveURL: URL,
        to destinationURL: URL,
        options: ExtractionOptions,
        onBytesWillWrite: (Int64) throws -> Void,
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

        do {
            while true {
                try Task.checkCancellation()

                let readCount = archive_read_data(archive, &buffer, buffer.count)
                if readCount == 0 {
                    break
                }

                guard readCount > 0 else {
                    throw readFailure(
                        archive: archive,
                        archiveURL: archiveURL,
                        operation: "read file data"
                    )
                }

                try onBytesWillWrite(Int64(readCount))
                fileHandle.write(Data(buffer.prefix(readCount)))
                onBytesWritten(Int64(readCount))
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }

        try applyMetadata(from: rawEntry, to: destinationURL, options: options)
    }

    func extractSymbolicLink(
        _ rawEntry: OpaquePointer,
        from archive: OpaquePointer,
        archiveURL: URL,
        to destinationURL: URL
    ) throws {
        guard let target = stringValue(archive_entry_symlink_utf8(rawEntry))
            ?? stringValue(archive_entry_symlink(rawEntry)) else {
            try skipEntryData(in: archive, archiveURL: archiveURL)
            return
        }

        try validateSymbolicLinkTarget(target)

        try createDirectory(at: destinationURL.deletingLastPathComponent())
        try fileManager.createSymbolicLink(atPath: destinationURL.path, withDestinationPath: target)
        try skipEntryData(in: archive, archiveURL: archiveURL)
    }

    func destinationURLByResolvingCollision(
        _ destinationURL: URL,
        entryPath: String,
        fileType: UInt32,
        options: ExtractionOptions
    ) throws -> URL? {
        var isDirectory = ObjCBool(false)

        guard fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory) else {
            return destinationURL
        }

        if fileType == LibArchiveFileType.directory && isDirectory.boolValue {
            if options.overwritePolicy == .skip {
                return nil
            }

            return destinationURL
        }

        let overwritePolicy = try effectiveOverwritePolicy(
            for: destinationURL,
            entryPath: entryPath,
            fileType: fileType,
            existingItemIsDirectory: isDirectory.boolValue,
            options: options
        )

        switch overwritePolicy {
        case .overwrite:
            try fileManager.removeItem(at: destinationURL)
            return destinationURL
        case .skip:
            return nil
        case .ask:
            throw ArchiveError.conflictRequiresDecision(destinationURL)
        case .rename:
            return uniqueDestinationURL(for: destinationURL)
        }
    }

    func effectiveOverwritePolicy(
        for destinationURL: URL,
        entryPath: String,
        fileType: UInt32,
        existingItemIsDirectory: Bool,
        options: ExtractionOptions
    ) throws -> OverwritePolicy {
        guard options.overwritePolicy == .ask else {
            return options.overwritePolicy
        }

        guard let conflictResolver = options.conflictResolver else {
            throw ArchiveError.conflictRequiresDecision(destinationURL)
        }

        let conflict = ArchiveConflict(
            entryPath: entryPath,
            destinationURL: destinationURL,
            existingItemIsDirectory: existingItemIsDirectory,
            incomingItemIsDirectory: fileType == LibArchiveFileType.directory
        )
        let decision = conflictResolver(conflict)

        guard decision != .ask else {
            throw ArchiveError.conflictRequiresDecision(destinationURL)
        }

        return decision
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

        guard !normalizedTarget.contains("\0"),
              !containsUnsafeControlCharacter(in: normalizedTarget) else {
            throw ArchiveError.unsafeEntryPath(target)
        }

        let components = normalizedTarget.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveError.unsafeEntryPath(target)
        }

        if let firstComponent = components.first,
           firstComponent.count == 2,
           firstComponent.last == ":",
           firstComponent.first?.isLetter == true {
            throw ArchiveError.unsafeEntryPath(target)
        }
    }

    func containsUnsafeControlCharacter(in path: String) -> Bool {
        path.unicodeScalars.contains { scalar in
            if CharacterSet.controlCharacters.contains(scalar) {
                return true
            }

            return isBidirectionalControl(scalar)
        }
    }

    func isBidirectionalControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
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

    func skipEntryData(in archive: OpaquePointer, archiveURL: URL? = nil) throws {
        let status = archive_read_data_skip(archive)

        if let archiveURL {
            try requireReadStatus(
                status,
                archive: archive,
                archiveURL: archiveURL,
                operation: "skip entry data"
            )
        } else {
            try require(status, archive: archive, operation: "skip entry data")
        }
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

    func requireReadStatus(
        _ status: Int32,
        archive: OpaquePointer,
        archiveURL: URL,
        operation: String
    ) throws {
        guard status == LibArchiveStatus.ok else {
            throw readFailure(archive: archive, archiveURL: archiveURL, operation: operation)
        }
    }

    func engineFailure(archive: OpaquePointer?, operation: String) -> ArchiveError {
        let message = stringValue(archive_error_string(archive)) ?? "Unknown libarchive error."

        return .engineFailure(
            engine: identifier,
            message: "\(operation): \(message)"
        )
    }

    func readFailure(
        archive: OpaquePointer?,
        archiveURL: URL,
        operation: String
    ) -> ArchiveError {
        let message = stringValue(archive_error_string(archive)) ?? "Unknown libarchive error."

        return LibArchiveReadErrorMapper.map(
            archiveURL: archiveURL,
            message: message,
            engine: identifier,
            operation: operation
        )
    }

    func stringValue(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }
}
