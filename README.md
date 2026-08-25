<div align="center">

# QKKDecrypt | QQ 酷狗酷我网易云音乐解密工具

<img src="./封面/封面.png" width="320" alt="QKKDecrypt cover">


</div>

## 项目定位

`QKKDecrypt` 是一个面向本地文件处理场景的桌面/控制台工具集：
- 控制台版本：批处理、自动化、脚本化操作
- UI 版本：面向普通用户的桌面工作台
- 架构保持三层：`Presentation / Application / Infrastructure`

当前仓库源码统一按 **GPLv3** 发布。Windows UI 保留 **PySide6 + QFluentWidgets**；macOS UI 使用 **SwiftUI + AppKit** 原生架构，二者复用同一套 Python Application / Infrastructure 业务层。

## 分支说明

- `main`
  - 控制台版本
  - 薄入口 `main.py`
  - 打包形态：`onefile`
- `main-ui`
  - Windows：PySide6 桌面 UI，保留 Win10/11 风格、亚克力效果与动态进度反馈
  - macOS：SwiftUI/AppKit 原生桌面 UI，使用系统 NavigationSplitView、Toolbar、Form、Alert、文件面板和 Liquid Glass
  - 两端仅表现层不同，解密、转码、配置和平台适配逻辑保持一致

## 当前支持的平台

- `QQ音乐`
  - Windows 使用原有运行期解密
  - macOS 支持 QTag/V1 内嵌 EKey 文件离线解密；musicex 文件会读取已登录 QQ 音乐的信息并获取 EKey
- `酷我音乐`
  - 运行期解密
  - 需要酷我进程配合
- `酷狗音乐`
  - 文件级离线解密
- `网易云音乐`
  - 文件级离线解密

## macOS 运行与构建

macOS 适配保持 `Presentation / Application / Infrastructure` 三层结构和原有业务流程不变，平台差异仅封装在基础设施与构建层。当前支持 Apple Silicon 原生构建；Intel Mac 可在对应机器上使用相同脚本生成 `x86_64` 包。

### 下载与安装

- [QKKDecrypt v1.5.0 Release](https://github.com/yc004/QQKWKG-TriMusicDecrypt-mac/releases/tag/v1.5.0)
- `QKKDecrypt-UI-macOS-arm64.zip`：带界面的 Apple Silicon 版本，推荐普通用户使用
- `QKKDecrypt-macOS-arm64.zip`：Apple Silicon 命令行版本

解压 UI 包后，将 `QKKDecrypt-UI.app` 移入“应用程序”并启动。该版本已在 Apple Silicon macOS 上完成实际解密、界面启动、原生库加载、代码签名完整性和 9 项自动化测试验证。

QQ 音乐 QTag/V1 文件可直接离线处理。若 musicex 文件提示权限不足，请保证 macOS QQ 音乐已经登录，并在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中允许 `QKKDecrypt-UI`，然后彻底退出并重新打开应用。

### 从源码构建

开发环境要求 Python 3.10 或更高版本、Node.js、Swift 6 / macOS SDK，以及 FFmpeg（可放入 `assets`，也可通过 Homebrew 安装）：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-build.txt
npm run package:mac
```

产物位于：

- `release/QKKDecrypt`
- `release/QKKDecrypt-macOS-<arch>.zip`
- `release/QKKDecrypt-UI-macOS-<arch>.zip`（标准 macOS `.app`）
- `release/QKKDecrypt-UI-macOS-<arch>.dmg`（拖入“应用程序”安装）

macOS 打包版的配置、日志和默认输出目录位于 `~/Library/Application Support/QKKDecrypt`。QQ 音乐的 QTag/V1 `.mflac/.mgg` 会走纯离线 QMC2 解密；新版 musicex 文件会从已登录的 QQ 音乐客户端读取凭据并请求该文件对应的 EKey。酷狗、网易云和批量转码均使用与 Windows 相同的应用层逻辑；原生加速库会构建为 `.dylib`，AES 使用跨平台密码库实现相同算法。

QQ 音乐的 Windows 运行期链仍保留不变，macOS 改用格式兼容的 QMC2 离线/EKey 链，因此不再依赖 Windows DLL。酷我的运行期解密仍依赖 Windows 客户端内部 ABI；仓库现有资料只有 DLL 名称、MSVC 符号和 `thiscall` 调用约定，不能直接复用到 macOS Mach-O 客户端。

## UI 路线

macOS 主界面采用真正的 **SwiftUI + AppKit** 原生架构，不再通过 Qt 模拟 Apple 外观。界面使用系统 `NavigationSplitView`、Toolbar、Form、GroupBox、Alert、`NSOpenPanel`、SF Symbols、动态系统色、辅助功能语义和键盘快捷键；在 macOS 26 及以上由系统标准组件自动采用 Liquid Glass，任务状态、文件选择、任务记录操作与底部主操作区使用 `GlassEffectContainer`、`glassEffect`、`glass` 和 `glassProminent` 构成统一的悬浮功能层。步骤卡片与日志正文仍使用标准内容层，确保层级和可读性；旧版 macOS 会自动降级为系统 Material 与 bordered 控件。设计依据为 Apple 官方 [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials) 与 [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)。

主窗口采用以任务为中心的连续工作流：边栏只保留“工作台”和“任务记录”，解密与批量转码在同一工作台内切换；任务类型、音乐平台和转码格式在 macOS 27 使用系统 `Picker(.tabs)` 滑动胶囊，由系统负责选中形态、动画和辅助功能，旧系统自动降级为原生 `Picker(.segmented)`。布尔配置统一使用系统 switch 开关。输入输出、处理方式和执行操作按步骤排列，高级参数默认收起，运行状态与停止操作固定显示在窗口底部。低频全局配置使用标准 macOS `⌘,` 设置窗口，减少主流程中的跳转和重复配置。

SwiftUI 前端通过内嵌的 `QKKDecryptBackend` 薄桥接调用原有 Python CLI：平台解密、批量转码、配置格式、输出路径和运行时适配仍由既有 Application / Infrastructure 层负责。Windows 继续构建原 PySide6 UI，功能逻辑不分叉。

## 打包

Windows：

```powershell
npm run package
```

默认会构建：
- `QKKDecrypt.exe`
- `QKKDecrypt-UI-setup.exe`

macOS：

```bash
npm run package:mac
```

## 合规与风险边界

以下内容是工程合规说明，不构成法律意见。

### 你应当只在这些前提下使用本项目
- 仅处理你本人拥有**合法访问权限**的本地文件
- 自行确认你的使用行为符合所在地法律、版权规则、平台协议和组织政策
- 不要把本项目用于批量分发、倒卖、牟利或规避付费授权

### 项目不承诺这些事情
- 不承诺适用于所有地区、所有平台规则、所有用途
- 不承诺一定符合你所在地区的合规要求
- 不承诺任何特定商业用途可直接使用
- 不为用户的侵权、违约或违规使用承担责任

### 对外发布建议口径
如果你二次分发、改包或转载，请至少保留下列表达：

> 本项目按 GPLv3 发布，仅面向学习、研究与本地文件处理场景。使用者应仅处理自己拥有合法访问权限的文件，并自行确认其行为符合适用法律、版权规则及平台协议。项目作者不对非法或违规用途负责。

## 第三方组件说明

请同时阅读：
- [THIRD_PARTY_LICENSES.md](./THIRD_PARTY_LICENSES.md)

当前需要特别注意：
- `SwiftUI / AppKit`（macOS 系统框架）
- `PySide6`
- `PySide6-Fluent-Widgets`
- `FFmpeg`
- 其他运行期依赖和打包依赖

## 致谢

- QQ 音乐解密模型思路参考项目：
  - [`qqmusic_decrypt`](https://github.com/luyikk/qqmusic_decrypt)
- 网易云音乐解密模型参考 `ncmdump` 相关实现思路
- 其他平台相关逻辑以学习、研究和兼容性验证为目的持续整理

## 许可证

本仓库源码按 **GNU GPL v3** 发布：
- [LICENSE](./LICENSE)

如果你计划进行商业使用、闭源分发或接入额外第三方组件，请先自行完成完整的许可证核验和风险评估。
