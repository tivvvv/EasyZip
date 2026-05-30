import EasyZipCore
import Foundation

struct ArchiveEntryRow: Identifiable {
    let id: String
    let name: String
    let detail: String
    let kind: ArchiveEntryKind

    init(entry: ArchiveEntry) {
        id = entry.path
        name = entry.path
        kind = entry.kind

        if let size = entry.uncompressedSize {
            detail = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            detail = "-"
        }
    }
}
