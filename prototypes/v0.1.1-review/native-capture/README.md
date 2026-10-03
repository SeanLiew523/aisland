# 隔离原生任务行导出

一条命令直接提取当前生产源码的 `IslandSessionRow`，使用 SwiftUI `ImageRenderer` 离屏导出四个真实组件示例。不启动 `OpenIslandApp`、不创建窗口、不读取真实会话、账号、bridge 或用户偏好。

```sh
python3 prototypes/v0.1.1-review/native-capture/capture.py
```

可通过 `--source /绝对路径/仓库 --output /绝对路径/素材目录` 选择源码与输出。`--language zh-Hans` 或 `--language en` 选择固定语言，默认简体中文；重复参数可用一次编译导出两种语言：

```sh
python3 prototypes/v0.1.1-review/native-capture/capture.py --language zh-Hans --language en
```

默认输出为 `output/verification/v0.1.1-intro-revision-3/native-rows`；生成 `native-row-{claude,codex,gemini,workbuddy}-{zh-Hans,en}@2x.png`、`native-row-manifest-{lang}.json` 和 `native-row-provenance-{lang}.json`，不同语言不覆盖。manifest 记录 language、示例标题与摘要，provenance 同时记录 language 和导出工具 SHA256。此工具固定语言，仅服务素材生成；系统默认语言选择由引导宿主另行处理。

输入均为固定 `.demo` 会话，元数据与 jump target 为 nil，所有操作回调为 nil 或 noop，`isInteractive=false`。行组件、配色、品牌徽章和字体直接沿用生产源码；示例任务文字不是用户真实任务。选择生产支持的 glyph 状态指示，取消绘图组以保持离屏导出稳定，使用生产 V6 ink 背景。输出宽 360 逻辑点，2× 像素；高度由原生组件自行布局。窄宽度减少引导中的缩小比例，标题按生产组件规则截断，品牌徽章保留。

工具把生产行及其私有辅助组件提取到临时 Swift Package，只链接 `OpenIslandCore` 和 `MarkdownUI`，不复制或初始化 `AppModel`。仅将 `LanguageManager` 偏好读取/写入替换成命令行明确选择的语言，资源接口指向隔离的本地化资源包。上述转换有明确断言，源结构变化会停止而不是猜测。原生组件的内建状态标签按生产源码保留，不为素材手改组件绘制或覆盖文字。

provenance 记录实际仓库提交、提取文件的完整 SHA256、提取起止行与 SHA256、Core 和本地化资源校验值、Swift Package 锁定结果及 PNG 校验值。需要 Xcode 命令行工具和 Swift 6.2，首次运行可能获取已声明的 Swift Package 依赖。临时源码、编译产物在完成后自动删除。PNG 编译生成与原生组件来源有效，不代表完整引导视觉已获用户验收。
