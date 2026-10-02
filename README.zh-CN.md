<p align="center">
  <img src="docs/images/readme-banner.svg" alt="AIsland — 菜单栏里的 Agent 控制台" width="760">
</p>

<h1 align="center">AIsland</h1>

<p align="center">
  <strong>本地优先的 macOS AI 编程 Agent 控制台。</strong>
  <br>
  监控会话、处理审批，并精确跳回对应终端或桌面端对话。
  <br><br>
  <strong>中文</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/SeanLiew523/aisland/releases/latest"><img src="https://img.shields.io/github/v/release/SeanLiew523/aisland?style=flat-square&label=release&color=blue" alt="最新版本"></a>
  <a href="https://github.com/SeanLiew523/aisland/stargazers"><img src="https://img.shields.io/github/stars/SeanLiew523/aisland?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="许可证：GPL v3"></a>
</p>

<p align="center">
  <a href="https://github.com/SeanLiew523/aisland/releases/latest/download/AIsland.dmg">下载 DMG</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="docs/index.md">文档</a> ·
  <a href="docs/product.md">产品范围</a> ·
  <a href="CONTRIBUTING.zh-CN.md">参与贡献</a>
</p>

<p align="center">
  <a href="https://seanliew523.github.io/aisland/"><img src="docs/images/aisland-demo.gif" alt="AIsland 原生动态演示：空闲、思考、审批、回答、会话与完成" width="720"></a>
</p>

<p align="center">20 秒原生演示 · 示例会话 · 点击观看完整演示</p>

> AIsland 是基于 [Open Island](https://github.com/Octane0411/open-vibe-island) 开发的独立项目，沿用 GPL-3.0 许可证，并拥有独立的产品路线与发布节奏。详见[与上游的关系](docs/upstream.md)。

## AIsland 是什么？

AIsland 驻留在 Mac 刘海或顶部栏，为本地 AI 编程 Agent 提供一个轻量控制面板：查看会话状态、处理权限请求和问题、接收完成事件，并一键回到对应终端、IDE 或桌面 Agent 对话。

所有数据都在本机处理：不需要 AIsland 账号，没有服务端、分析 SDK 或遥测。

观看[原生动效演示](https://seanliew523.github.io/aisland/)，了解当前 C1 图标与状态表情。

## 核心特点

- **状态表情**：空闲时轻微眼神移动，思考时三点依次跳动，审批粉色、回答暖黄色；等待状态约每五秒眨眼一次
- **原生 macOS**：SwiftUI + AppKit，不是 Electron 套壳
- **本地优先**：使用本地 socket、转录文件和进程发现
- **多 Agent**：支持 Claude Code、Codex、ZCode、WorkBuddy、Cursor、Gemini CLI、OpenCode 等
- **精确跳回**：除终端定位外，还支持精确打开 ZCode、WorkBuddy 对话
- **可交互控制**：对支持的 Agent 执行允许/拒绝和问题回答
- **Fail open**：AIsland 不可用时，不阻塞 Agent 继续运行
- **中英双语界面**

## 支持的 Agent

| Agent | 当前集成能力 |
|---|---|
| **Claude Code** | Hooks、转录发现、权限/问题交互、状态栏用量桥接 |
| **Codex CLI 与桌面端** | 低噪声 Hooks、本地用量、app-server 生命周期、桌面端精确深链跳转 |
| **OpenCode** | 内置插件、生命周期、权限与问题事件 |
| **Qoder** | `~/.qoder/settings.json` 中的 Claude 格式 Hooks |
| **Qwen Code** | `~/.qwen/settings.json` 中的 Claude 格式 Hooks |
| **Factory** | `~/.factory/settings.json` 中的 Claude 格式 Hooks |
| **CodeBuddy** | `~/.codebuddy/settings.json` 中的 Claude 格式 Hooks |
| **ZCode** | 七类 Hook、交互式权限决策、桌面端存活检测，以及通过本地任务索引和 macOS 辅助功能精确定位对话 |
| **WorkBuddy** | 九类 Hook、桌面端存活检测，以及通过 `workbuddy://chat/<session-id>` 精确跳回任务对话 |
| **Cursor** | Hook 集成、会话追踪、工作区跳转 |
| **Gemini CLI** | 生命周期 Hooks 和 fire-and-forget 会话更新 |
| **Kimi CLI** | TOML Hook 安装、生命周期和权限交互 |
| **Grok Build** | 受管 Hook 文件、生命周期与终端跳回 |
| **Pi** | 内置 TypeScript 扩展、生命周期与终端信息 |
| **Oh My Pi** | 内置扩展及同等生命周期覆盖 |

详细事件合同和兼容边界见 [docs/hooks.md](docs/hooks.md)。

## 支持的终端和 IDE

Terminal.app、Ghostty、iTerm2、WezTerm、Warp、cmux、Kaku、tmux、Zellij 支持精确跳回。VS Code、Cursor、Windsurf、Trae、Zed 和 JetBrains IDE 支持工作区级激活。

## ZCode 与 WorkBuddy

这两个集成是 AIsland 的一等功能：

- **ZCode** 的配置位于 `~/.zcode/cli/config.json`。AIsland 保存稳定的会话 ID，只读查询 `~/.zcode/v2/tasks-index.sqlite`，通过辅助功能选择对应侧栏对话，并核对最终页面标题。精确定位不可用时，会安全降级到工作区窗口或应用激活。
- **WorkBuddy** 使用 `~/.workbuddy/settings.json` 中的 Claude 兼容 Hooks。AIsland 跟随桌面应用存活状态，并使用 WorkBuddy 自己的 `workbuddy://chat/<session-id>` 路由打开对应任务对话。

## 快速开始

### 下载安装

从 [GitHub Releases](https://github.com/SeanLiew523/aisland/releases) 下载最新 DMG，打开后把 **AIsland** 拖入 **Applications**。

初期版本属于开发构建，尚未经过 Apple 公证。如果 Gatekeeper 阻止启动，可在“系统设置 → 隐私与安全性”中为 AIsland 选择“仍要打开”。若下载文件带有隔离属性，也可以执行：

```bash
xattr -dr com.apple.quarantine "/Applications/AIsland.app"
```

系统要求：macOS 14+；发布流程会构建同时支持 Apple Silicon 和 Intel 的 Universal 应用。

### 从源码运行

```bash
git clone https://github.com/SeanLiew523/aisland.git
cd aisland
swift build
swift run OpenIslandApp
```

在本机生成 AIsland 应用、ZIP 和 DMG：

```bash
OPEN_ISLAND_VERSION=0.1.0 zsh scripts/package-aisland.sh
```

需要执行确定性冒烟验证时，运行 `zsh scripts/harness.sh smoke`。

内部 executable target 继续保留 `OpenIsland` 前缀，以兼容现有 Hooks 和本地数据路径；对外应用名称为 **AIsland**。

首次启动后，在“设置 → 安装”中选择需要接入的 Agent，再安装对应 Hooks。

AIsland 沿用 OpenIsland 本机桥接协议。启动前请退出 Agent Island 或 Alsland；旧应用和偏好设置不会自动迁移。

## 工作原理

```text
编程 Agent
    ↓ Hook 事件
OpenIslandHooks CLI
    ↓ 本地 Unix socket
BridgeServer → 会话状态 → AIsland UI
    ↓ 点击
终端 / IDE / 精确桌面端对话
```

仓库是一个包含四个主要 target 的 Swift package：

| Target | 作用 |
|---|---|
| `OpenIslandApp` | SwiftUI/AppKit 应用、菜单栏、悬浮层、设置和跳回 |
| `OpenIslandCore` | 模型、桥接协议、安装器、发现与持久化 |
| `OpenIslandHooks` | 把 Agent Hook 事件转发到本机的轻量 CLI |
| `OpenIslandSetup` | 安装和卸载受管集成的 CLI |

实现细节见[架构](docs/architecture.md)、[Hooks](docs/hooks.md)和[打包](docs/packaging.md)。

## 项目方向

AIsland 不属于上游 fork network，并按自己的路线发展。当前重点包括：

- 在真实桌面会话中保证 ZCode、WorkBuddy 的可靠性；
- 低噪声、可审查的 Hook 管理；
- 从“激活应用”升级为“精确跳回对应对话”；
- 原生 macOS 交互和稳定的本地权限身份；
- 不依赖云端、由使用者需求驱动的功能。

## 参与贡献

欢迎提交 Issue 和 Pull Request。请先阅读 [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)，并确保改动保持增量、可审查，同时在对应真实运行环境中完成验证。

## Contributors · 贡献者

<table>
  <tr>
    <td align="center" width="160">
      <a href="https://github.com/SeanLiew523"><img src="https://avatars.githubusercontent.com/u/208326784?v=4&amp;s=128" width="64" height="64" alt="SeanLiew523"></a><br>
      <a href="https://github.com/SeanLiew523"><strong>SeanLiew523</strong></a><br>
      <sub>项目维护者</sub>
    </td>
    <td align="center" width="160">
      <a href="https://chatgpt.com/"><img src="https://images.ctfassets.net/j22is2dtoxu1/intercom-img-d177d076c9a5453052925143/49d5d812b0a6fcc20a14faa8c629d9fb/icon-ios-1024_401x.png?fm=webp&amp;q=80&amp;w=128" width="64" height="64" alt="ChatGPT"></a><br>
      <a href="https://chatgpt.com/"><strong>ChatGPT / Codex</strong></a><br>
      <sub>AI 开发助手</sub>
    </td>
  </tr>
</table>

## 许可证与致谢

AIsland 使用 [GNU General Public License v3.0](LICENSE) 发布。

本项目派生自 [Open Island](https://github.com/Octane0411/open-vibe-island)，保留原有版权和许可证声明，并感谢上游作者的工作。截至 2026 年 10 月 2 日，AIsland 的独立适配包括 C1 品牌、原生状态角色及 ZCode / WorkBuddy 集成。AIsland 不是 Open Island 官方版本。

原生状态角色改编自 [bloub](https://github.com/jeremy-prt/bloub)，保留其 [MIT 许可证](docs/licenses/bloub-MIT.txt)。
