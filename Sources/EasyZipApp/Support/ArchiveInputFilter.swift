import EasyZipShared
import Foundation

struct ArchiveInputFilterResult {
    let acceptedFileURLs: [URL]
    let rejectedFileURLs: [URL]

    var rejectedCount: Int {
        rejectedFileURLs.count
    }
}

enum ArchiveInputFilter {
    static func filter(_ fileURLs: [URL], for mode: WorkspaceMode) -> ArchiveInputFilterResult {
        let acceptedFileURLs: [URL]
        let rejectedFileURLs: [URL]

        switch mode {
        case .compress:
            acceptedFileURLs = fileURLs
            rejectedFileURLs = []
        case .extract:
            acceptedFileURLs = fileURLs.filter(ArchiveFileNameMatcher.isSupportedArchiveFileURL)
            rejectedFileURLs = fileURLs.filter { url in
                !ArchiveFileNameMatcher.isSupportedArchiveFileURL(url)
            }
        }

        return ArchiveInputFilterResult(
            acceptedFileURLs: acceptedFileURLs,
            rejectedFileURLs: rejectedFileURLs
        )
    }
}
