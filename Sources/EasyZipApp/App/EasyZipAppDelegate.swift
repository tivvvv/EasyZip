import AppKit
import EasyZipCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EasyZipAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var workspaceWindow: NSWindow?
    private var workspaceModel: EasyZipAppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        installStatusItem()
        installMainMenu()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === workspaceWindow else {
            return
        }

        workspaceWindow = nil
        workspaceModel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === workspaceWindow,
              workspaceModel?.isRunning == true else {
            return true
        }

        sender.orderOut(nil)
        return false
    }

    @objc private func openWorkspaceFromMenu() {
        showWorkspace()
    }

    @objc private func chooseItemsForCompression() {
        chooseItems(mode: .compress)
    }

    @objc private func chooseItemsForExtraction() {
        chooseItems(mode: .extract)
    }

    @objc(compressSelection:userData:error:)
    func compressSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handleServiceSelection(
            pasteboard,
            mode: .compress,
            error: error
        )
    }

    @objc(extractSelection:userData:error:)
    func extractSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handleServiceSelection(
            pasteboard,
            mode: .extract,
            error: error
        )
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "archivebox",
                accessibilityDescription: "易压缩"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu(title: "易压缩")
        menu.addItem(statusMenuItem(title: "打开易压缩", action: #selector(openWorkspaceFromMenu)))
        menu.addItem(.separator())
        menu.addItem(statusMenuItem(title: "压缩文件...", action: #selector(chooseItemsForCompression)))
        menu.addItem(statusMenuItem(title: "解压归档...", action: #selector(chooseItemsForExtraction)))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出易压缩",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        item.menu = menu
        statusItem = item
    }

    private func statusMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func chooseItems(mode: WorkspaceMode) {
        let panel = NSOpenPanel()
        panel.title = mode == .compress ? "选择要压缩的项目" : "选择要解压的归档"
        panel.message = mode == .compress ? "可以选择文件或文件夹" : "请选择支持的归档文件"
        panel.prompt = "添加"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = mode == .compress
        panel.allowedContentTypes = mode == .extract
            ? ArchiveFormat.supportedPathExtensions.compactMap { UTType(filenameExtension: $0) }
            : []

        guard panel.runModal() == .OK else {
            return
        }

        showWorkspace(mode: mode, fileURLs: panel.urls)
    }

    private func handleServiceSelection(
        _ pasteboard: NSPasteboard,
        mode: WorkspaceMode,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let fileURLs = fileURLs(from: pasteboard)

        guard !fileURLs.isEmpty else {
            error.pointee = "没有可处理的文件"
            return
        }

        showWorkspace(mode: mode, fileURLs: fileURLs)
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "easyzip",
              url.host == "finder-action",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let queryItems = components.queryItems ?? []
        let modeValue = queryItems.first { $0.name == "mode" }?.value
        let fileURLs = queryItems
            .filter { $0.name == "item" }
            .compactMap(\.value)
            .compactMap(URL.init(string:))
            .filter(\.isFileURL)

        guard let mode = workspaceMode(from: modeValue), !fileURLs.isEmpty else {
            showWorkspace()
            return
        }

        showWorkspace(mode: mode, fileURLs: fileURLs)
    }

    private func workspaceMode(from value: String?) -> WorkspaceMode? {
        switch value {
        case "compress":
            return .compress
        case "extract":
            return .extract
        default:
            return nil
        }
    }

    private func showWorkspace(
        mode: WorkspaceMode? = nil,
        fileURLs: [URL] = []
    ) {
        let model: EasyZipAppModel

        if let existingModel = workspaceModel {
            model = existingModel
        } else {
            model = EasyZipAppModel()
            workspaceModel = model
        }

        if let mode {
            model.prepareExternalSelection(mode: mode, fileURLs: fileURLs)
        }

        if workspaceWindow == nil {
            let hostingController = NSHostingController(
                rootView: EasyZipWorkspaceView(model: model)
                    .frame(minWidth: 920, minHeight: 620)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "易压缩"
            window.titlebarAppearsTransparent = true
            window.contentViewController = hostingController
            window.delegate = self
            window.center()
            workspaceWindow = window
        }

        workspaceWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        let fileURLObjects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        for object in fileURLObjects {
            if let url = object as? URL {
                urls.append(url)
            } else if let url = object as? NSURL {
                urls.append(url as URL)
            }
        }

        if let filePaths = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            urls.append(contentsOf: filePaths.map { URL(fileURLWithPath: $0) })
        }

        if let text = pasteboard.string(forType: .string) {
            urls.append(contentsOf: fileURLs(fromPlainText: text))
        }

        return uniqueFileURLs(urls)
    }

    private func fileURLs(fromPlainText text: String) -> [URL] {
        text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap { value in
                if value.hasPrefix("file://") {
                    return URL(string: value)
                }

                guard value.hasPrefix("/") else {
                    return nil
                }

                return URL(fileURLWithPath: value)
            }
    }

    private func uniqueFileURLs(_ urls: [URL]) -> [URL] {
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

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "易压缩")
        appMenu.addItem(
            NSMenuItem(
                title: "关于易压缩",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "隐藏易压缩",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )
        let hideOthersItem = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            NSMenuItem(
                title: "全部显示",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "退出易压缩",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        mainMenu.addItem(menuItem(title: "易压缩", submenu: appMenu))

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(
                title: "全选",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        mainMenu.addItem(menuItem(title: "编辑", submenu: editMenu))

        let viewMenu = NSMenu(title: "视图")
        let fullScreenItem = NSMenuItem(
            title: "进入全屏",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        mainMenu.addItem(menuItem(title: "视图", submenu: viewMenu))

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(
            NSMenuItem(
                title: "最小化",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )
        windowMenu.addItem(
            NSMenuItem(
                title: "缩放",
                action: #selector(NSWindow.performZoom(_:)),
                keyEquivalent: ""
            )
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            NSMenuItem(
                title: "前置全部窗口",
                action: #selector(NSApplication.arrangeInFront(_:)),
                keyEquivalent: ""
            )
        )
        mainMenu.addItem(menuItem(title: "窗口", submenu: windowMenu))

        let helpMenu = NSMenu(title: "帮助")
        mainMenu.addItem(menuItem(title: "帮助", submenu: helpMenu))

        NSApplication.shared.mainMenu = mainMenu
    }

    private func menuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
