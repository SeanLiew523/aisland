# MiniMax Code CLI（mcode）与桌面接入比较

日期：2026-10-03。状态：`STATIC_COMPARISON_COMPLETE_RUNTIME_PENDING`。这是用户要求的补充研究，不自动把 mcode 作为第六个正式来源，也不替换原 MiniMax Code 桌面需求。

结论：AIsland 若启动并持有 mcode 的 exec / ACP 会话，CLI 的结构化结果与回传契约更友好；若只被动观察用户已经打开的 TUI，接入难度与桌面接近。CLI 不天然解决原终端定位。

## 本机版本与证据

本机入口为 `/Users/seanliew/.minimax-code/bin/mcode`，安装包 `/Users/seanliew/.minimax-code/lib/node_modules/@minimax-ai/code` 的 `package.json` 为 0.5.3，包含 mcode / mcode-tools。研究只读安装包、公开 registry 与官方源码，未安装、升级、运行真实任务、读取会话正文或凭证。launcher 在解析帮助前创建 `.mcode-active` marker，因此本轮也未执行 `--help/--version`；启动可达性尚未验证。

官方源码固定到 `564e9166d81f87b0b767b005e4779d4697b512be`。本机包为本轮结论的具体基线；官方较新源码不能直接作为本机字段契约。

## 能力比较

| 能力 | mcode 0.5.3 证据与限制 | 相较桌面 |
| --- | --- | --- |
| 恢复指定会话 | `--session <id>`、`--continue` 有明确入口；启动另一 CLI 不等于选中原来运行的 pane | 更友好，但准确跳转未完成 |
| 真实最终结果 | exec 的 schemaVersion 1 `exec.result` 带 runId/sessionId/turnId；结果 succeeded/failed/timeout/cancelled/limit_exceeded；stream-json 有 turn.completed/turn.failed/exec.completed | exec 更友好 |
| 审批回传 | ACP `session.requestPermission` → replyPermission，含 allowOnce/allowAlways/deny 和过期/取消 attachment 检查 | 客户端持有的 ACP 更友好 |
| 问答回传 | ACP `elicitation.create` → replyQuestionnaire；无表单能力时只有部分单选问题可降级为权限请求 | 客户端持有的 ACP 更友好 |
| exec 人工交互 | `--permission ask` 被拒绝；待审批/问答会话要求 TUI 或 ACP | 不提供 exec 人工回传 |
| 被动 TUI hooks | 与桌面同类 hooks，默认 5 秒、最多 10 秒；Stop 的 continuePrompt 可以续跑 | 基本相同，Stop 不是最终成功 |
| 终端归属 | hook env 白名单无 ITERM_SESSION_ID/TMUX_PANE；子进程 stdio pipe、detached，hook 中 tty 得不到原 TUI | 需要启动包装器提前登记 |
| 附着已有 TUI/桌面 | 尚无稳定外部契约证明 ACP 可附着另一运行进程并代它回传 | 不承诺附着能力 |
| 插件管理 | `/plugins` 与 `mcode plugin` 可显式管理当前 profile 的 official/local 包；任意 local path 导入不成立 | 略更友好，但同类 runtime 限制仍在 |

不把 stdout 文本、进程结束或 idle 判为成功。exec 的正式结果表示该回合按运行时语义结束，不代表用户目标经过独立验收。ACP 路线要求 AIsland 成为会话客户端，属于新的会话托管设计，需要另行明确产品范围。

## 可复查本机定位

以下为安装包内 bundle 名和文本字符偏移，不是假定可读源码行号：

- `chunks/main-IOILPBAK.js`：约 35889 为 --session，40376 为 exec/ACP，36800 附近为 exec 参数与 ask 限制。
- `chunks/run-exec-command-GLUQCUHC.js`：约 4276 为结果结构，5411 为五类最终状态，17368 为 terminal stream events，18236 为 sequence 和身份字段，33938 为待交互会话拒绝 exec。
- `chunks/run-acp-command-WKIY3JS6.js`：约 410865 为权限请求，411281 为问答，433139 附近为 prompt/cancel。
- `chunks/chunk-VORQSP3A.js`：约 6767483 为 hook 事件与时间限制，6811414 为 hook 身份/cwd，6813152 为安全 env，7835468 为 Stop 续跑，8313290 为内部 ingress 状态表。
- `chunks/launcher-EJDM3IIM.js`：约 864443 为本机 [V] 状态行；`chunks/chunk-ZZOIWHZG.js` 的 re() 创建 active marker。

本机 0.5.3 [V] 状态行使用 session/turn 字符串、request 短哈希，没有 background；官方固定提交的文档改为 opaque refs 并增加 background。正式适配必须按版本校准，不能照较新文档解析本机。

## 下一验证及范围决定

目前优先 Hermes CLI 与 DeepSeek Harness 桌面，MiniMax 桌面保留原五来源范围。本研究推荐先留作后续决策：若接受 AIsland 启动并持有会话，可验证 mcode exec/ACP；若坚持被动接入已开会话，则继续补桌面/TUI 的最终状态、身份与导航缺口。

最小真实验证使用独立 MINIMAX_DATA_DIR 和合成目录、两个重复标题会话。启动包装器先采终端身份再按 session 关联；检查成功、失败、超时、中断、Stop 继续、退出恢复及断流。ACP 若进入研究，应另测 allow/deny、问题回答、取消后迟到回传、断连与重载。跳转分别核对正确 pane/session 和应用前台。上述均尚未执行。

一手来源：[官方架构](https://github.com/MiniMax-AI/minimax-code/blob/564e9166d81f87b0b767b005e4779d4697b512be/docs/architecture.md)、[exec 契约](https://github.com/MiniMax-AI/minimax-code/blob/564e9166d81f87b0b767b005e4779d4697b512be/packages/tui/src/headless/contract.ts)、[ACP 交互](https://github.com/MiniMax-AI/minimax-code/blob/564e9166d81f87b0b767b005e4779d4697b512be/packages/tui/src/acp/interactions.ts)、[状态行](https://github.com/MiniMax-AI/minimax-code/blob/564e9166d81f87b0b767b005e4779d4697b512be/packages/tui/docs/status-line-config.md)、[插件管理](https://github.com/MiniMax-AI/minimax-code/blob/564e9166d81f87b0b767b005e4779d4697b512be/docs/examples.md#4-manage-plugins)。
