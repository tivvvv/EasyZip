import Foundation

public enum ArchiveFileNameMatcher {
    public static let supportedArchiveSuffixes = [
        ".zip",
        ".7z",
        ".rar",
        ".tar",
        ".tar.gz",
        ".tgz",
        ".tar.bz2",
        ".tbz2",
        ".tbz",
        ".tar.xz",
        ".txz",
        ".tar.zst",
        ".tzst",
        ".gz",
        ".xz"
    ]

    public static func isSupportedArchiveFilename(_ filename: String) -> Bool {
        let normalizedFilename = filename.lowercased()

        return supportedArchiveSuffixes.contains { suffix in
            normalizedFilename.hasSuffix(suffix)
        }
    }

    public static func isSupportedArchiveFileURL(_ url: URL) -> Bool {
        isSupportedArchiveFilename(url.lastPathComponent)
    }
}
