# EasyZip 技术设计

## 第一期目标

- 支持 `.zip` 和 `.7z` 的列表预览, 解压, 压缩.
- 先不做加密压缩, 分卷压缩, 云盘同步, Finder 扩展.
- 核心能力必须和 UI 解耦, 后续新增 RAR, tar, gzip, xz 等格式时只增加引擎或格式适配.

## 技术栈

- 语言: Swift 6.
- UI: SwiftUI 为主, AppKit bridge 补足菜单, 拖拽, Finder 交互, 文件选择器, 窗口细节.
- 核心模块: Swift Package `EasyZipCore`.
- 压缩引擎: 第一期使用 `libarchive` 作为统一底座, 覆盖 `.zip` 和 `.7z` 的读写.
- 依赖交付: 开发期可以用 Homebrew 或 pkg-config 接入, 正式发行使用自建 static XCFramework
  或随 app bundle 携带的动态库.
- 并发模型: Swift Concurrency, 每个归档任务用独立 `Task`, 支持进度回调和取消.
- 测试: XCTest 覆盖领域模型, 格式识别, 路径安全, 引擎选择, 之后补真实归档 fixture.

## 分层结构

```text
EasyZip.app
  UI
    SwiftUI views
    ViewModels
    AppKit adapters

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
- RAR 解压: 增加 `UnarEngine` 或 `XADEngine`, 只支持解压.
- tar 系列: 用现有 `LibArchiveEngine` 增加格式映射即可.
- Finder 扩展: 新增 app extension target, 只通过 IPC 或 shared service 调用核心能力.
