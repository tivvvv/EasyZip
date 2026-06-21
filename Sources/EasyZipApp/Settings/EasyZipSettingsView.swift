import AppKit
import EasyZipCore
import SwiftUI

struct EasyZipSettingsView: View {
    @ObservedObject var settings: EasyZipAppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("默认任务") {
                    LabeledContent("输出目录") {
                        HStack(spacing: 8) {
                            Text(outputDirectoryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Button {
                                chooseDefaultOutputDirectory()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("选择输出目录")

                            Button {
                                settings.defaultOutputDirectory = nil
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .help("清除输出目录")
                            .disabled(settings.defaultOutputDirectory == nil)
                        }
                    }

                    Picker("压缩格式", selection: $settings.defaultCompressionFormat) {
                        ForEach(ArchiveFormat.allCases, id: \.self) { format in
                            Text(format.displayExtension).tag(format)
                        }
                    }

                    Picker("冲突策略", selection: $settings.defaultOverwritePolicy) {
                        Text("自动重命名").tag(OverwritePolicy.rename)
                        Text("覆盖").tag(OverwritePolicy.overwrite)
                        Text("跳过").tag(OverwritePolicy.skip)
                    }

                    Toggle("总是创建外层目录", isOn: $settings.shouldCreateContainingDirectory)
                }

                Section("应用") {
                    Toggle(
                        "开机启动",
                        isOn: Binding(
                            get: { settings.launchAtLoginEnabled },
                            set: { settings.setLaunchAtLoginEnabled($0) }
                        )
                    )

                    if let message = settings.launchAtLoginErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Toggle("任务完成通知", isOn: $settings.taskCompletionNotificationEnabled)
                }
            }
            .formStyle(.grouped)
        }
        .padding(24)
        .frame(width: 520)
    }

    private var outputDirectoryText: String {
        settings.defaultOutputDirectory?.displayPath ?? "跟随源文件位置"
    }

    private func chooseDefaultOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认输出目录"
        panel.message = "任务结果将默认保存到这里"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        settings.defaultOutputDirectory = url
    }
}
