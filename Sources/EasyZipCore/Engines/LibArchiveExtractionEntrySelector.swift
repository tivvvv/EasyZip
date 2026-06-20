import Foundation

struct LibArchiveExtractionEntrySelector {
    private let selectedPaths: Set<String>

    init(selectedPaths: Set<String>) {
        self.selectedPaths = Set(
            selectedPaths
                .map(Self.normalizedPath)
                .filter { !$0.isEmpty }
        )
    }

    func shouldExtract(entryPath: String, fileType: UInt32) -> Bool {
        guard !selectedPaths.isEmpty else {
            return true
        }

        let normalizedEntryPath = Self.normalizedPath(entryPath)

        if selectedPaths.contains(normalizedEntryPath) {
            return true
        }

        if selectedPaths.contains(where: { normalizedEntryPath.hasPrefix($0 + "/") }) {
            return true
        }

        guard fileType == LibArchiveFileType.directory else {
            return false
        }

        return selectedPaths.contains { $0.hasPrefix(normalizedEntryPath + "/") }
    }

    private static func normalizedPath(_ path: String) -> String {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        return normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
