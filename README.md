# EasyZip

EasyZip 是一款面向 macOS 的归档工具, 目标是提供稳定, 安全, 可扩展的压缩与解压体验.

第一期聚焦常见归档格式, 支持归档预览, 解压和压缩. 核心能力独立封装在 `EasyZipCore`
Swift Package 中, 图形界面通过 `EasyZipApp` 提供任务式拖拽工作台.

## 技术栈

- Swift 6
- SwiftUI + AppKit
- Swift Package Manager
- XCTest
- libarchive, 作为第一期压缩与解压引擎
- 可选外部 `rar` 命令, 用于创建 RAR 归档

## 图形界面

- 应用以菜单栏常驻方式运行, 不显示在 Dock 中.
- 菜单栏图标展示轻量状态面板, 可打开工作台, 直接选择压缩或解压.
- 菜单栏状态面板展示最近任务和最近输出目录, 任务运行时图标旁展示进度状态.
- 任务完成后发送 macOS 系统通知.
- Finder Sync 扩展提供 `使用易压缩进行压缩` 和 `使用易压缩进行解压` 右键菜单.
- macOS Services 保留同名入口作为系统右键菜单兜底.
- 任务式拖拽工作台, 左侧维护待处理队列, 右侧承载拖拽区, 选项面板和预览区.
- 支持压缩和解压两种模式切换.
- 压缩模式支持选择输出目录, 归档格式, 归档名称, 隐藏文件和目录保留策略.
- 选择 RAR 压缩时展示 `rar` 命令可用状态, 并在任务开始前拦截缺失工具.
- 解压模式支持选择输出目录, 冲突处理策略, 单归档预览和按归档名创建外层目录.
- 任务执行时展示字节级进度, 并提供取消和在 Finder 中定位输出目录.

## 核心设计

- 高内聚核心模块, 归档领域模型, 引擎协议, 服务入口和安全校验分层清晰.
- 低耦合引擎接入, 后续新增 RAR, 单文件 gzip, 单文件 xz 等格式时优先扩展 `ArchiveEngine`.
- 安全优先, 解压前校验条目路径, 防止路径穿越和异常目标路径.
- 解压默认启用资源限制, 防止异常归档消耗过多磁盘和文件系统资源.
- 可测试结构, 格式识别, 引擎选择和路径安全策略均可独立验证.

## 当前状态

- 已建立 `EasyZipCore` 核心包.
- 已接入 macOS 系统 `libarchive`.
- 已支持 `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz` 的创建, 列表读取和解压.
- 已支持 `.tgz`, `.tbz`, `.tbz2`, `.txz` 归档扩展名识别和解压.
- 已支持 `.rar` 归档扩展名识别, 列表读取和解压.
- 已支持 `.zip`, `.7z`, `.rar`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz` 的 magic number 优先识别.
- 已接入可选 RAR 压缩引擎和外部工具检测; 创建 `.rar` 需要系统中安装可执行的 `rar` 命令.
- 已支持压缩等级传递, 冲突重命名, `ask` 冲突决策, 字节级进度, 取消检查和加密归档识别.
- 解压默认创建与归档同名的外层目录, Core 可通过 `ExtractionOptions.shouldCreateContainingDirectory` 关闭.
- 解压会拒绝 hard link, FIFO, socket 和设备文件等高风险条目类型.
- 解压路径会拒绝控制字符, Unicode 双向控制字符, 路径穿越和符号链接逃逸.
- 解压会预扫描条目数量, 总解压体积, 单文件体积和目录深度, 并在写入时复查真实字节数.
- 压缩输出使用临时文件完成后替换, 避免失败时提前破坏已有归档.
- 已新增 `EasyZipApp` macOS 菜单栏入口, Finder Sync 右键菜单和 Finder 服务入口.
- 已提供正式 `.app` 包结构构建脚本.
- 已覆盖中文路径, emoji 路径, 空目录, 符号链接, 权限和修改时间测试.

## 开发命令

```bash
swift build --product EasyZipApp
swift run EasyZipApp
swift test
Scripts/build_app_bundle.sh
open -n dist/易压缩.app
```

默认 `.app` 产物输出到 `dist/易压缩.app`.
