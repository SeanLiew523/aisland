# AIsland v0.1.1 开发交接

交接日期：2026-10-03（北京时间）。状态：`READY_FOR_REQUIREMENTS`。

用户要求在当前本机已验证的 **v0.1.0、构建 5** 基础上，开独立分支开展 **v0.1.1** 需求开发。本轮已准备工作目录、分支和交接文档；尚未实施 v0.1.1 功能、修改程序版本、安装新应用或发布新版本。新需求由用户在新窗口提供。

## 1. 新窗口使用这个工作目录

| 项目 | 已准备的值 |
| --- | --- |
| 正式仓库 | `https://github.com/SeanLiew523/aisland` |
| 共享集成目录 | `/Users/seanliew/aisland`，分支 `main` |
| v0.1.1 开发目录 | `/Users/seanliew/aisland-v0.1.1` |
| v0.1.1 分支 | `feat/v0.1.1`，已在本机创建 |
| 起始运行时代码 | `82765483ee4e3924cbe49914616f97b16c44b2bd` |
| 起始代码所在分支 | `fix/zcode-task-navigation` |
| 起始代码原目录 | `/Users/seanliew/aisland-zcode-navigation` |
| 应用名称 / Bundle ID | `AIsland` / `dev.aisland.app` |
| Swift 可执行目标 | `OpenIslandApp`；辅助程序为 `OpenIslandHooks`、`OpenIslandSetup` |

在 Codex 项目下新建本地聊天后，将工作目录设为 `/Users/seanliew/aisland-v0.1.1`，把本文件交给接手 Agent。不要自动启动额外聊天或把提示发送给其他窗口。

当前对话所在的 `/Users/seanliew/open-vibe-island` 是旧项目目录；不要把它当成 AIsland v0.1.1 的工作目录。不要以公开 `v0.1.0` 标签或尚未包含修复的 `main` 重新创建分支。

本分支按用户明确指定的构建 5 起点创建，是项目“通常从 origin/main 创建工作树”规则的一次有明确授权的例外。仍需遵守其余 `AGENTS.md` 工作流。

接手时先核对：

```sh
cd /Users/seanliew/aisland-v0.1.1
git status -sb
git branch --show-current
git remote -v
git merge-base --is-ancestor 82765483ee4e3924cbe49914616f97b16c44b2bd HEAD
```

预期分支为 `feat/v0.1.1`，`origin` 指向 `SeanLiew523/aisland`，最后一个命令退出码为 0。本次交接提交只增加文档，因此本分支会比构建 5 多一个文档提交；不要要求 `HEAD` 仍等于起始源码 SHA，也不要重置它。

## 2. 构建 5 已包含的修复

**Codex Desktop 会话识别和精确跳转。** 识别 Desktop originator，避免仅凭通用 `vscode` 来源误判为 `Unknown`；不完整 hook 不再抹掉已解析的 Desktop 跳转目标。补全已有会话缓存的 thread ID，保留等待审批和回答的状态，并适配新旧 Codex app-server 路径及响应结构。Codex CLI 与 Codex Desktop 是不同运行时，修改其中一条路径时需检查另一条是否受影响。

**ZCode 独立任务精确跳转。** 通过只读本地任务索引匹配 task ID、标题和工作目录，兼容没有项目分组的独立任务。标题不唯一时避免猜测目标；侧边栏选择与实际页面标题需要一致。

**ZCode 被其他应用遮挡时切到前台。** 窗口保持打开、没有最小化、Codex 在最前台时，从刘海点击 ZCode 会话，可以选中正确对话并把 ZCode 带到前台。用户已实测回复“正确对话已到最前台”，两次实际日志记录 `frontmost=dev.zcode.app`。

对应提交为：

- `32784f3ee8304518ebc777bda8af9650b7d3c800`：Codex 修复线的冻结起点。
- `abd59e6389803f10e3c89e11931f37d4b124ac4b`：ZCode 独立任务匹配。
- `82765483ee4e3924cbe49914616f97b16c44b2bd`：ZCode 前台切换；已经包含前两项。

构建 5 的 [CI 37108131633](https://github.com/SeanLiew523/aisland/actions/runs/37108131633) 已通过 harness 和 Universal 打包校验。安装回执记录 497 项测试通过。CI 通过与上述用户实际会话验证分别保留证据，不把“应用激活”当作“正确会话跳转”。

## 3. 保留的产品与视觉基线

正式品牌为 **AIsland**。图标采用 C1「轻侧目」：原有平顶刘海轮廓、暖纸色图标背景、象牙色胶囊眼睛和内部蓝色通知点。品牌资源在 `Assets/Brand/AIsland/`；不要在刘海上方中间额外挖凹槽。

Bloub 动效已原生融入 SwiftUI：空闲角色轻微视线移动、偶尔眨眼；运行时三个圆点依次运动；审批为粉色、回答为暖黄色，带蓝色通知点和轻微呼吸。审批和回答的眨眼约五秒一次；用户要求保留现有空闲节奏，且不接受眼睛到通知点持续快速闪动。

产品范围以 `docs/product.md` 为准，hook 契约以 `docs/hooks.md` 为准，不在这里复制完整支持矩阵。保持 WorkBuddy、Codex Desktop、Ghostty 等已有跳转能力和中英文设置界面。内部 `OpenIsland*` 类型、兼容路径和协议不是待批量改名的品牌露出。

## 4. 本机应用与设置基线

交接时已读取 `/Applications/AIsland.app/Contents/Info.plist`，确认：

- `CFBundleShortVersionString=0.1.0`、`CFBundleVersion=5`。
- `AIslandSourceCommit=82765483ee4e3924cbe49914616f97b16c44b2bd`。
- 当前主程序 SHA256 为 `be3acb73ae6db938df409a87d5482086893a9d111f1d3971b0b32ca3899160fd`，与安装回执相符。
- 使用稳定的 `Open Island Dev Local` 本地签名，自动更新禁用。

构建 5 安装回执及真实跳转证据位于：

```text
/Users/seanliew/aisland-zcode-navigation/output/verification/zcode-navigation/foreground/local-install-receipt.json
```

该回执记录安装时原有 31 项设置保持一致，并保存旧应用和设置备份。接手后的安装测试要重新备份、记录实际安装来源并核对原有设置；有明确设计的新设置可以新增，不要求未来始终只有 31 项。

当前准备分支不代表授权替换 `/Applications/AIsland.app`。需要用户测试新功能时，再根据新窗口的明确测试安排安装。不要同时启动两个使用同一 OpenIsland bridge 的实例。

注意：`scripts/launch-dev-app.sh` 的 AIsland Dev 也使用 `dev.aisland.app`，并会写入 `~/Applications/AIsland Dev.app` 后启动；其设置和 bridge 并未天然隔离。`scripts/build-aisland-app.sh --install` 会创建另一份本地安装。不要为了读代码或测试编译直接执行这些安装/启动命令，避免重新出现多个应用图标。

## 5. 与 v0.1.0 公证发布的分工

**原窗口继续负责 v0.1.0 构建 5 的签名、公证与发布；新窗口负责 v0.1.1 需求。两条工作线并行。**

原窗口工作树为 `/Users/seanliew/aisland-notarization`，分支 `feat/aisland-notarization`。其公证候选使用构建 5 的冻结程序与资源，仅重签和附加票据。接手窗口不得覆盖、重建或重传该候选，也不得更换其公开资产或操作监控。

```text
唯一发布候选目录：
/Users/seanliew/aisland-notarization/output/releases/v0.1.0-build5-notarized

已有应用公证提交：
dffd1053-f62f-4fae-8939-9c89c007405b

发布进度记录：
/Users/seanliew/aisland-notarization/output/verification/notarization/release-progress.json
```

该提交在 2026-10-03 北京时间 16:39 的保存查询中为 `In Progress`；上传成功回执已核对。此处是时间明确的快照，不是之后的实时状态。构建 1、构建 3 的旧提交都已被取代。公证完成后才替换原 `v0.1.0` 发布的四个资产并更新两处站点、README 和描述；不公开处理中等中间文案，不自动安装公证包。

交接核对时以下 PR 尚未合入 `main`，仍由原窗口集成：

- [PR #4：Codex Desktop](https://github.com/SeanLiew523/aisland/pull/4)，冻结源码 `32784f3`。
- [PR #5：ZCode](https://github.com/SeanLiew523/aisland/pull/5)，冻结源码 `8276548`。

新分支已经包含两份修复，不要重复 cherry-pick。原窗口完成集成后，新窗口在自己的干净工作树里 `git fetch origin`，审阅后按项目规则合入最新 `origin/main`，保留既有修复与 v0.1.1 改动。所有 PR 最终指向 `main`，不以 #4、#5 或公证分支作为 PR 目标，不强推 `main` 或重写 `v0.1.0` 标签。

**签名与严格公证校验工具尚在公证分支中，并非已在这个构建 5 分支全部具备。** 接手前需重新核对它们的集成情况；不要复制带“已公证”结论的未发布文案，也不要把基线 `verify-aisland-package.py` 的普通签名检查等同于 Gatekeeper/票据检查。将来公开 v0.1.1 的新程序需要自己的签名、公证和验证，不能沿用构建 5 的票据或提交编号。

## 6. 新窗口的首轮工作

先阅读本文件、`AGENTS.md`、`docs/product.md`、`docs/architecture.md`、`docs/hooks.md`、`docs/quality.md`，确认工作目录和构建 5 起点。向用户收集 v0.1.1 的具体需求、优先级和可观察的验收结果；当前没有已批准的 v0.1.1 功能列表，不把历史 roadmap 自动当成本次范围。

把需求整理为用户能审阅的范围，明确需要修改的模块和测试场景，再按小步实现、验证、提交推进。仅缺少局部信息时继续不依赖该信息的工作。接手首轮不需要重跑已通过的全部基线测试，也不要为了开发新版本重复提交公证。

重点代码入口：

| 需求涉及的区域 | 先读的文件 |
| --- | --- |
| Codex Desktop | `docs/codex-desktop-identity.md`、`Sources/OpenIslandApp/SessionDiscoveryCoordinator.swift`、`Sources/OpenIslandApp/CodexAppServerCoordinator.swift`、`Sources/OpenIslandCore/CodexSessionTracking.swift` |
| 会话跳转 / ZCode | `Sources/OpenIslandApp/TerminalJumpService.swift`、`Sources/OpenIslandApp/ZCodeConversationJumpController.swift` |
| 状态角色 / 刘海布局 | `Sources/OpenIslandApp/Views/BloubStatusGlyph.swift`、`Sources/OpenIslandApp/Views/UnifiedBars.swift`、`Sources/OpenIslandApp/Views/V6NotchContent.swift` |
| 设置与预览 | `Sources/OpenIslandApp/Views/SettingsView.swift`、`Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift` |
| 打包和版本 | `scripts/package-aisland.sh`、`scripts/package-app.sh`、`scripts/build-aisland-app.sh`、`scripts/launch-dev-app.sh`、`scripts/verify-aisland-package.py`、`.github/workflows/release.yml` |

## 7. 开发验证与版本要求

根据实际变更选择验证：

```sh
cd /Users/seanliew/aisland-v0.1.1
zsh scripts/harness.sh docs
zsh scripts/test-clt.sh --filter CodexDesktopIdentityTests
zsh scripts/test-clt.sh --filter CodexDesktopDiscoveryTests
zsh scripts/test-clt.sh --filter CodexAppServerCompatibilityTests
zsh scripts/test-clt.sh --filter ZCodeConversationJumpControllerTests
zsh scripts/test-clt.sh --filter TerminalJumpServiceTests
```

这是可选的针对性验证入口，不表示每次文案或小改动都要运行以上全部测试。运行时完成一个可交付阶段后，再执行相称的完整 CI 与 Universal 包检查；文档交接阶段只做文档、Git 基线和脚本参数核对。

涉及会话跳转时，实际验收至少覆盖：Codex 会话保持正确身份和 thread；ZCode 项目任务与独立任务都能选择正确对话；ZCode 未最小化但被 Codex 遮挡时能把正确对话带到前台；重复标题不猜错；WorkBuddy 和 Ghostty 的现有跳转没有回归。记录“选中的会话”和“前台应用”两个结果。

进入版本打包阶段后使用 `0.1.1`，构建号从 **6 或更高**开始并明确记录，不沿用构建 5。当前脚本仍有 `0.1.0` / `0.1` 默认值，需按新需求统一调整；修改文档不等于应用实际已升级。

下面是仅生成本地验收包的现有参数示例，**本轮没有执行**。执行前确认没有通过其他打包环境变量把输出路径重定向到旧候选目录：

```sh
OPEN_ISLAND_VERSION=0.1.1 \
OPEN_ISLAND_BUILD_NUMBER=6 \
OPEN_ISLAND_PACKAGE_ROOT=/Users/seanliew/aisland-v0.1.1/output/v0.1.1-local \
OPEN_ISLAND_SIGN_IDENTITY='Open Island Dev Local' \
OPEN_ISLAND_NOTARY_PROFILE='' \
zsh scripts/package-aisland.sh

python3 scripts/verify-aisland-package.py output/v0.1.1-local
```

该示例不是公开公证发布命令，不安装应用。版本号、build、`AIslandSourceCommit`、双架构、资源、设置兼容性和实际行为都需要核对。自动更新仍禁用，除非用户另行批准设计和发布自己的更新链路。

## 8. 交接完成判据与待办

交接准备完成判据：新工作树确实继承 `8276548`，运行时代码未变；文档已提交，工作树干净；原公证工作树与本机应用没有被修改。

接手待办：收集并确认新需求 → 小步开发与回归验证 → 用户实际验收 → 准备独立 v0.1.1 发布。后两项的具体安排由新窗口与用户确认，当前交接不是发布授权。

待决事项只有 v0.1.1 的具体需求和验收场景。v0.1.0 公证尚在原窗口进行，不妨碍从构建 5 开发新功能；临近集成和发布时，需要重新核对 `main`、签名校验工具和公证状态，避免基于旧快照作决定。
