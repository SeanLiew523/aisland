# 路线图

<strong>中文</strong> | <a href="roadmap.md">English</a>

AIsland 是独立维护、面向社区的 macOS 本地编程 Agent 控制台。路线图优先推进可端到端交付、并能在对应真实 Agent 与桌面运行环境中验证的小步改进。

涉及较大产品范围或架构变化时，请先提交 Issue；边界清楚的修复和集成改进可以直接提交 Pull Request。详见 [CONTRIBUTING.zh-CN.md](../CONTRIBUTING.zh-CN.md)。

## 重点方向

| # | 方向 | 目标 | 状态 |
|---|---|---|---|
| 1 | **ZCode 与 WorkBuddy** | 随产品演进持续保证 Hook 安装、会话身份、存活检测和桌面端精确对话跳回可靠。 | 活跃 |
| 2 | **Claude Code 与 Codex** | 在 CLI 和桌面端保持低噪声生命周期上报、受支持的交互流程、用量可见性和精确返回路径。 | 活跃 |
| 3 | **其他编程 Agent** | 基于真实运行证据持续改进 OpenCode、Gemini CLI、Qoder、Qwen Code、Factory、CodeBuddy、Cursor、Kimi CLI、Grok Build、Pi 和 Oh My Pi。 | 持续 |
| 4 | **终端与 IDE 跳回** | 扩大精确定位覆盖，不用笼统激活应用替代已有的精确路径。 | 持续 |
| 5 | **本地可靠性** | 让 Hook 管理、转录发现、进程检测、辅助功能使用和故障恢复更安静、更可预测。 | 活跃 |
| 6 | **原生体验** | 改进 macOS UI、通知、声音、动画、无障碍和多显示器体验。 | 开放 |
| 7 | **远程会话与新终端形态** | 先增强 SSH 工作流，再以边界清楚的小步评估 Apple Watch、iOS、语音和通知回复。 | 已规划 |
| 8 | **独立发布能力** | 建立 AIsland 自有的签名、公证、Sparkle 身份和可持续发布流程，不继承上游凭据。 | 活跃 |

**状态说明：** `活跃` = 当前维护重点 · `持续` = 已支持并持续迭代 · `已规划` = 已认可方向，但不代表版本承诺 · `开放` = 欢迎提案与贡献

## 边界

- 当前支持 macOS 14+。
- 集成保持本地优先；AIsland 不可用时应 fail open，不阻塞 Agent。
- AIsland 拥有独立版本历史，不自动跟随上游发布。
- 内部 `OpenIsland*` 标识在专门迁移方案出现前继续作为兼容细节保留。

当前支持矩阵见[产品范围](product.md)，上游变更的评估方式见[与上游的关系](upstream.md)。
