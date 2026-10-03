# AIsland v0.1.1 效果审阅原型

独立 HTML / Canvas / Web Audio 原型，用于用户的分阶段效果对齐；不连接正式应用或第三方工具。原生应用继续使用 Swift / AppKit / SwiftUI，不把本原型作为运行时引入。

在仓库根目录启动仅本机可见的预览：

```sh
python3 -m http.server 49161 --bind 127.0.0.1 --directory prototypes/v0.1.1-review
```

打开 `http://127.0.0.1:49161/?revision=2#intro`。用户已选择 A 声音方向，本版只修订 A。点击“播放音画预览”；可全屏、跳过、静音、重播及减少动态效果；点击右侧阶段可静帧检查细节（不播放声音）。首次播放由点击激活浏览器音频。任务声音页支持三类独立导入 MP3、解码验证、完整试听、自动场景提示、替换和恢复默认草样。

## 审阅范围

- 约 28 秒的连续画面与原创合成声音节奏；A「温润共鸣」修订版。深蓝开场、明亮汇入、不同状态的深色场景，再返回工作桌面，均为连续过渡。
- 开场使用低中频蓄势、共鸣落点、左右空气纹理，再留下静默；母线压缩限制叠加峰值。不是整体提高所有音量。三种事件保持相同音色家族。
- 汇入模块有文档、代码和审核内容；回应阶段包含整理后的文件、具体审批修改和问题选项；返回阶段显示同一个页面修改演示任务。
- 示例任务 A 完成、B 等待审批、C 等待回答；不会把同一完成任务接着变成审批或回答。
- 默认声音仅为原创合成试听草样，不冒充 macOS Bottle。正式声音设置保留全部系统声音。
- 自动提示长度可试 5 秒或完整音频；本页提议新提示替换上一条，主动试听不受自动静音或长度限制。等待用户确认后再落实原生策略。
- 文件只在浏览器内存中解码，不上传、不持久化。正式版的受管理本地副本、重启恢复、迁移与系统音回退尚未实现。
- 全屏收束到的是画布内顶部示意，尚未连接真实屏幕刘海；配置页只演示选择，不安装任何工具。
- 不产生真实触控板触感。后续原生触感遵循 macOS 用户操作与硬件条件，单独真人验收。

跳过、重播、静帧检查、离开页面、切换审阅页或关闭页面会取消尚未发生的声音节点；静音可立即停止声音，重新开声需重播，避免播放过期 cue。异步开启音频使用取消代次，防止跳过后残留调度。

## 实现与验证

`intro-scene.js` 只负责示意画面；`review.js` 使用同一音频时钟编排声音和画面；静音时使用单调时间。对完整文件调用 `decodeAudioData`，验证成功后才替换当前类别选择；播放使用可停止的 source 节点。参考 [MDN 解码文档](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData)、[音频恢复](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume)、[节点停止](https://developer.mozilla.org/en-US/docs/Web/API/AudioScheduledSourceNode/stop)。

静态检查：

```sh
node --check prototypes/v0.1.1-review/review.js
node --check prototypes/v0.1.1-review/intro-scene.js
zsh scripts/harness.sh docs
git diff --check
```

浏览器检查与未验证范围见 [阶段 1 记录](../../docs/exec-plans/active/aisland-v0.1.1-stage-1.md)及[引导第二版记录](../../docs/exec-plans/active/aisland-v0.1.1-intro-revision-2.md)。所有视听草样仍需用户实际观看试听，不能把原型可运行或波形存在记为效果通过。
