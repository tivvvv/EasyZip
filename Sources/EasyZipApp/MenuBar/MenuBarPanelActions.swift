import Foundation

struct MenuBarPanelActions {
    let openWorkspace: () -> Void
    let chooseCompression: () -> Void
    let chooseExtraction: () -> Void
    let revealURL: (URL) -> Void
    let openURL: (URL) -> Void
    let quit: () -> Void
}
