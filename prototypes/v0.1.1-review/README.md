# AIsland v0.1.1 效果审阅原型

独立 HTML / Canvas / Web Audio 原型，用于用户的分阶段效果对齐；不连接正式应用或第三方工具。原生应用继续使用 Swift / AppKit / SwiftUI，不把本原型作为运行时引入。

在仓库根目录启动仅本机可见的预览：

```sh
python3 -m http.server 49161 --bind 127.0.0.1 --directory prototypes/v0.1.1-review
```

打开 `http://127.0.0.1:49161/?revision=6#intro`。用户已选择 A 声音方向，本版只修订 A。点击“播放音画预览”；可全屏、跳过、静音、重播及减少动态效果；点击右侧阶段可静帧检查细节（不播放声音）。首次播放由点击激活浏览器音频。任务声音页支持三类独立导入 MP3、解码验证、完整试听、自动场景提示、替换和恢复默认草样。

## 审阅范围

- 约 22 秒音画；先展示独立的九个 Agent Logo 汇聚，再进入站点原生任务示例。
- 开场共鸣保留；Logo 到任务汇入增加约 3.7 秒逐层展开的连续纹理，审批前留出静默；回答与审批音色区分，任务继续使用轻呼吸。归位使用约 2.6 秒慢蓄势，20.7 秒贴合后安静结束；已删除的展开尾声与重复品牌收尾保持删除。
- 画面集中于中央，四条原生任务行缩小流入小岛；影片内只在开场和归位出现短文字，中间六段通过真实原生界面变化表达用途。
- 审批、回答、会话、完成与归位直接使用站点原生录制；汇入增加应用原生组件离屏录制的 Claude / Codex / Gemini / WorkBuddy 四条示例，保留真实徽章和任务形式，只改变呈现布局与转场。素材来源与处理见 [assets/SOURCES.md](assets/SOURCES.md)。
- 原生示例顺序为审批、回答、会话、完成；没有将已完成任务接着演成等待输入。
- 默认声音仅为原创合成试听草样，不冒充 macOS Bottle。正式声音设置保留全部系统声音。
- 自动提示长度可试 5 秒或完整音频；本页提议新提示替换上一条，主动试听不受自动静音或长度限制。等待用户确认后再落实原生策略。
- 文件只在浏览器内存中解码，不上传、不持久化。这些原生能力已完成第一轮代码整合，真实应用效果仍待验收。
- 引导文字和任务示例支持中英文；浏览器初次按浏览器语言，原生审阅壳按 `Locale.preferredLanguages.first` 自动选择，右上角可临时切换。不读取或写入生产应用语言偏好。
- 浏览器全屏收束到自身视口顶部；独立 [native-host](native-host/README.md) 才测量真实屏幕刘海。配置页只演示选择，不安装工具。
- 不产生真实触控板触感。后续原生触感遵循 macOS 用户操作与硬件条件，单独真人验收。

跳过、重播、静帧检查、离开页面、切换审阅页或关闭页面会取消尚未发生的声音节点；静音可立即停止声音，重新开声需重播，避免播放过期 cue。异步开启音频使用取消代次，防止跳过后残留调度。

## 实现与验证

`intro-scene.js` 组合原生录制取样帧与独立品牌动效；`intro-audio.js` 定义递进声音与静默区，`review.js` 使用同一音频时钟编排声音和画面；静音时使用单调时间。对完整文件调用 `decodeAudioData`，验证成功后才替换当前类别选择；播放使用可停止的 source 节点。参考 [MDN 解码文档](https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/decodeAudioData)、[音频恢复](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext/resume)、[节点停止](https://developer.mozilla.org/en-US/docs/Web/API/AudioScheduledSourceNode/stop)。

静态检查：

```sh
node --check prototypes/v0.1.1-review/review.js
node --check prototypes/v0.1.1-review/intro-scene.js
node --check prototypes/v0.1.1-review/intro-audio.js
node --check prototypes/v0.1.1-review/intro-i18n.js
zsh scripts/harness.sh docs
git diff --check
```

浏览器检查与未验证范围见 [阶段 1 记录](../../docs/exec-plans/active/aisland-v0.1.1-stage-1.md)及[引导第六版记录](../../docs/exec-plans/active/aisland-v0.1.1-intro-revision-6.md)。用户选择的第五版基线 `86f2865` 已固定为本地标签 `review/v0.1.1-intro-r5`；冻结预览为 `http://127.0.0.1:49162/?revision=5#intro`，该服务使用单独的 Git 导出快照。所有视听草样仍需用户实际观看试听，不能把原型可运行或波形存在记为效果通过。
