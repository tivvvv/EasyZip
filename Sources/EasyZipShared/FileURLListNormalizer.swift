import Foundation

public enum FileURLListNormalizer {
    public static func uniqueStandardizedFileURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            uniqueURLs.append(standardizedURL)
        }

        return uniqueURLs
    }
}
