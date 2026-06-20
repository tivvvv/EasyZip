import EasyZipCore
import Foundation

enum ArchiveErrorMessageFormatter {
    static func message(for error: Error) -> String {
        guard let archiveError = error as? ArchiveError else {
            return "操作未完成, 请检查文件和输出目录"
        }

        switch archiveError {
        case .unsupportedFormat(let value):
            return "暂不支持该归档格式: \(value)"
        case .unsupportedOperation(let format, _):
            return "该格式暂不支持当前操作: .\(format.fileExtension)"
        case .invalidSource(let url):
            return "源文件无效: \(url.path)"
        case .invalidDestination(let url):
            return "输出位置无效: \(url.path)"
        case .encryptedArchive(let url):
            return "加密归档需要密码: \(url.path)"
        case .incorrectArchivePassword(let url):
            return "归档密码不正确: \(url.path)"
        case .externalToolUnavailable(let toolName):
            return "未找到外部工具: \(toolName), RAR 压缩需要安装 RAR 命令行工具"
        case .conflictRequiresDecision(let url):
            return "目标已存在, 需要选择冲突处理方式: \(url.path)"
        case .unsupportedEntryType(let path, let type):
            return "归档内包含暂不支持的条目类型: \(type), \(path)"
        case .unsafeEntryPath(let path):
            return "归档内包含不安全路径: \(path)"
        case .extractionResourceLimitExceeded(let violation):
            return resourceLimitErrorMessage(for: violation)
        case .engineFailure:
            return "归档引擎执行失败"
        case .cancelled:
            return "任务已取消"
        }
    }

    private static func resourceLimitErrorMessage(
        for violation: ExtractionResourceLimitViolation
    ) -> String {
        switch violation {
        case .entryCount(let limit, let actual):
            return "归档条目数量过多: \(actual), 最大允许 \(limit)"
        case .totalUncompressedSize(let limit, let actual):
            return "归档解压后体积过大: \(formatByteCount(actual)), 最大允许 \(formatByteCount(limit))"
        case .singleFileUncompressedSize(let path, let limit, let actual):
            return "归档内单个文件过大: \(path), \(formatByteCount(actual)), 最大允许 \(formatByteCount(limit))"
        case .directoryDepth(let path, let limit, let actual):
            return "归档目录层级过深: \(path), 当前 \(actual), 最大允许 \(limit)"
        }
    }

    private static func formatByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
