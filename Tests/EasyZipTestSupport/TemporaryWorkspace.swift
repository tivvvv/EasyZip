import Foundation

public enum TemporaryWorkspace {
    public static func makeURL(
        prefix: String = "EasyZipTests",
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func remove(
        _ url: URL,
        fileManager: FileManager = .default
    ) {
        try? fileManager.removeItem(at: url)
    }
}
