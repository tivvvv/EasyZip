import AppKit
import EasyZipCore
import UniformTypeIdentifiers

@MainActor
enum FileSelectionPanelFactory {
    static func makeItemSelectionPanel(mode: WorkspaceMode) -> NSOpenPanel {
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

        return panel
    }

    static func makeOutputDirectoryPanel(
        title: String = "选择输出目录",
        message: String = "任务结果将保存到这里"
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        return panel
    }
}
