import Cocoa
import FinderSync

final class EasyZipFinderSyncExtension: FIFinderSync {
    private enum ActionMode: String {
        case compress
        case extract
    }

    private static let maximumFallbackURLLength = 6_000

    private let handoffStore: FinderActionHandoffStore? = {
        let groupIdentifier = FinderActionHandoffStore.configuredAppGroupIdentifier()
        guard let directoryURL = FinderActionHandoffStore.appGroupDirectoryURL(
            groupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        return FinderActionHandoffStore(directoryURL: directoryURL)
    }()

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
        guard !fileURLs.isEmpty else {
            return
        }

        guard let handoffStore else {
            openFallbackURL(mode: mode, fileURLs: fileURLs)
            return
        }

        do {
            _ = try handoffStore.write(fileURLs: fileURLs, action: mode.rawValue)
        } catch {
            openFallbackURL(mode: mode, fileURLs: fileURLs)
            return
        }

        guard let appURL = containingAppURL() else {
            openFallbackURL(mode: mode, fileURLs: fileURLs)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(
            fileURLs,
            withApplicationAt: appURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard error != nil else {
                return
            }

            self?.openFallbackURL(mode: mode, fileURLs: fileURLs)
        }
    }

    private func openFallbackURL(mode: ActionMode, fileURLs: [URL]) {
        if let fallbackURL = fallbackActionURL(mode: mode, fileURLs: fileURLs),
           fallbackURL.absoluteString.count <= Self.maximumFallbackURLLength {
            NSWorkspace.shared.open(fallbackURL)
            return
        }

        if let failureURL = handoffFailureURL(mode: mode) {
            NSWorkspace.shared.open(failureURL)
        }
    }

    private func containingAppURL() -> URL? {
        var candidateURL = Bundle.main.bundleURL

        while candidateURL.pathExtension != "app" && candidateURL.path != "/" {
            candidateURL.deleteLastPathComponent()
        }

        return candidateURL.pathExtension == "app" ? candidateURL : nil
    }

    private func fallbackActionURL(mode: ActionMode, fileURLs: [URL]) -> URL? {
        var components = URLComponents()
        components.scheme = "easyzip"
        components.host = "finder-action"
        guard let bookmarks = FinderActionHandoffStore.securityScopedBookmarks(for: fileURLs),
              bookmarks.count == fileURLs.count else {
            return nil
        }
        let bookmarkItems = bookmarks.map { bookmark in
            URLQueryItem(
                name: FinderActionHandoffStore.bookmarkQueryItemName,
                value: bookmark.base64EncodedString()
            )
        }
        components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
            + bookmarkItems
            + fileURLs.map { URLQueryItem(name: "item", value: $0.absoluteString) }

        return components.url
    }

    private func handoffFailureURL(mode: ActionMode) -> URL? {
        var components = URLComponents()
        components.scheme = "easyzip"
        components.host = "finder-action"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "error", value: "handoff-unavailable")
        ]

        return components.url
    }

    private func isSupportedArchive(_ url: URL) -> Bool {
        ArchiveFileNameMatcher.isSupportedArchiveFileURL(url)
    }

}
