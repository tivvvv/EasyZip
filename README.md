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
- 可选外部 `zstd` 命令, 用于创建 TAR.ZST 归档

## 图形界面

- 应用以菜单栏常驻方式运行, 不显示在 Dock 中.
- 首次启动会展示轻量引导, 提示菜单栏入口, Finder Sync 和通知权限.
- 菜单栏图标展示轻量状态面板, 可打开工作台, 直接选择压缩或解压.
- 菜单栏状态面板展示最近任务和最近输出目录, 支持清空任务, 固定目录和移除目录.
- 菜单栏状态面板可打开设置页, 首次启动引导和环境诊断页.
- 应用菜单可打开设置页.
- 失败或取消任务可从菜单栏面板回到工作台查看详情.
- 任务运行时菜单栏图标旁展示进度状态.
- Finder 或 Services 从后台唤起时, 同模式选择会合并, 不同模式选择会替换队列.
- 任务运行中再次唤起时会暂存新选择, 并在菜单栏面板和工作台同步提示.
- 退出应用时会拦截运行中任务, 确认后先取消任务再退出.
- 任务完成后发送 macOS 系统通知.
- 工作台和菜单栏状态面板展示当前会话任务队列, 支持重试, 清理和定位输出.
- Finder Sync 扩展提供 `使用易压缩进行压缩` 和 `使用易压缩进行解压` 右键菜单.
- Finder Sync 使用临时 handoff 文件传递大量选择, 避免文件多时 URL 过长.
- Finder handoff 默认限制文件数量和 payload 大小, 并使用私有目录和文件权限.
- macOS Services 保留同名入口作为系统右键菜单兜底.
- 任务式拖拽工作台, 左侧维护待处理队列, 右侧承载拖拽区, 选项面板和预览区.
- 支持压缩和解压两种模式切换.
- 压缩模式支持选择输出目录, 归档格式, 归档名称, 隐藏文件和目录保留策略.
- 压缩模式支持 ZIP 加密压缩.
- 选择 RAR 或 TAR.ZST 压缩时展示外部命令可用状态, 并在任务开始前拦截缺失工具.
- 解压模式支持选择输出目录, 冲突询问, 自动重命名, 覆盖, 跳过, 单归档预览和按归档名创建外层目录.
- 解压模式选择或拖入不支持的文件时会明确提示, 并保留可处理归档.
- 设置页支持默认输出目录, 默认压缩格式, 默认冲突策略, 开机启动, 任务完成通知和外层目录策略.
- 设置页支持失效默认输出目录提示, 工作台会自动回退到源文件位置.
- 设置页支持一键恢复默认设置.
- 解压加密归档时支持输入密码, 密码错误会提示重新输入.
- 归档预览支持搜索, 排序, 类型列, 修改时间列, 层级缩进, 详情面板和风险条目标记.
- 归档预览支持选择当前结果, 追加当前结果, 反选, 只选文件, 只选目录和只选风险项.
- 归档预览支持选择条目后只解压所选内容.
- 任务执行时展示字节级进度, 并提供取消和在 Finder 中定位输出目录.

## 核心设计

- 高内聚核心模块, 归档领域模型, 引擎协议, 服务入口和安全校验分层清晰.
- 低耦合引擎接入, 后续新增格式时优先扩展 `ArchiveEngine`.
- 安全优先, 解压前校验条目路径, 防止路径穿越和异常目标路径.
- 解压默认启用资源限制, 防止异常归档消耗过多磁盘和文件系统资源.
- 可测试结构, 格式识别, 引擎选择, 路径安全策略和共享 handoff 逻辑均可独立验证.

## 当前状态

- 已建立 `EasyZipCore` 核心包.
- 已接入 macOS 系统 `libarchive`.
- 已支持 `.zip`, `.7z`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst` 的创建, 列表读取和解压.
- 已支持 `.gz`, `.xz` 单文件压缩流的创建, 列表读取和解压.
- 已支持 `.tgz`, `.tbz`, `.tbz2`, `.txz`, `.tzst` 归档扩展名识别和解压.
- 已支持 `.rar` 归档扩展名识别, 列表读取和解压.
- 已支持 `.zip`, `.7z`, `.rar`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.gz`, `.xz` 的 magic number 优先识别.
- 已接入可选 RAR 压缩引擎和外部工具检测; 创建 `.rar` 需要系统中安装可执行的 `rar` 命令.
- 已支持 `.tar.zst` 创建, 读取和解压; 创建 `.tar.zst` 需要系统中安装可执行的 `zstd` 命令.
- 已支持压缩等级传递, ZIP AES-256 加密压缩, 冲突询问, 冲突重命名和批量冲突决策.
- 已支持字节级进度, 取消检查和加密归档解压.
- RAR 加密压缩暂不支持, 避免通过外部命令参数暴露密码.
- 解压默认创建与归档同名的外层目录, Core 可通过 `ExtractionOptions.shouldCreateContainingDirectory` 关闭.
- 归档预览已支持搜索过滤, 多维排序, 总大小统计, 条目详情和链接类高风险标记.
- 归档预览已支持多选快捷操作, 可按当前结果, 文件, 目录和风险项快速生成解压选择.
- 解压可通过 `ExtractionOptions.selectedEntryPaths` 只处理指定条目或目录子树.
- 解压会拒绝 hard link, FIFO, socket 和设备文件等高风险条目类型.
- 解压路径会拒绝控制字符, Unicode 双向控制字符, 路径穿越和符号链接逃逸.
- 解压会预扫描条目数量, 总解压体积, 单文件体积和目录深度, 并在写入时复查真实字节数.
- 压缩输出使用临时文件完成后替换, 避免失败时提前破坏已有归档.
- 已新增 `EasyZipApp` macOS 菜单栏入口, Finder Sync 右键菜单和 Finder 服务入口.
- 已新增首次启动引导, 可引导用户打开 Finder Extension 设置, 通知权限和工作台.
- 已新增环境诊断页, 可检查安装位置, Finder Sync, 通知权限, RAR 命令, zstd 命令, 默认输出目录和签名状态.
- 已新增设置页和设置持久化, 工作台会读取默认任务选项并同步设置变更提示.
- 已支持失效默认输出目录检测和默认设置恢复.
- 已新增当前会话任务队列, 每个任务记录独立状态, 进度, 结果和重试快照.
- 已支持 Finder Sync handoff 文件传参, 并保留旧 URL query 入口作为兼容兜底.
- 已对 Finder handoff 增加权限, 容量和启动清理保护.
- 已抽取共享文件 URL 标准化逻辑, App, Finder Sync extension 和 handoff 读写共用同一去重策略.
- 已抽取 App 输入过滤逻辑, 解压模式会统一忽略不支持文件并提示用户.
- 已抽取共享归档文件名匹配逻辑, App 和 Finder Sync extension 共用同一支持后缀判断.
- 已抽取所选条目解压匹配和 libarchive 读取错误映射逻辑, 并补充独立单元测试.
- 已提供正式 `.app` 包结构构建脚本.
- 已提供发布构建脚本, 可生成 zip, dmg, SHA256 校验文件和构建摘要.
- 已提供 DMG 打包和完整性检查脚本, 发布包会包含应用和 Applications 入口.
- 已提供可选公证脚本, 可配合 Developer ID 签名和 Apple notarytool 使用.
- 已提供产物完整性检查脚本, 可独立校验 `.app` 结构, Info.plist, Finder Sync extension 和签名.
- 已新增 GitHub Actions CI, push 和 pull request 会执行统一质量检查.
- 已提供 `EasyZipTestSupport` 测试支撑 target, 统一管理临时工作目录.
- 已覆盖中文路径, emoji 路径, 空目录, 符号链接, 权限, 修改时间和密码归档测试.
- 已新增真实归档 fixture 测试, 覆盖 `.zip`, `.7z`, `.tar.gz`, 加密 zip, 损坏 zip 和路径穿越 zip.

## 开发命令

```bash
swift build --product EasyZipApp
swift run EasyZipApp
swift test
Scripts/build_app_bundle.sh
Scripts/check_app_bundle.sh
Scripts/package_dmg.sh
Scripts/check_dmg.sh
Scripts/release_build.sh
Scripts/notarize_release.sh dist/release/EasyZip-0.1.0-1.dmg
Scripts/ci_check.sh
open -n dist/易压缩.app
```

默认 `.app` 产物输出到 `dist/易压缩.app`.
默认发布产物输出到 `dist/release`, 包含 zip, dmg, SHA256 校验文件和构建摘要.

## 安装和 Finder Sync

1. 运行 `Scripts/release_build.sh`.
2. 打开 `dist/release/EasyZip-0.1.0-1.dmg`.
3. 将 `易压缩.app` 拖到 `Applications`.
4. 首次运行后, 如 Finder 右键菜单未出现, 打开 System Settings -> Privacy & Security -> Extensions -> Finder Extensions, 启用 EasyZip Finder Sync Extension.
5. Finder Sync 入口未启用时, macOS Services 入口仍可作为右键菜单兜底.

Developer ID 发布时可设置 `CODE_SIGN_IDENTITY`, 例如 `Developer ID Application: Example`.
完成发布构建后可运行 `Scripts/notarize_release.sh dist/release/EasyZip-0.1.0-1.dmg` 提交公证.
