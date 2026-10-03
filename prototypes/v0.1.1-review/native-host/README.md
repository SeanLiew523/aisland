# 独立刘海效果审阅壳

这是 AppKit + WKWebView 的本地原型审阅 App，Bundle ID 为 `dev.aisland.intro-review`。它不导入生产应用代码，不读取生产设置、会话、账号或 bridge，不安装到 `/Applications`。页面使用临时 WebKit 数据存储；仅允许原型目录内的文件导航，拒绝远程 HTTP(S) 资源与新窗口，页面只能通过 `window.webkit.messageHandlers.reviewHost.postMessage('close')` 关闭审阅。

```sh
zsh prototypes/v0.1.1-review/native-host/build.sh
```

可选参数为源仓库绝对路径。构建脚本把该仓库的`prototypes/v0.1.1-review` 页面与素材快照（排除 `native-host/`、`output/` 和符号链接）复制到 App 内，输出到同一仓库的 `output/verification/v0.1.1-intro-revision-5/AIsland Intro Review.app`，不会启动 App。完成父分支画面更新后必须重新构建，保证审阅的是当前文件。

只读几何核对，不创建审阅窗口：

```sh
"output/verification/v0.1.1-intro-revision-5/AIsland Intro Review.app/Contents/MacOS/AIslandIntroReview" --geometry-json
```

App 启动后在内建屏幕的完整 `NSScreen.frame` 上显示无边框审阅窗口，保留页面的明确播放入口。暂时隐藏菜单栏和 Dock，退出时恢复原 presentation options。`Esc`、`Command Q` 或右下方“退出审阅”均关闭独立审阅 App。此壳不进入 macOS 独立全屏 Space，不中断生产 AIsland 会话。屏幕配置变化时重新选择内建屏幕并刷新坐标；没有内建屏幕时回退至主屏，并以 `hasHardwareNotch` 标示实际情况。

## 页面坐标接口

在 document start 注入 `window.AIslandReviewHost`，并设置 `html[data-native-review="true"]`。所有尺寸为逻辑点，横坐标相对所选屏幕 `frame.minX`，纵坐标为顶部原点；WebView 1 CSS px 对应 1 逻辑点。显示变更时更新对象，并派发 `aisland-review-geometrychange`（detail 为完整对象）及 `resize`。

- `preferredLanguage`：系统 `Locale.preferredLanguages.first`，供初次选择中文 / 英文；手动审阅切换仅在页面内存中。
- `screen`：`width`、`height`、`displayID`、`builtIn`。
- `notch.x/y/width/height`：最终闭合小岛边界，`height = max(32, safeAreaInsets.top)`。
- `notch.hardwareLeft/hardwareRight`：`auxiliaryTopLeftArea.maxX` 和 `auxiliaryTopRightArea.minX` 决定的物理黑色缺口。
- `notch.exclusionLeft/exclusionRight/exclusionWidth`：缺口每侧加 2 点覆盖范围；禁止在此绘制眼睛。
- `notch.leftWing/rightWing`：覆盖区外每侧 44 点的可见区域（各有 `x/width`），用于左侧角色和右侧智能体数量格；不再把两只眼睛分置两侧。
- `notch.hasHardwareNotch`：辅助刘海区域实际存在。

当前 MacBook 的预期屏幕为 1728 × 1117，safe top 为 32，缺口边界为 771 / 956；覆盖区宽 189、最终小岛宽 277、x 为 725，两侧可见区域各 44。第五版已在本机从头完整播放到设置页，核对实际角色与数量格贴合，并检查退出后进程结束与桌面恢复。完整音画效果仍需用户确认，外接屏及屏幕变化待后续验收。

实际窗口加载后把窗口、视口、画布及 Bundle ID 写入输出目录 `native-layout.json`，只用于核对这个隔离审阅壳。WebKit 内容过滤分别使用 `^https?://` 和 `^wss?://` 两条规则；不用不支持的正则 alternation，编译失败仍退出。
