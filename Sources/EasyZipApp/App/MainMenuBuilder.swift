import AppKit

@MainActor
enum MainMenuBuilder {
    static func install() {
        NSApplication.shared.mainMenu = makeMainMenu()
    }

    private static func makeMainMenu() -> NSMenu {
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

        return mainMenu
    }

    private static func menuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
