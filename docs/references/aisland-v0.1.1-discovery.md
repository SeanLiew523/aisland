# AIsland v0.1.1 接入与视听引导调研记录

采集日期：2026-10-03（北京时间）。状态：`STATIC_DISCOVERY_AND_PROTOTYPE_REVIEW_PENDING`。本记录区分本机静态资源、公开资料、实际画面、设计推导和待验证行为；不代表新工具已接入或 Dia 视听调研已完成。用户已确认总体计划并允许扩展相关调研；本轮补齐静态能力与跨案例视听设计研究，交付独立原型供实际试听。范围见 [执行计划](../exec-plans/active/aisland-v0.1.1-requirements.md)，停止节点见 [阶段 1 记录](../exec-plans/active/aisland-v0.1.1-stage-1.md)。

## 1. 新工具的本机身份与证据

只读检查应用 `Info.plist` 和已安装程序资源，未读取用户会话正文、登录凭证或修改第三方配置。

| 来源 | 当前检查对象 | 已观察事实 | 仍需验证 |
| --- | --- | --- | --- |
| Hermes CLI | `/Users/seanliew/.hermes/hermes-agent`，源码提交 `0ff4c74865` | 本机 `agent/shell_hooks.py` 提供 `hook_event_name`、`session_id`、`cwd`、`tool_input`；CLI 注册 shell hooks；存在 `pre_llm_call`、`post_llm_call`、会话和工具事件 | 真实 CLI/TUI 事件、恢复与中断、终端定位、审批/问答回传能力 |
| MiniMax Code 桌面 | `com.minimax.agent`，3.1.0 / 3.1.0.176 | 有 `minimax` URL 协议和本地运行时；程序包包含 deep-link 解析模块 | 外部事件/扩展入口；任务级跳转。`minimax://chat?message=...` 带发送消息语义，不能用来做只读跳转探针 |
| DeepSeek Harness 桌面 | `com.deepseek.dsh`，0.2.0-rc.2 | 官方桌面包；注册 `dsh` 协议；当前主程序的 `open-url` 处理只观察到 `dsh://open` 的窗口聚焦 | 真实任务事件/存储契约；通过其他接口或 Accessibility 精确选择任务；审批/问答能力 |
| 豆包工作 | `com.work.pc.doubao`，2.31.8 | 本机 `DoubaoWork.app`，注册 `doubaowork` 协议 | 协议的任务参数、外部扩展和真实任务状态来源；不是把一般豆包聊天当作办公任务 |
| 千问办公 | `cn.qwenwork.desktop.mac`，1.0.5 / 26090806 | 本机 `QwenWorkCN.app`，注册 `qwenwork-cn`；内部主程序有会话、任务和工具 hook 代码 | 内部 hook 是否有可配置外部入口；任务事件、回传和跳转。不与 Qwen Code 的配置或身份混用 |

协议注册、源代码中出现 `hooks` 或 `PermissionRequest` 字符串均不能直接证明外部支持。例如 Electron 的浏览器权限处理与 agent 工具审批属于不同概念。尚未对这些来源执行真实任务，也未运行会发送消息的深链接。

Hermes 当前官方文档明确区分 gateway、plugin、shell 等路径；CLI 适配优先核对本机 shell/plugin 的版本契约，不能选用只在 gateway 生效的事件。[Hermes 官方 Event Hooks 文档](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks/)

DeepSeek 官方下载页列出 Harness 桌面端；公开搜索同时存在多个第三方桌面包装，本轮以用户本机官方包的身份为对象。[DeepSeek 官方下载](https://www.deepseek.com/en/download/)

## 2. AIsland 现有实现

- `NotificationSoundService.swift` 列举 `/System/Library/Sounds` 的系统音效，通过 `NSSound(named:)` 播放，持久化一个 `notification.sound.name`。
- `SoundSettingsPane` 点击系统声音时选择并试听；没有导入 MP3 或按事件分组。
- `OverlayUICoordinator.presentNotificationSurface` 统一触发通知声音，目前没有传入任务完成、审批、回答类别。
- `AppModel.showOnboarding()` 打开设置并跳到接入页，尚无独立全屏引导。
- `AgentIntentStore` 已有首次启动完成标记和旧用户迁移；不能忽略这些状态另起重复引导。
- overlay 目前在悬停展开时按用户设置调用 `NSHapticFeedbackManager`，并非完整引导触感设计。

## 3. Dia 公开实际画面

实际打开并检查 [Andreas Storm 发布的 Dia onboarding 录屏](https://x.com/avstorm/status/1932800037081247788)。帖子日期为 2025-06-11，播放器时长约 23.43 秒。通过播放器定位观察 0、5、10、15、20 秒及结尾关键画面：

- 开始为蓝黄亮色桌面氛围；早段转为深色背景和简短品牌文字。
- 约五秒出现亮色球形图形。
- 约十秒可见悬浮输入和消息形态；图形持续变为产品交互，而非不断切换说明页。
- 随后演示把两个浏览器标签加入比较输入。
- 后段演示页面内容与替换交互；该短片本身没有覆盖完整安装配置流程。

这些是画面观察，不是音色或真实触感证据。该录屏与下面本机 2026 年版本的声音文件尚未对齐，不能逐秒强行匹配。

The Browser Company 的设计说明强调熟悉的日常界面，并在体现新能力的动作中用动画和颜色表达品牌。这支持 AIsland 将品牌开场收束到日常刘海和实际操作的设计方向；具体分镜仍是 AIsland 的推导。[The strategy behind Dia's design](https://browsercompany.substack.com/p/the-strategy-behind-dias-design)

官网安装说明覆盖账号、可选导入和开始 Chat，不提供上述开场的音轨与震感时序，不能仅据文字完成视听调研。[Dia 安装说明](https://www.diabrowser.com/download/thanks)

## 4. Dia 本机声音资源与强弱分析

检查对象为 `/Applications/Dia.app`，Bundle ID `company.thebrowser.dia`，版本 1.51.0 / 构建 88065。

资源位置：

```text
/Applications/Dia.app/Contents/Resources/BoostBrowser_Onboarding.bundle/Contents/Resources/SoundEffects/
/Applications/Dia.app/Contents/Resources/BoostBrowser_BoostSoundEffects.bundle/Contents/Resources/
```

`Onboarding.bundle` 有单独的欢迎音。`BoostSoundEffects.bundle` 中观察到以下文件，时长来自音频元数据：

| 素材 | 时长 | 编码与声道 |
| --- | --- | --- |
| `onboarding_intro_music.m4a` | 34.806712 秒 | AAC，44.1 kHz，双声道 |
| `welcome.m4a` | 1.880816 秒 | AAC，44.1 kHz，双声道 |
| `click1`–`click4.m4a` | 约 0.186–0.279 秒 | AAC，44.1 kHz，单声道 |
| `pop.m4a` | 0.139320 秒 | AAC，44.1 kHz，单声道 |
| `shimmer.m4a` | 1.695057 秒 | AAC，44.1 kHz，双声道 |

开场音乐 SHA256：`c77ef9a7ac197b24d7dbb94ac7111e161aceb092c903faa815baa4cd7c7643a4`。没有将 Dia 的音频素材复制进仓库。

将开场音乐临时解码为单声道 PCM，按 250 ms 窗口计算 RMS 强弱，观察到：

- 0–1 秒平均约 -41 dBFS，1–2 秒约 -21 dBFS，存在起音变化。
- 约 3–8 秒维持较强声音能量，最大窗口出现在约 5.75 秒。
- 约 10–12 秒减弱；约 12–14 秒又有能量变化。
- 约 14 秒后显著减弱，后段有很长的低强度尾部，末段接近无声。

因此文件长度不等于强声音持续时间。上述数值只能描述强弱和包络，不能证明它是什么音色、哪个转场使用哪段，或主观听感是否高级。转换后 PCM 的有效长度与压缩容器长度略有不同，也不应用于未经校准的逐帧同步结论。

## 5. 触感的实际边界

Apple 的 `NSHapticFeedbackManager` 用于带 Force Touch 触控板的系统，默认 performer 取决于输入设备、无障碍设置和用户偏好。屏幕图形的轻震动与用户触控板的真实触感需分别记录；视频不能证明后者。[Apple NSHapticFeedbackManager 文档](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)

本轮没有更改 Dia 的账号、配置或首次启动状态，没有重跑其引导，亦没有声称已体验物理触感。

## 6. 研究缺口与下一步

当前工具可以读取音轨元数据、分析波形和播放公开视频，但模型端返回“音频输入不受支持”，所以没有完成直接听辨。公开视频保存尝试超时，没有获得可用于声画联合分析的本地录屏。不得把本轮写成完整试听或充分调研完成。

后续需要在同一来源/版本的带声音演示中记录：每一步的视觉起止、音效起点/主落点/尾音、音乐与交互音的关系、触感时机、跳过和中断时的行为。听感与真实触感最终通过用户可播放、可操作的预览验收；代码调用成功或素材存在不能替代体验结果。

对 AIsland 的设计建议是共同编排画面、音乐底层、转场音、交互音和触感，提供分步骤 cue 表及完整联动预览。该建议是设计推导，不是对 Dia 原始时间轴的复刻结论。

## 7. 进一步来源能力核验

本轮由用户指定的 `gpt-6.1-sol` / `high` 子 Agent 分两路只读研究，主 Agent 复核 Hermes 结束/授权源码、MiniMax 插件文档与结果 schema、DeepSeek `openSession` 和千问通知 URL 构造。没有读取真实会话数据库、正文或凭证，没有执行第三方配置安装。下列路径相对各应用的 `Contents/Resources/app.asar`；行号为包条目的文本行，压缩条目用字符偏移定位，版本变化后需重新核对。

| 来源 | 可实施的静态入口 | 关键缺口与结果判据 |
| --- | --- | --- |
| Hermes CLI | profile `config.yaml` 的 shell hooks；`pre_llm_call` 与 `on_session_end`；session/task/turn 身份 | 终端 pane/窗口身份需补采；审批 observer 不接纳回答，内部 TUI RPC 不等于普通 CLI 外部 API。完成必须使用显式结果字段，不能只用 `post_llm_call` |
| MiniMax Code | 本地 `.minimax-plugin/plugin.json` 的 hooks，扫描本地 plugins 目录；session/turn/tool-use 身份 | `Stop` 后其他 hook 可能继续运行；完成需校准最终提交。内部结果表可作为只读元数据候选，尚未读取实测；deep-link 只证明窗口聚焦；同步审批最多 10 秒，不能承诺长时间人工回传 |
| DeepSeek Harness | 官方桌面独立 Cordis profile；插件 `session/event`、`agent/status`、审批与问答能力；客户端 `uiWorkspace.openSession` | 需要做 server 插件到客户端导航的可卸载桥接；`idle` 不必然成功完成，需 `turn/end(reason)`；`dsh://open` 本身仍只是聚焦 |
| 千问办公 | 内部真实 task/stream 状态及带 `chatId/subChatId` 的通知导航；官方企业 HTTP hooks | 当前用户有效 profile 是否可用企业入口未知；hook session ID 到桌面 ID 映射待测。`Stop` 可被阻止继续，不是最终完成；未证实外部对已有审批/问题回传 |
| 豆包工作 | 本机资源有办公异步状态与会话 ID 模型 | 未找到可配置外部事件订阅或带会话 ID 的准确导航契约；不能拿内部字符串或进程存在当接入路线 |

### Hermes

- 本机源码仍为 `0ff4c748658ff5b92661fa2b453fcf8ed813414d`。`agent/turn_finalizer.py:572–577` 计算成功完成需有最终响应、非失败、非中断；`:770–782` 的 `on_session_end` 转发 `completed/failed/interrupted/turn_exit_reason`、session/task/turn ID。CLI 每条消息执行一次回合，此事件名不表示用户彻底退出终端。
- `hermes_cli/cli_shutdown.py:183–190` 中断补发可能缺少 task/turn，须谨慎匹配当前 session；`post_llm_call` 在普通中断时通常不发，但缺少结果字段，失败说明也可能发，不能作为成功完成判据。
- `agent/shell_hooks.py:141–175` 注册需要来源自己的 consent；授权写入 profile 的 `shell-hooks-allowlist.json`，非 TTY 未授权会跳过。安装引导应展示真实待授权状态，不全局开启 `hooks_auto_accept`。
- shell payload 包含 `tool_input` 等不需要的数据，适配器只留下身份/状态/终端元数据。`action:approve` 是进入人工审批，不是批准。TUI 的 `approval.respond/request.answer` 属私有 socketpair，普通外部连接尚未成立。

公开文档将 Gateway-only `HOOK.yaml` 与 CLI/TUI shell 路线区分，需使用正确系统。[Hermes 官方 Event Hooks](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks/)

### MiniMax Code

- `node_modules/@mavis/local-runtime-v2/assets/skills/plugin-creator/references/local-plugin-hooks.md` 声明本地 plugin hooks 入口与 `UserPromptSubmit/PreToolUse/PermissionRequest/PostToolUse/Stop` 等事件；`dist/service/plugin-system/plugin/package/minimax-reader.js:76–90` 和 `plugin/runtime/local-directory-watcher.js:25–63` 提供 loader 与扫描实现。
- `dist/service/turn-system/agent-host/execution/user-input-control.js:167–199` 在 Stop handler 后可能追加 `continuePrompt`；`dist/infra/db/schema/turn.js:10–28` 的 `local_runtime_turn_ingress` 才有 `accepted/completed/failed/aborted` 最终状态字段。仅查询这些身份、状态、时间字段是候选路线，不代表已按真实数据库验证。
- `dist/main/modules/local-runtime/data-dir.js:150–179` 表明 dataDir 可变，不能硬编码 `~/.minimax`。HTTP diagnostic sidecar 默认不是普通外部 API，不为了接入擅自改启动环境。
- `dist/main/modules/deeplink/index.js:114–135` 只确认 restore/focus 与 renderer 广播；renderer 唯一观察到的 deep-link listener 处理 `navigate` 支付回跳。没有发现 session 选择契约，不能猜 `minimax://open?session_id=...` 已有效。
- `@mavis/plugin-hooks/dist/parser.js:2–3` 约束 hook 默认 5 秒、最长 10 秒；HTTP permission/questionnaire controller 名称存在，但当前实现抛 `NotImplementedError`，不能据此展示可回传按钮。

### DeepSeek Harness

- 随包 `runtime/cli/bin/dsh` 与官方桌面 README 说明桌面有独立 profile，可使用随包 CLI 管理插件，需要先退出桌面应用；本轮未执行。[DeepSeek 官方桌面文档](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.md)
- `dsh/node_modules/@deepseek-ai/dsh-session/lib/index.js` 约 69457 发布 `session/event`；agent-loop 约 33642/35988 写入 `turn/start` / `turn/end`，身份、turn、seq 可用于归属与去重，不转发正文。
- `dsh-client-ui-workspace/lib/client.js` 约 34009 的 `openSession(target)` 调用 `replaceMain(...,"reveal")`；这是客户端插件能力，需要外部桥接与实际验证。`lib/main.js` 的 `dsh://open` 处理仍仅聚焦。
- `dsh-user-approval/lib/index.js` 约 7767 通过 `approval/request` waterfall 回传决定并响应取消；`userQuestions` 有活跃问题路径。需要验证取消、请求归属和与现有 UI 协同。

### 千问办公与豆包工作

- 千问 `out/main/main.js` 约 3790722 的 `notification-click` 读取 chatId/subChatId/requestId，bringToFront 后发 `notification:clicked`；renderer `out/renderer/assets/index-Dg59jxtt.js` 约 3406810 按 ID 选择会话。主 Agent 复核了包内构造的 `qwenwork-cn://notification-click?...`。这是只导航候选，仍需真实任务 ID 与准确选中验收。
- 内部 stream/task 模型区分 running/completed/failed/cancelled/interrupted；baseline profile 不注入企业 hooks。官方说明企业 HTTP POST 的六类 hook，并在企业旗舰版管理规则；账号能力需当前核对。[千问桌面 Hooks](https://docs.qwenwork.cn/desktop/hooks)、[企业 Hooks 规则](https://docs.qwenwork.cn/enterprise-ultimate/security/hooks-rules)
- 豆包 `DoubaoWork Browser Framework.framework/Versions/147.0.7727.149/Resources/local_webcontents/` 下 `extensions/ai-views/static/js/side_panel.js` 约 32731 有办公任务状态枚举；`apps/entry-main/main.js` 出现 conversation/thread 身份。已找到的 `doubaowork://doubaowork-settings` 是设置入口，不是准确会话导航。

建议先做 Hermes 与 DeepSeek 的完整来源切片；其余三来源补缺口，不降低五来源验收目标。专用真实任务要覆盖并行、成功、失败、中断、恢复和重复标题，分别记录会话选择与前台；本轮尚未执行。

## 8. 扩展视听案例与平台限制

| 一手案例 | 可核实的事实 | AIsland 设计推导 |
| --- | --- | --- |
| Google / Pixel 6 欢迎动画 | 设计师说明两形碰撞用低频、随时间变化的 THUD 触感模拟橡胶球与软膜；明确有意使用静默。子 Agent 观察官方内嵌视频两帧的形体与波形变化，未听辨 | 统一形体的材质感；聚拢落位一次反馈，运行与持续漂移保持安静。Pixel 马达曲线不移植为 macOS 承诺 |
| Apple WWDC18 流畅界面 | 建议先用没有过冲的阻尼，再根据手势目的添加弹性；音画与触感需保持同一性格 | 连续变形与稳定收束，少量有目的的压缩；配置页保持克制，可立即打断 |
| Microsoft 音频设计 | 鼓励设计师在早期 demo 和原型中尝试声音，并用声音库保持同一家族 | 同一画面和落点对比 A/B 音色，让用户实际听后选；声音不是最后补上的素材 |
| Dia 设计说明 | 新能力的动作承担创新表达，日常界面保持熟悉 | 将开场收束为日常刘海，再进入简洁配置；不是品牌影片结束后重新开说明页 |

来源：[Google Sound & Touch](https://design.google/library/ux-sound-haptic-material-design)、[Apple Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)、[Microsoft 音频设计访谈](https://microsoft.design/articles/the-sound-of-innovation-how-audio-designers-are-redefining-digital-experiences/)、[Dia 设计说明](https://browsercompany.substack.com/p/the-strategy-behind-dias-design)。这些支持原则和推导，不表示本轮已经直接听辨上述音轨。

**触感修正。** 主 Agent 复核 Apple 官方文档数据：`NSHapticFeedbackPerformer.perform` 只应响应用户发起的操作；未触碰 Force Touch 触控板时可能不反馈。macOS 提供 generic/alignment/levelChange 等语义，HIG 将其用于合适的拖动或 Force Click 响应；不能用 iPhone 的 success/error 或 Pixel 自定义 THUD 替代。自动开场、自动完成状态和自动收拢均不安排真实触感；后续原生阶段在合适的真实用户操作上试验，记录设备、输入方式和体验结果。[Apple 调用条件](https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:))、[Apple HIG 触感](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

## 9. 首次交付的原创音画原型与 cue 表（历史版本）

原型见 [阶段记录](../exec-plans/active/aisland-v0.1.1-stage-1.md)。下表是首次交付参数，属于设计草样；不是 Dia 时序，也不是已经通过听感验收的制作标准。用户选 A 后已修订为 28 秒第二版，当前 cue 见[修订记录](../exec-plans/active/aisland-v0.1.1-intro-revision-2.md)。网页不产生真实触感。减少动态效果使用固定构图和状态切换。

| 时间 | 画面 | 音效起点 / 目标 | 最晚尾音约 |
| --- | --- | --- | --- |
| 0–3 秒 | 从小形体展开为 Bloub / 平顶刘海 | 0.4 秒低强度底层；1.65 秒三音品牌动机 | 约 2.7 秒；底层约 3.7 秒 |
| 3–8 秒 | 三张有身份的任务卡汇入 | 3.7 秒短移动纹理；6.4 秒一次低中频落位；running 无循环音 | 移动约 4.5 秒，落位约 6.8 秒；底层约 7.9 秒 |
| 8–11.8 秒 | 示例任务 A 运行后完成 | 9.4 秒两音上行完成标记 | A 约 10.2 秒 / B 约 9.9 秒 |
| 11.8–14.2 秒 | 示例任务 B 粉色等待审批 | 11.8 秒同音短双击 | A 约 12.5 秒 / B 约 12.3 秒 |
| 14.2–16.2 秒 | 示例任务 C 黄色等待回答 | 14.2 秒上扬回答标记 | A 约 15 秒 / B 约 14.7 秒 |
| 16.2–18 秒 | 返回任务 B 的示意会话窗口 | 16.2 秒轻确认 | 约 16.4 秒 |
| 18–22 秒 | 收回顶部，进入简洁工具选择 | 18 秒移动纹理；20.5 秒品牌收束 | A 约 21.7 秒 / B 约 21.2 秒 |

A「温润共鸣」用正弦、低中频底层与空气纹理，B「清脆数字」用三角波与较短包络；两者采用相同主要事件落点。名称描述合成意图，不能代替主观听感。用户可比较完整开场与三类样音，反馈节奏、可辨识度及是否愿意继续设置。后续调整仍先视听对齐，再接入原生；跳过、静音、切换、重播和退出必须取消过期声音。

## 10. mcode 补充比较

按用户后续要求补充 [mcode 与桌面比较](aisland-v0.1.1-mcode-comparison.md)。本机 0.5.3 exec 有明确最终结果，ACP 有客户端持有会话的双向交互；被动观察已有 TUI 的 Stop 与终端身份缺口仍类似桌面。研究不替换桌面范围，也不自动增加第六个正式来源。Hermes 和 DeepSeek 保持第一实施顺序。
