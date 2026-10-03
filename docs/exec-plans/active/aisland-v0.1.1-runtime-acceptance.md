# AIsland v0.1.1 正式应用与四来源验证

状态：`IN_PROGRESS`。用户认可第六版 `32c94f2fb0282242d17ef4db63f6c169a874e25f` 并定版，标签 `review/v0.1.1-intro-r6` 固定该原型；第五版 `86f2865` 回退点保留。v0.1.0 公证仍由原窗口负责。

## 完整验收包首次启动诊断

`d6c5937` 的独立 `runtime-live` 构建 6 包已构建并通过深度严格签名校验，但两次 CUA 原生启动均退出，尚无引导展示回执。这不是首启验收通过。2026-10-04 01:18:58 的实际进程 `90562` 日志明确记录 Foundation 拒绝用自己的 bundle identifier 再创建 UserDefaults suite，随后 `exit(1), ran for 82ms`。对外部 Bundle(path:) 的配置探针原先通过，遗漏了真实主 bundle 的 Foundation 语义。

修复后，已经通过严格配置校验且与主 bundle ID 相同的验收配置使用 `.standard`，它实际属于独立验收 bundle 的偏好域；外部探针仍使用显式 case suite。生产 bundle 不进入该验收分支。启动失败现在输出错误类型到系统日志，便于区分配置拒绝与 UI 失败。原生首启、语言、重启及真实声音仍以重新构建后的实际结果验收。

## 当前授权与顺序

1. 核对并验证 Hermes CLI、DeepSeek Harness 桌面端及 MiniMaxCode 桌面端的真实加载、任务状态、完成提醒、确切会话和前台。
2. MiniMaxCode 桌面验证通过后，接入并验证 MiniMaxCode CLI，启动命令为 `mcode`。两者只被动接入用户已有会话；不引入任务发起、exec 会话托管或 ACP 代理。
3. 将已定版的第六版效果接入原生应用首次引导；用户后续明确改为默认全屏强制完整播放，移除审阅按钮与角落说明，不可手动暂停、跳过或取消。保留系统减少动态和已有声音偏好，以及设置中的显式重播。首次进入后记录展示状态，第二次及以后启动不自动重播。系统默认中文/英文对应正确介绍与素材，已有手动语言优先。
4. 四来源真实验证后整体构建本地 v0.1.1 验收应用，验证首启/再次启动、双语、三类 MP3 真实事件及必要原有导航回归，再给用户看实际应用效果。编译、合成任务或插件单元测试不能代替真实来源验证。

可并行推进来源适配与原生引导代码，各自独立 worktree 和文件所有权；UI 操作、真实任务提交、来源配置修改与最终证据汇总由主 Agent 连续处理。使用用户指定的 gpt-6.1-sol / high 子 Agent。

## 验证约束

优先使用可丢弃专用任务、隔离 profile 和独立 bridge；真实 profile 必要变更仅针对 AIsland 接入并备份，保留原条目。不读取凭证或无关任务正文，不覆盖已安装 AIsland、不同时占用生产 bridge。认证、来源授权或确切导航缺口应据实记录并请求所需用户操作；不把应用激活或工具进程存在当作正确会话和完成状态。

首启与持久化使用独立偏好域或注入 store 检查，不能清空用户生产偏好。按最新强制播放契约验证早期 Esc/Cmd-W/Cmd-Q 被拒绝、自然完成进入设置、再次启动不重播；显式设置重播单独验证可关闭。已有用户升级迁移不重播。两种系统语言采用独立验收域设置进行验收，不修改 macOS 全局语言。

## 完成判据

每个来源分别给出真实验证结果与缺口；引导提供原生首启和再次启动的实际窗口/持久化证据。只有通过四来源及应用检查后才报告整体验收包可审阅；不自动发布、推送、公证或接手 v0.1.0 发布。

## 实际进度（四来源 gate 未全部通过）

Hermes CLI 的隔离真实任务已成功，DeepSeek Harness Desktop 已验证真实成功与中止；
DeepSeek exact ID 导航 RPC 实际返回 dispatched，并通过来源 UI 确认对应会话已选中及
完成内容已显示。MiniMaxCode Desktop 已验证真实成功与中止，CLI 普通 mcode 当前
因未登录而未能开始真实任务，等待用户选择账号区域/登录。三者的 native AIsland
通知、最终 App 点击导航与声音还不能只凭 bridge/source UI 报告通过。

原生 V6 引导、首次 claim/持久化、系统语言解析、独立验收构建基础设施已实现；
Core 与 App 目标构建及相关隔离检查已通过。已准备完整验收包的 plan-only 输出，
但尚未执行 --build、安装或启动整体 App；按用户顺序等待四来源实测 gate。独立
验收 App 的偏好、socket、registry、上传声音文件与回执均不使用生产路径。

### 后续用户指令：先完成桌面，CLI 暂缓

用户明确暂不处理 mcode，先接通 MiniMaxCode 桌面。当前构建门槛因此调整为
Hermes CLI、DeepSeek Harness Desktop、MiniMaxCode Desktop 的真实基础 flow；CLI
登录和真实验收延期，不能报告四来源已全部通过。已恢复 desktop-only owned plugin
配置并退出本轮 CLI。按当前三个来源的真实结果继续 native 交互、整体构建和首次
欢迎/双语/声音验收；CLI 留在后续清单，原先豆包/千问范围同样尚未验收。

## 完整原生应用当前实测

完整验收包已实际构建、严格签名并运行。首启/自然结束进入 Setup/第二次不重播、
中英文与多行排版、强制播放和 Watch 隐藏的现状见
`v0.1.1-native-mandatory-playback.md`。不是仅 plan-only 或 offscreen 验证。
R7 浏览器修订已准备并通过实际全屏复测，仍等用户效果确认后才能同步 Native。

实际导入一个 7.027 秒 MP3，保存到独立验收域的管理目录。MiniMaxCode Desktop
真实新回合在 build 7 和 8 完成后，App 的声音回执均记录 `customAudioPlaying:true`；
build 8 对应 session `mvs_e19c9779a18d4ba4906281649f41034e`、turn
`a4b60ce5-3938-46ad-b8c4-f010c87a37fc`，来源 UI 回复
`AISLAND-MINIMAXCODE-NAV-OK`。Desktop 插件允许来源仍为 desktop-only。

Build 11 对保留的隔离 Hermes profile 执行一个真实普通 CLI 回合；回复
`AISLAND-HERMES-OK`、退出 0、session `20261004_023410_d995ce`，App 收到
`turnCompleted/text_response` 并启动同一自定义 MP3。没有新增授权、切换模型或
读取额外凭证。CLI 仍只验证 PTY，原 GUI 终端 pane 与前台尚未验证。

DeepSeek Harness Desktop 重新加载官方插件到独立 App socket；在已有专用验收
会话中发送仅回复标记、禁止工具/文件访问的测试，实际完成 session
`session-b9ae59e0-4236-43b6-b785-9b84e00c6a5f`、turn `3`、sequence `46`。
完整 App 收到 `turnCompleted/completed`、显示 DeepSeek 完成卡并启动同一 MP3。
桥接终态和真实 AVAudioPlayer 播放证明完成声音流程，不证明耳感、审批/回答声音
或点击导航。元数据与声音回执只记录专用任务，保存于 ignored
`output/verification/v0.1.1-live/native-app/real-source-completion-and-mp3.json`。

真实 App 点击确切会话/前台仍待验证，MiniMax 旧 build 7 的实际失败为
`sidebar-conversation-unavailable`。新版控制器已区分 AX 权限不可用与侧栏结构
缺失，不能把 OS entitlement warning 当成权限拒绝。辅助技术的面板/行可操作性
正单独处理；不把 source RPC、当前已选中会话或进程激活冒充 App 点击成功。
审批与回答类别的 MP3 真实事件、既有来源导航回归也尚待验证。

### 原生可访问动作与 DeepSeek 点击复测

`6f65fdb` 给原有闭合 pill 添加独立按钮名称/default action，给会话行添加
保留子按钮的 container/default action；没有改动视觉、鼠标、悬停、窗口穿透或动画。
完整 build 12 的实际 AX 树显示“展开 AIsland 会话”，按该动作可展开列表；会话
容器与原独立 chevron 按钮均可见。实际 MiniMaxCode 行触发导航并记录
`sidebar-conversation-unavailable`，证明新版 permission probe 没有返回权限拒绝。
其现有侧栏 label 读取仍在修复，不能报告准确会话成功。

DeepSeek 来源先选中另一条专用中止会话，再从完整 App 的 DeepSeek 会话行点击，
来源实际改选 `AISLAND-DEEPSEEK-OK 测试` 并加载 `AISLAND-DEEPSEEK-NATIVE-OK`
完成内容。这是实际 App 点击后的选择证据，已经超出单独 RPC dispatch；macOS
前台的独立观测仍待验证，来源窗口截图本身不证明前台。
