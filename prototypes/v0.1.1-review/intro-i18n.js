// Copy only. The reviewer chooses the language and applies it to the page.
// Scene title strings intentionally preserve the current <br> line breaks.
window.AIslandIntroText = {
  zh: {
    language: "zh-Hans",
    languageName: "简体中文",
    page: {
      title: "AIsland · v0.1.1 效果审阅",
      brandLabel: "AIsland 效果审阅",
      edition: "v0.1.1 / 效果审阅 07",
      tabsLabel: "审阅内容",
      introTab: "安装引导",
      soundTab: "任务声音",
      sourcesTab: "新工具接入",
      eyebrow: "01 / SEE · HEAR",
      heading: "让等待，有回应。",
      previewDescription: "从全屏的第一声，到屏幕顶部的一座小岛。",
      canvasLabel: "AIsland 引导动画预览",
      curtainLabel: "A · 温润共鸣 / 第七版",
      curtainDescription: "约 22 秒 · 建议全屏并开启声音",
      directorTitle: "A · 温润共鸣，第七版",
      directorDescription: "让界面自己讲故事。<br>声音随汇聚和归位逐步展开。",
      reviewNote: "任务画面沿用原生组件与录制，使用示例会话。Logo 汇聚为独立品牌演示；各工具接入能力另行验收。点击阶段看静帧，完整音画从头播放。",
      footer: "引导修订审阅 · 本页为独立原型。",
      footerHint: "Esc 跳过开场 · 支持减少动态效果"
    },
    controls: {
      play: "播放音画预览",
      replay: "从头重播",
      skip: "跳过开场",
      soundOn: "声音开启",
      soundOff: "声音关闭",
      mute: "静音观看",
      reduceMotion: "减少动态效果",
      fullscreen: "全屏观看 ↗",
      exitFullscreen: "退出全屏 ↙",
      exitReview: "退出审阅 ↙",
      nativeExit: "退出审阅",
      nativeExitLabel: "退出审阅（Esc 或 Command Q）",
      languageLabel: "审阅语言",
      followSystem: "跟随系统"
    },
    status: {
      waiting: "等待播放",
      playing: "{time} / {duration} 秒{muted}",
      mutedSuffix: " · 静音",
      chooseTools: "选择工具 · 流程演示",
      soundEnabled: "声音已开启 · 请从头播放",
      still: "静帧审阅 · {time} 秒 · 无声音",
      paused: "已暂停 · 返回后从头重播",
      fullscreenUnavailable: "当前浏览器不支持全屏，可在浏览器窗口中观看。",
      preparing: "正在准备原生画面…",
      audioUnavailable: "浏览器未能开启声音，请重试。",
      assetUnavailable: "素材未能载入：{source}",
      previewUnavailable: "暂时无法加载预览，请重新播放。"
    },
    setup: {
      kicker: "YOUR ISLAND, YOUR TOOLS",
      title: "把你的工具，<br>带上小岛。",
      description: "选择常用工具，随后检查接入能力。",
      next: "查看接入方案",
      hint: "此处演示选择流程，不安装或修改工具。",
      tools: ["Hermes CLI", "DeepSeek Harness", "MiniMax Code", "豆包工作", "千问办公"]
    },
    scenes: [
      { kicker: "HELLO, AISLAND", title: "让等待，有回应。", caption: "任务在继续，你可以做自己的事。" },
      { kicker: "MANY AGENTS, ONE ISLAND", title: "你常用的 Agent，<br>汇到一座岛。", caption: "每个工具都有自己的方式，你有一个共同的入口。" },
      { kicker: "ONE PLACE, MANY TASKS", title: "把分散的任务，<br>汇到一起。", caption: "原生组件示例 · Claude、Codex、Gemini、WorkBuddy 四条任务行。" },
      { kicker: "APPROVAL · NATIVE DEMO", title: "这一步，<br>需要你点头。", caption: "原生示例 · 查看 Claude 的文件修改请求。" },
      { kicker: "ANSWER · NATIVE DEMO", title: "给一点方向，<br>它就能继续。", caption: "原生示例 · 选择登录验证方式。" },
      { kicker: "SESSIONS · NATIVE DEMO", title: "谁在忙，<br>一眼就看清。", caption: "站点原生录制 · 回到 Claude 与 Codex 会话列表。" },
      { kicker: "DONE · NATIVE DEMO", title: "完成了。", caption: "原生示例 · 登录流程更新，检查通过。" },
      { kicker: "ALWAYS WITHIN REACH", title: "随时，回应。", caption: "全屏归位至顶部中央；真实刘海请使用原生审阅窗口。", nativeCaption: "回到这块屏幕的刘海位置。" }
    ],
    sceneList: [
      { time: "00–03", title: "展开", description: "共鸣展开，短句只在关键时刻出现" },
      { time: "03–05", title: "Agent 汇聚", description: "九个 Logo 汇入，持续声音逐步叠入" },
      { time: "05–08", title: "汇入", description: "四条原生任务行沿路径进入岛里" },
      { time: "08–11", title: "审批", description: "原生文件请求与允许 / 拒绝" },
      { time: "11–13", title: "回答", description: "原生问题与回答选项" },
      { time: "13–16", title: "会话", description: "原生列表，查看谁在忙" },
      { time: "16–18", title: "完成", description: "原生完成摘要" },
      { time: "18–22", title: "归位", description: "缓缓回收，蓄势后轻贴真实刘海" }
    ],
    description: {
      logos: "九个 Agent Logo 的独立品牌演示。",
      rows: "Claude、Codex、Gemini、WorkBuddy 四条原生任务行，使用示例内容。",
      nativeFootageLabel: "AISLAND · 站点原生录制 / 示例会话",
      languagePreview: "首次引导默认跟随系统语言；这里可切换中英文审阅。"
    },
    agents: ["Claude", "ChatGPT", "Gemini", "Grok", "Kimi", "MiniMax", "ZCode", "DeepSeek", "WorkBuddy"]
  },
  en: {
    language: "en",
    languageName: "English",
    page: {
      title: "AIsland · v0.1.1 Preview",
      brandLabel: "AIsland preview",
      edition: "v0.1.1 / Preview 07",
      tabsLabel: "Preview sections",
      introTab: "Welcome",
      soundTab: "Task sounds",
      sourcesTab: "Connect tools",
      eyebrow: "01 / SEE · HEAR",
      heading: "A little island. A timely response.",
      previewDescription: "From the first sound to a little island at the top of your screen.",
      canvasLabel: "AIsland welcome animation preview",
      curtainLabel: "A · Warm Resonance / Preview 07",
      curtainDescription: "About 22 seconds · Best viewed fullscreen with sound",
      directorTitle: "A · Warm Resonance, Preview 07",
      directorDescription: "Let the interface tell the story.<br>Sound grows with the gathering and the journey home.",
      reviewNote: "Task scenes use native components and recordings with demo sessions. The logo sequence is a separate brand animation; each integration is reviewed separately. Select a stage for a still frame, or play from the start for the full experience.",
      footer: "Welcome preview · This is a standalone prototype.",
      footerHint: "Esc skips the intro · Reduced motion supported"
    },
    controls: {
      play: "Play preview",
      replay: "Play from the start",
      skip: "Skip intro",
      soundOn: "Sound on",
      soundOff: "Sound off",
      mute: "Watch without sound",
      reduceMotion: "Reduce motion",
      fullscreen: "View fullscreen ↗",
      exitFullscreen: "Exit fullscreen ↙",
      exitReview: "Exit preview ↙",
      nativeExit: "Exit preview",
      nativeExitLabel: "Exit preview (Esc or Command Q)",
      languageLabel: "Preview language",
      followSystem: "Use system language"
    },
    status: {
      waiting: "Ready to play",
      playing: "{time} / {duration} s{muted}",
      mutedSuffix: " · Muted",
      chooseTools: "Choose your tools · Demo",
      soundEnabled: "Sound is on · Play from the start",
      still: "Still frame · {time} s · No sound",
      paused: "Paused · Play from the start when you return",
      fullscreenUnavailable: "Fullscreen is unavailable in this browser. You can watch in the browser window.",
      preparing: "Preparing the native preview…",
      audioUnavailable: "The browser could not turn on sound. Please try again.",
      assetUnavailable: "Could not load this asset: {source}",
      previewUnavailable: "The preview could not load. Please try playing again."
    },
    setup: {
      kicker: "YOUR ISLAND, YOUR TOOLS",
      title: "Bring your tools<br>to the island.",
      description: "Choose the tools you use, then review their integrations.",
      next: "Review integrations",
      hint: "This demo shows the selection flow. It does not install or change your tools.",
      tools: ["Hermes CLI", "DeepSeek Harness", "MiniMax Code", "Doubao Work", "Qwen Office"]
    },
    scenes: [
      { kicker: "HELLO, AISLAND", title: "A little island.<br>A timely response.", caption: "Your tasks keep going. So can you." },
      { kicker: "MANY AGENTS, ONE ISLAND", title: "Your favorite agents.<br>One little island.", caption: "Each tool works its own way. You have one place to find them." },
      { kicker: "ONE PLACE, MANY TASKS", title: "Bring your tasks<br>together.", caption: "Native component demo · Four task rows: Claude, Codex, Gemini, and WorkBuddy." },
      { kicker: "APPROVAL · NATIVE DEMO", title: "This step<br>needs your go-ahead.", caption: "Native demo · Review Claude’s request to change a file." },
      { kicker: "ANSWER · NATIVE DEMO", title: "A little direction.<br>And it can carry on.", caption: "Native demo · Choose a sign-in verification method." },
      { kicker: "SESSIONS · NATIVE DEMO", title: "See who’s busy<br>at a glance.", caption: "Native site recording · Back to the Claude and Codex session list." },
      { kicker: "DONE · NATIVE DEMO", title: "All done.", caption: "Native demo · Sign-in flow updated. Checks passed." },
      { kicker: "ALWAYS WITHIN REACH", title: "Always within reach.", caption: "The island settles at the top center. Use the native preview to align it with your Mac’s notch.", nativeCaption: "Back to the notch on this screen." }
    ],
    sceneList: [
      { time: "00–03", title: "Opening", description: "Resonance and a brief welcome" },
      { time: "03–05", title: "Agents gather", description: "Nine logos gather as the sound grows" },
      { time: "05–08", title: "Tasks gather", description: "Four native task rows flow into the island" },
      { time: "08–11", title: "Approval", description: "Native file request with Allow / Deny" },
      { time: "11–13", title: "Answer", description: "A native question with answer choices" },
      { time: "13–16", title: "Sessions", description: "The native list shows who’s busy" },
      { time: "16–18", title: "Done", description: "The native completion summary" },
      { time: "18–22", title: "Home", description: "A slow inward breath and a soft landing" }
    ],
    description: {
      logos: "A separate brand animation featuring nine agent logos.",
      rows: "Four native task rows for Claude, Codex, Gemini, and WorkBuddy, using demo content.",
      nativeFootageLabel: "AISLAND · Native site recording / Demo sessions",
      languagePreview: "The first welcome follows your system language. Switch between Chinese and English here to review it."
    },
    agents: ["Claude", "ChatGPT", "Gemini", "Grok", "Kimi", "MiniMax", "ZCode", "DeepSeek", "WorkBuddy"]
  }
};
