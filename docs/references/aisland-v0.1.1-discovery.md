# AIsland v0.1.1 接入与 Dia 引导调研记录

采集日期：2026-10-03（北京时间）。状态：`PRELIMINARY_RESEARCH`。本记录区分本机静态资源、公开资料、实际画面和待验证行为；不代表新工具已接入或 Dia 视听调研已完成。需求草案见 [执行计划](../exec-plans/active/aisland-v0.1.1-requirements.md)。

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
