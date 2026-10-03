# AIsland v0.1.1 原生第一切片与效果停止节点

日期：2026-10-03。状态：`IMPLEMENTED_EFFECT_ACCEPTANCE_PENDING`。按用户后续选择，首轮推进 Hermes CLI、DeepSeek Harness 桌面端和原生三类 MP3；A 第二版已交给用户播放审阅，原生引导等待反馈。

## 当前交付与验收状态

| 需求 | 当前可检查结果 | 当前效果节点 |
| --- | --- | --- |
| 安装引导 | [A 第二版](aisland-v0.1.1-intro-revision-2.md)：28 秒连续场景、开场共鸣落点、具体任务内容、明暗背景衔接；本机预览可完整播放 | `PENDING`：已向用户请求音画效果反馈，未继续原生移植 |
| 自定义声音 | [原生实现](v0.1.1-custom-sounds-implementation.md)：三类别、本地托管、迁移、回退、单播放器、完整试听/自动时长；已接真实事件入口及全局静音/退出收束 | `PENDING`：原生导入、真实三类事件播放、文件移动与重启效果待真人验收 |
| Hermes / DeepSeek | [原生接收与导航](v0.1.1-hermes-implementation.md)、[DS 插件](v0.1.1-deepseek-implementation.md)：namespace/turn 归属、显式结果、恢复去重、受管理安装、确切 ID 导航派发 | `PENDING`：真实来源加载、hook 授权、并行状态、正确会话和应用前台待真人验收 |
| mcode 比较 | [版本与路线比较](../../references/aisland-v0.1.1-mcode-comparison.md) | 静态比较完成；不自动替换桌面范围或新增正式来源 |

原五来源目标不变。MiniMax 桌面、豆包工作与千问办公没有被宣称完成接入。审批/回答只有在来源确有回传后才能展示操作；Hermes 和 DeepSeek 本轮均未开放原生人工回传按钮。

## 整合与独立审阅修正

- 三类声音按通知目标 session 的当前状态匹配，不能使用尚未切换的旧面板会话；失败、中断和退出不选择成功声音。
- 全局静音变化和应用退出停止播放。静音自动事件不打断允许的主动试听。自定义声音启动失败或 MP3 运行时解码失败最多尝试一次 Bottle，取消代次与播放器身份抑制旧回调；回退沿用原自动截止时间。
- DeepSeek 插件重载后未观察 start 的结束以 source_observed_start:false 同步，收拢原生状态且不补响。来源结果白名单与实际插件投影逐项对齐。
- companion 的 completion schema 会展示成功标记和触感，因此原生失败、中断、sessionEnded 和静默恢复在投影前过滤，不能遗失结果后当成功推送。
- Hermes profile/Python 选择在异步处理期间禁用，防旧 profile 的安装状态写回新选择。
- DeepSeek 导航连接、发送和接收共享截止时间；派发回执不冒充已选中。测试 bridge 只使用独立 socket，生产/legacy socket 不被测试接管。

## 整合验证

- `swift build`：整合后所有当前产品编译通过；没有运行应用。
- **53 项、9 suites 隔离 Swift Testing 通过**：在临时 package 复制当前 Core 源码、最小 IslandSurface 目标及相关测试，检查来源结果、实际独立 Unix bridge、Hermes 临时 YAML 配置、导航回执与截止、声音生命周期、事件类别和 companion 过滤。
- 53 项中包含一次跨组件检查：由真实 JS LifecycleProjection 生成合成 NDJSON，交给当前 Swift BridgeCodec/RuntimeLifecycleReducer/SessionState，核对正常成功、失败及插件重建后静默结束。这里的数据为构造任务，不是 Harness 真实任务。
- DS 插件 **22 项 Node 确定性检查**通过；配置安装脚本仅 dry-run。
- 前述各独立 worktree 的相关 Core/App 检查及声音专项记录保留在对应实施文档。常规全量测试入口仍受现有 CLT Testing overlay / Test.cancel 缺口影响，不能宣称全套测试通过；没有修改机器工具链或仓库测试配置来掩盖失败。
- 文档与 Git 差异检查通过；预览的浏览器验证见第二版记录。

本地整合日志保留在 `output/verification/v0.1.1-native-check.log` 和 `v0.1.1-app-build.log`；临时测试 package、合成文件及只读研究工作树收尾清理。生产偏好、用户 MP3、第三方 profile、已安装 AIsland 和公证发布线均未被本轮操作修改。

## 下一真实效果节点

使用单一 AIsland bridge、独立来源 profile 和可丢弃测试目录，分别检查成功、失败、取消、两任务并行、重复标题、来源与 AIsland 的退出恢复。每次跳转同时核对正确会话/pane 与应用前台；不能以派发或唤起代替。声音用三份独立 MP3 检查完成/审批/回答、静音与完整试听、连续打断、原文件移动和重启恢复。

本轮还没有安装或运行第三方接入，没有付费真实任务。应先交付这些真实效果给用户确认，再进入该需求后续范围。A 第二版仍等待用户反馈，时间经过、编译成功和隔离检查都不替代用户认可。
