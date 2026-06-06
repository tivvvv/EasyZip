# EasyZip 技术设计

## 第一期目标

- 支持 `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz` 的列表预览, 解压, 压缩.
- 支持 `.rar` 的列表预览和解压; RAR 压缩通过外部 `rar` 命令提供.
- 先不做加密压缩, 分卷压缩和云盘同步.
- 核心能力必须和 UI 解耦, 后续新增 RAR, 单文件 gzip, 单文件 xz 等格式时只增加引擎或格式适配.

## 技术栈

- 语言: Swift 6.
- UI: SwiftUI 为主, AppKit bridge 补足菜单, 拖拽, Finder 交互, 文件选择器, 窗口细节.
- 桌面集成: AppKit `NSStatusItem` 提供菜单栏常驻入口, Finder Sync extension 提供 Finder 右键菜单,
  macOS Services 提供兜底右键入口.
- 核心模块: Swift Package `EasyZipCore`.
- 共享模块: Swift Package `EasyZipShared`, 放置 App 和 Finder Sync extension 共用的轻量逻辑.
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
  App
    AppKit lifecycle
    Main menu
  MenuBar
    Status panel
  Workspace
    SwiftUI workbench
  ViewModels
    App state
  Tasks
    Archive task runner
  Persistence
    Recent records
  Support
    UI support models and helpers
  BuildSupport
  Scripts

EasyZipShared
  FinderActionHandoffStore

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
    RARCommandResolver

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
- `RARCommandResolver` 集中检测外部 `rar` 命令, UI 和 RAR 压缩引擎共用同一判断.
- `ArchiveFormat` 集中维护格式主扩展名, 别名扩展名和 UI 显示名.
- `DefaultArchiveFormatDetector` 优先读取文件头 magic number, 无法识别时回退扩展名.
- `ArchiveService.makeDefault()` 默认注册 `LibArchiveEngine` 和 `RARCommandCompressionEngine`.
- 解压默认通过 `ArchivePathValidator` 校验条目路径.
- 解压写入前会校验目标父目录的符号链接解析结果, 避免通过既有符号链接逃逸.
- `ArchivePathValidator` 会拒绝路径穿越, Windows drive path, 空组件, 控制字符和 Unicode 双向控制字符.
- 解压阶段会拒绝 hard link, FIFO, socket, character device 和 block device.
- `ExtractionResourceLimits` 默认限制条目数量, 总解压体积, 单文件体积和目录深度.
- `LibArchiveEngine` 解压前会流式预扫描归档计划, 写入文件时会按真实字节数再次校验资源限制.
- 列表预览会标记 hard link, 但不会在解压阶段创建 hard link.
- 解压默认创建与归档同名的外层目录, Core 可通过 `ExtractionOptions.shouldCreateContainingDirectory` 关闭.
- 压缩写入先生成临时归档, 成功关闭后再替换最终目标.
- libarchive 写入会透传 `CompressionOptions.compressionLevel`, `.tar` 无压缩时忽略该选项.
- 解压冲突支持 `overwrite`, `skip`, `ask` 和 `rename`; `ask` 需要 resolver 给出明确决策.
- 图形界面在选择 RAR 压缩时展示外部工具状态, 并在任务开始前拦截缺失工具.
- App 通过 `LSUIElement` 和 accessory activation policy 后台运行, 默认不显示 Dock 图标.
- AppDelegate 管理菜单栏图标和轻量状态面板, 按需创建任务工作台窗口.
- App 侧按 `App`, `MenuBar`, `Workspace`, `ViewModels`, `Tasks`, `Persistence` 和 `Support` 拆分.
- 菜单栏状态面板和任务工作台共用同一个 `EasyZipAppModel`, 因此进度, 结果和最近记录保持同步.
- `ArchiveTaskRunner` 负责 UI 层任务编排, `EasyZipAppModel` 只保留状态流转和用户操作入口.
- `RecentArchiveStore` 使用 `UserDefaults` 保存最近任务和可固定的最近输出目录.
- 菜单栏状态面板支持清空最近任务, 固定或移除输出目录, 失败任务可回到工作台查看详情.
- AppDelegate 统一处理应用退出, 运行中任务会先确认并取消后再退出.
- `TaskCompletionNotifier` 在成功完成任务后发送 macOS 系统通知.
- Finder Sync extension 打包在 `Contents/PlugIns`, 通过临时 handoff 文件把 Finder 选择传回主 app.
- `easyzip://` URL scheme 只传递操作模式和 handoff id, 旧 `item` query 入口保留兼容.
- `NSServices` 声明 `使用易压缩进行压缩` 和 `使用易压缩进行解压`, 服务入口会把 Finder 选择带入工作台.
- Finder 和 Services 后台唤起会走统一外部选择策略, 空闲时同模式合并, 不同模式替换.
- 任务运行中再次唤起会生成 `PendingExternalSelection`, 菜单栏面板和工作台同步展示并允许稍后应用.
- 进度回调使用字节数作为 unit count, 列表读取仍按条目返回.
- 已识别加密归档并返回 `ArchiveError.encryptedArchive`, 但暂不支持输入密码.
- 当前不支持分卷归档.

## 设计原则

- UI 只依赖 `ArchiveService`, 不直接依赖 libarchive 或任何 C API.
- 每个底层库只出现在自己的 engine target 内, 避免 C 依赖污染业务代码.
- 新格式优先通过新增 `ArchiveEngine` 实现接入, 不改 UI 流程.
- 格式识别优先 magic number, 无签名或读取失败时回退扩展名.
- 解压必须先做路径安全校验, 禁止绝对路径, `..`, Windows drive path, 控制字符和符号链接逃逸.
- 解压只创建普通文件, 目录和安全相对符号链接, 其他条目类型默认拒绝.
- 解压必须在写入前完成资源预扫描, 并在实际写入时对不可信头信息做二次限制.
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
- Finder 扩展: 已新增 Finder Sync extension, 后续可接 App Group 或 XPC 传递更大批量的选择.
