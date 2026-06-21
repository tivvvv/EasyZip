import AppKit
import Combine
import EasyZipCore
import EasyZipShared
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EasyZipAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var workspaceWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let appSettings = EasyZipAppSettings.shared
    private let onboardingState = EasyZipOnboardingState.shared
    private let workspaceModel = EasyZipAppModel(settings: .shared)
    private var cancellables: Set<AnyCancellable> = []
    private var terminationObserver: AnyCancellable?
    private var isHandlingTerminationRequest = false
    private let handoffStore = FinderActionHandoffStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        appSettings.refreshLaunchAtLoginStatus()
        if appSettings.taskCompletionNotificationEnabled,
           !onboardingState.shouldShowFirstLaunchGuide {
            TaskCompletionNotifier.requestAuthorization()
        }
        handoffStore.removeExpiredFiles()
        installStatusItem()
        MainMenuBuilder.install(
            settingsTarget: self,
            settingsAction: #selector(openSettingsFromMenu)
        )
        observeStatusModel()
        updateStatusItem()
        showOnboardingIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workspaceModel.isRunning else {
            return .terminateNow
        }

        guard !isHandlingTerminationRequest else {
            return .terminateCancel
        }

        isHandlingTerminationRequest = true
        confirmTerminationWhileRunning()
        return .terminateLater
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === workspaceWindow {
            workspaceWindow = nil
        } else if window === onboardingWindow {
            onboardingWindow = nil
            onboardingState.completeFirstLaunchGuide()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === workspaceWindow,
              workspaceModel.isRunning else {
            return true
        }

        sender.orderOut(nil)
        return false
    }

    @objc private func openWorkspaceFromMenu() {
        closeStatusPanel()
        showWorkspace()
    }

    @objc private func openSettingsFromMenu() {
        closeStatusPanel()
        showSettings()
    }

    @objc private func chooseItemsForCompression() {
        closeStatusPanel()
        chooseItems(mode: .compress)
    }

    @objc private func chooseItemsForExtraction() {
        closeStatusPanel()
        chooseItems(mode: .extract)
    }

    @objc private func toggleStatusPanel(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if statusPopover?.isShown == true {
            closeStatusPanel()
            return
        }

        showStatusPanel(relativeTo: button)
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
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggleStatusPanel(_:))
        }

        statusItem = item
    }

    private func observeStatusModel() {
        Publishers.CombineLatest4(
            workspaceModel.$isRunning,
            workspaceModel.$progressFraction,
            workspaceModel.$progressText,
            workspaceModel.$taskResult
        )
        .sink { [weak self] _, _, _, _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
        .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let item = statusItem,
              let button = item.button else {
            return
        }

        if workspaceModel.isRunning {
            item.length = NSStatusItem.variableLength
            button.title = statusItemProgressTitle()
            button.contentTintColor = .controlAccentColor
        } else {
            item.length = NSStatusItem.squareLength
            button.title = ""
            button.contentTintColor = nil
        }
    }

    private func statusItemProgressTitle() -> String {
        let percent = Int((workspaceModel.progressFraction * 100).rounded(.down))

        guard percent > 0 else {
            return " 处理中"
        }

        return " \(min(percent, 100))%"
    }

    private func showStatusPanel(relativeTo button: NSStatusBarButton) {
        let popover = statusPopover ?? makeStatusPopover()
        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closeStatusPanel() {
        statusPopover?.performClose(nil)
    }

    private func makeStatusPopover() -> NSPopover {
        let actions = MenuBarPanelActions(
            openWorkspace: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.showWorkspace()
                }
            },
            openSettings: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.showSettings()
                }
            },
            openOnboarding: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.showOnboarding()
                }
            },
            chooseCompression: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.chooseItems(mode: .compress)
                }
            },
            chooseExtraction: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.chooseItems(mode: .extract)
                }
            },
            revealURL: { [weak self] url in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            openURL: { [weak self] url in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    NSWorkspace.shared.open(url)
                }
            },
            quit: { [weak self] in
                Task { @MainActor in
                    self?.closeStatusPanel()
                    self?.requestApplicationTermination()
                }
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: EasyZipMenuBarPanelView(model: workspaceModel, actions: actions)
        )

        return popover
    }

    private func requestApplicationTermination() {
        NSApplication.shared.terminate(nil)
    }

    private func confirmTerminationWhileRunning() {
        closeStatusPanel()
        showWorkspace()

        let alert = NSAlert()
        alert.messageText = "任务仍在进行中"
        alert.informativeText = "退出易压缩会取消当前任务, 未完成的输出不会保留."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消任务并退出")
        alert.addButton(withTitle: "继续运行")

        guard let window = workspaceWindow else {
            Task { @MainActor in
                self.handleTerminationConfirmation(alert.runModal())
            }
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor in
                self?.handleTerminationConfirmation(response)
            }
        }
    }

    private func handleTerminationConfirmation(_ response: NSApplication.ModalResponse) {
        guard response == .alertFirstButtonReturn else {
            completeTerminationRequest(shouldTerminate: false)
            return
        }

        beginTerminationAfterCancellingTask()
    }

    private func beginTerminationAfterCancellingTask() {
        guard workspaceModel.isRunning else {
            completeTerminationRequest(shouldTerminate: true)
            return
        }

        terminationObserver = workspaceModel.$isRunning
            .removeDuplicates()
            .sink { [weak self] isRunning in
                guard !isRunning else {
                    return
                }

                Task { @MainActor in
                    self?.completeTerminationRequest(shouldTerminate: true)
                }
            }

        workspaceModel.cancelOperation()
    }

    private func completeTerminationRequest(shouldTerminate: Bool) {
        terminationObserver?.cancel()
        terminationObserver = nil
        isHandlingTerminationRequest = false
        NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
    }

    private func chooseItems(mode: WorkspaceMode) {
        guard !workspaceModel.isRunning else {
            workspaceModel.noteSelectionBlocked(mode: mode)
            showWorkspace()
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
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

        guard let mode = workspaceMode(from: modeValue) else {
            showWorkspace()
            return
        }

        let fileURLs: [URL]

        do {
            fileURLs = try fileURLsFromQueryItems(queryItems)
        } catch {
            showWorkspace()
            workspaceModel.alert = AppAlert(
                title: "无法读取 Finder 选择",
                message: "请重新从 Finder 右键菜单发起操作"
            )
            return
        }

        guard !fileURLs.isEmpty else {
            showWorkspace()
            return
        }

        showWorkspace(mode: mode, fileURLs: fileURLs)
    }

    private func fileURLsFromQueryItems(_ queryItems: [URLQueryItem]) throws -> [URL] {
        if let handoffId = queryItems.first(
            where: { $0.name == FinderActionHandoffStore.handoffQueryItemName }
        )?.value {
            return try handoffStore.readAndRemove(id: handoffId)
        }

        return queryItems
            .filter { $0.name == "item" }
            .compactMap(\.value)
            .compactMap(URL.init(string:))
            .filter(\.isFileURL)
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
        if let mode {
            workspaceModel.prepareExternalSelection(mode: mode, fileURLs: fileURLs)
        }

        if workspaceWindow == nil {
            let hostingController = NSHostingController(
                rootView: EasyZipWorkspaceView(model: workspaceModel)
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

        if workspaceWindow?.isMiniaturized == true {
            workspaceWindow?.deminiaturize(nil)
        }

        workspaceWindow?.makeKeyAndOrderFront(nil)
        workspaceWindow?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showOnboardingIfNeeded() {
        guard onboardingState.shouldShowFirstLaunchGuide else {
            return
        }

        showOnboarding()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let actions = EasyZipOnboardingActions(
                complete: { [weak self] in
                    Task { @MainActor in
                        self?.completeOnboarding()
                    }
                },
                openWorkspace: { [weak self] in
                    Task { @MainActor in
                        self?.completeOnboarding()
                        self?.showWorkspace()
                    }
                },
                openFinderExtensionSettings: { [weak self] in
                    Task { @MainActor in
                        self?.openFinderExtensionSettings()
                    }
                },
                requestNotificationAuthorization: {
                    TaskCompletionNotifier.requestAuthorization()
                }
            )
            let hostingController = NSHostingController(
                rootView: EasyZipOnboardingView(actions: actions)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "首次启动引导"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
        }

        if onboardingWindow?.isMiniaturized == true {
            onboardingWindow?.deminiaturize(nil)
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func completeOnboarding() {
        onboardingState.completeFirstLaunchGuide()

        guard let window = onboardingWindow else {
            return
        }

        onboardingWindow = nil
        window.close()
    }

    private func openFinderExtensionSettings() {
        let settingsURLs = [
            URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"),
            URL(string: "x-apple.systempreferences:com.apple.preferences.extensions?Finder")
        ].compactMap { $0 }

        for url in settingsURLs {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Extensions.prefPane"))
    }

    private func showSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: EasyZipSettingsView(settings: appSettings)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        if settingsWindow?.isMiniaturized == true {
            settingsWindow?.deminiaturize(nil)
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
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

        return FileURLListNormalizer.uniqueStandardizedFileURLs(urls)
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

}
