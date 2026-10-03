# AIsland v0.1.1 效果审阅原型

独立 HTML / Canvas / Web Audio 原型，用于用户的第一阶段效果对齐；不连接正式应用或第三方工具。原生应用继续使用 Swift / AppKit / SwiftUI，不把本原型作为运行时引入。

在仓库根目录启动仅本机可见的预览：

```sh
python3 -m http.server 49161 --bind 127.0.0.1 --directory prototypes/v0.1.1-review
```

打开 `http://127.0.0.1:49161/`。选择声音方向，点击“播放音画预览”；可全屏、跳过、静音、重播及减少动态效果。首次播放由点击激活浏览器音频。任务声音页支持三类独立导入 MP3、解码验证、完整试听、自动场景提示、替换和恢复默认草样。

## 审阅范围

- 约 22 秒的连续画面与原创合成声音节奏；A「温润共鸣」与 B「清脆数字」共用主要落点。
- 示例任务 A 完成、B 等待审批、C 等待回答；不会把同一完成任务接着变成审批或回答。
- 默认声音仅为原创合成试听草样，不冒充 macOS Bottle。正式声音设置保留全部系统声音。
- 自动提示长度可试 5 秒或完整音频；本页提议新提示替换上一条，主动试听不受自动静音或长度限制。等待用户确认后再落实原生策略。
- 文件只在浏览器内存中解码，不上传、不持久化。正式版的受管理本地副本、重启恢复、迁移与系统音回退尚未实现。
- 全屏收束到的是画布内顶部示意，尚未连接真实屏幕刘海；配置页只演示选择，不安装任何工具。
- 不产生真实触控板触感。后续原生触感遵循 macOS 用户操作与硬件条件，单独真人验收。

跳过、重播、切换方向、离开页面、切换审阅页或关闭页面会取消尚未发生的声音节点；静音可立即停止声音，重新开声需重播，避免播放过期 cue。异步开启音频使用取消代次，防止跳过后残留调度。

## 实现与验证

`review.js` 使用同一音频时钟编排声音和画面；静音时使用单调时间。对完整文件调用 `decodeAudioData`，验证成功后才替换当前类别选择；播放使用可停止的 source 节点。参考 [MDN 解码文档](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData)、[音频恢复](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume)、[节点停止](https://developer.mozilla.org/en-US/docs/Web/API/AudioScheduledSourceNode/stop)。

静态检查：

```sh
node --check prototypes/v0.1.1-review/review.js
zsh scripts/harness.sh docs
git diff --check
```

浏览器检查与未验证范围见 [阶段 1 记录](../../docs/exec-plans/active/aisland-v0.1.1-stage-1.md)。所有视听草样仍需用户实际观看试听，不能把原型可运行或波形存在记为效果通过。
