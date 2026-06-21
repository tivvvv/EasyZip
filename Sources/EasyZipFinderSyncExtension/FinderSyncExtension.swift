import Cocoa
import FinderSync

final class EasyZipFinderSyncExtension: FIFinderSync {
    private enum ActionMode: String {
        case compress
        case extract
    }

    private static let maximumLegacyURLLength = 6_000

    private let handoffStore = FinderActionHandoffStore()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String {
        "易压缩"
    }

    override var toolbarItemToolTip: String {
        "使用易压缩处理选中文件"
    }

    override var toolbarItemImage: NSImage {
        if let image = NSImage(
            systemSymbolName: "archivebox",
            accessibilityDescription: "易压缩"
        ) {
            return image
        }

        if let image = NSImage(named: NSImage.folderName) {
            return image
        }

        return NSImage(size: NSSize(width: 18, height: 18))
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard shouldShowMenu(for: menuKind) else {
            return nil
        }

        let fileURLs = selectedFileURLs()
        guard !fileURLs.isEmpty else {
            return nil
        }

        let menu = NSMenu(title: "易压缩")
        let compressItem = menuItem(
            title: "使用易压缩进行压缩",
            action: #selector(compressSelection(_:))
        )
        let extractItem = menuItem(
            title: "使用易压缩进行解压",
            action: #selector(extractSelection(_:))
        )
        extractItem.isEnabled = fileURLs.contains { isSupportedArchive($0) }

        menu.addItem(compressItem)
        menu.addItem(extractItem)
        return menu
    }

    @objc private func compressSelection(_ sender: Any?) {
        openMainApp(mode: .compress)
    }

    @objc private func extractSelection(_ sender: Any?) {
        openMainApp(mode: .extract)
    }

    private func shouldShowMenu(for menuKind: FIMenuKind) -> Bool {
        switch menuKind {
        case .contextualMenuForItems, .toolbarItemMenu:
            return true
        default:
            return false
        }
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func selectedFileURLs() -> [URL] {
        if let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
           !selectedURLs.isEmpty {
            return FileURLListNormalizer.uniqueStandardizedFileURLs(selectedURLs)
        }

        guard let targetedURL = FIFinderSyncController.default().targetedURL() else {
            return []
        }

        return [targetedURL.standardizedFileURL]
    }

    private func openMainApp(mode: ActionMode) {
        let fileURLs = selectedFileURLs()
        guard !fileURLs.isEmpty,
              let url = actionURL(mode: mode, fileURLs: fileURLs) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func actionURL(mode: ActionMode, fileURLs: [URL]) -> URL? {
        if let handoffURL = handoffActionURL(mode: mode, fileURLs: fileURLs) {
            return handoffURL
        }

        guard let legacyURL = legacyActionURL(mode: mode, fileURLs: fileURLs),
              legacyURL.absoluteString.count <= Self.maximumLegacyURLLength else {
            return nil
        }

        return legacyURL
    }

    private func handoffActionURL(mode: ActionMode, fileURLs: [URL]) -> URL? {
        guard let handoffId = try? handoffStore.write(fileURLs: fileURLs) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "easyzip"
        components.host = "finder-action"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: FinderActionHandoffStore.handoffQueryItemName, value: handoffId)
        ]

        return components.url
    }

    private func legacyActionURL(mode: ActionMode, fileURLs: [URL]) -> URL? {
        var components = URLComponents()
        components.scheme = "easyzip"
        components.host = "finder-action"
        components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
            + fileURLs.map { URLQueryItem(name: "item", value: $0.absoluteString) }

        return components.url
    }

    private func isSupportedArchive(_ url: URL) -> Bool {
        ArchiveFileNameMatcher.isSupportedArchiveFileURL(url)
    }

}
