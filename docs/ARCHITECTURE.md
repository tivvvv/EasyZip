# EasyZip 技术设计

## 第一期目标

- 支持 `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz` 的列表预览, 解压, 压缩.
- 支持 `.rar` 的列表预览和解压; RAR 压缩通过外部 `rar` 命令提供.
- 先不做加密压缩, 分卷压缩, 云盘同步, Finder 扩展.
- 核心能力必须和 UI 解耦, 后续新增 RAR, 单文件 gzip, 单文件 xz 等格式时只增加引擎或格式适配.

## 技术栈

- 语言: Swift 6.
- UI: SwiftUI 为主, AppKit bridge 补足菜单, 拖拽, Finder 交互, 文件选择器, 窗口细节.
- 核心模块: Swift Package `EasyZipCore`.
- 压缩引擎: 第一期使用 macOS 系统 `libarchive` 作为统一底座, 覆盖常见归档格式的读写.
- RAR 压缩: 系统 `libarchive` 不提供 RAR writer, 因此通过可选外部 `rar` 命令接入.
- App 交付: 通过 `Scripts/build_app_bundle.sh` 生成 `dist/易压缩.app`.
- 依赖交付: 当前使用 macOS 系统 `libarchive`, 后续如需跨系统版本一致性,
  再评估随 app bundle 携带动态库.
- 并发模型: Swift Concurrency, 每个归档任务用独立 `Task`, 支持进度回调和取消.
- 测试: XCTest 覆盖领域模型, 格式识别, 路径安全, 引擎选择, 之后补真实归档 fixture.

## 分层结构

```text
EasyZip.app
  UI
    SwiftUI views
    ViewModels
    AppKit adapters
    BuildSupport
    Scripts

EasyZipCore
  Domain
    ArchiveFormat
    ArchiveEntry
    ArchiveRequest
    ArchiveProgress
    ArchiveError

  Ports
    ArchiveEngine
    ArchiveFormatDetecting

  Services
    ArchiveService
    ArchiveEngineRegistry
    DefaultArchiveFormatDetector

  Security
    ArchivePathValidator

  Engines
    LibArchiveEngine
    Future engines
```

## 当前实现

- `LibArchiveEngine` 已实现 `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz` 的列表读取,
  解压和压缩.
- `LibArchiveEngine` 已实现 `.rar` 的列表读取和解压.
- `RARCommandCompressionEngine` 已实现 `.rar` 创建的外部命令适配; 未安装 `rar` 时返回明确错误.
- `ArchiveFormat` 集中维护格式主扩展名, 别名扩展名和 UI 显示名.
- `ArchiveService.makeDefault()` 默认注册 `LibArchiveEngine` 和 `RARCommandCompressionEngine`.
- 解压默认通过 `ArchivePathValidator` 校验条目路径.
- 解压写入前会校验目标父目录的符号链接解析结果, 避免通过既有符号链接逃逸.
- 压缩写入先生成临时归档, 成功关闭后再替换最终目标.
- 解压冲突支持 `overwrite`, `skip`, `ask` 和 `rename`.
- 进度回调使用字节数作为 unit count, 列表读取仍按条目返回.
- 已识别加密归档并返回 `ArchiveError.encryptedArchive`, 但暂不支持输入密码.
- 当前不支持分卷归档.

## 设计原则

- UI 只依赖 `ArchiveService`, 不直接依赖 libarchive 或任何 C API.
- 每个底层库只出现在自己的 engine target 内, 避免 C 依赖污染业务代码.
- 新格式优先通过新增 `ArchiveEngine` 实现接入, 不改 UI 流程.
- 格式识别先基于扩展名, 后续增加 magic number 检测.
- 解压必须先做路径安全校验, 禁止绝对路径, `..`, Windows drive path 和符号链接逃逸.
- 压缩任务和解压任务统一使用 request object, 避免方法参数越来越长.

## 第一期模块边界

- `ArchiveService`: 业务入口, 负责格式识别, 引擎选择, 调用具体操作.
- `ArchiveEngineRegistry`: 管理多个引擎, 根据格式和操作选择最合适的引擎.
- `ArchiveEngine`: 引擎协议, libarchive, libzip, sevenzip CLI fallback 都实现这个协议.
- `ArchivePathValidator`: 纯安全逻辑, 不知道 UI, 不知道底层库.
- `DefaultArchiveFormatDetector`: 可替换的格式识别器.

## 后续扩展路径

- ZIP 高级能力: 如果需要 AES 加密, 注释编码兼容, 原地修改 ZIP, 增加 `LibZipEngine`.
- 7z 疑难兼容: 如果 libarchive 在加密 7z 或特殊压缩方法上不足, 增加 `SevenZipEngine`
  作为 fallback.
- RAR 兼容性: 如 libarchive 对部分 RAR 变体不足, 增加 `UnarEngine` 或 `XADEngine` 作为解压 fallback.
- tar 系列: 已通过现有 `LibArchiveEngine` 接入, 后续可继续增加 `.tar.zst`.
- Finder 扩展: 新增 app extension target, 只通过 IPC 或 shared service 调用核心能力.
