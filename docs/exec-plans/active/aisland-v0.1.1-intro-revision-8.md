# AIsland v0.1.1 引导原型 R8

日期：2026-10-04（北京时间）。状态：`READY_FOR_VISUAL_REVIEW`。R7 的待确认方案被用户本轮修订取代，不能记为已批准；原生引导仍保留已批准 V6（`32c94f2`），第五版回退点 `86f2865` 保留。

用户要求：所有阶段不显示额外介绍文字；归位中的六角色圆环改为站点的彩色轨道三角角色连续变为圆形角色。原任务画面里的标题、Agent 标签、审批/回答内容属于演示界面，保留；审阅控制留在原型，正式强制首启没有这些控件。

## 实现

删除 stage-copy 元素和所有写入/显示逻辑；不显示开场和归位短句、字幕或 AGENT 编号。无障碍图像名称只使用阶段名称。中英文审阅控件和原生任务素材继续提供双语版本。

实际浏览器打开用户指定的 `https://aisland.brianliew.chatgpt.site/`，确认原站点 SCATTERED → ORBIT → ONE ISLAND 的演示。R8 直接导入相同 vendored BotEngine 的 `orbit` 状态和 SVG 层序；不是两张截图交叉淡入。旋转、形状、眼睛、彩色弧线由原引擎生成。`intro-bloub-source.json` 更新 adapter、引擎源和生成 bundle 的 SHA256；MIT 许可保留。

归位岛沿 V6 原轨迹从 18.1 秒开始上移；19.8 秒可见三角姿态，21.6 秒可见圆形姿态。角色从 18.9 秒出现，中心为视口 55% 高度，尺寸取视口宽度 68% 与高度 66% 的较小值。完整 0–3.3 秒原始姿态采样以 1.1 倍速度放入末尾三秒，避免角色在岛刚开始上移时遮住它。减少动态时固定使用已变圆的 2.5 秒姿态。R7 汇入左侧空闲/思考 SVG 保留。

岛壳形状比例、四条任务行、路径、22 秒 timeline 与音频源码逐字保持 V6 基线。原型额外提供两个外部静帧审阅按钮，便于比较三角和圆形；不是正式首次安装界面。

## 验证与审阅

入口：`http://127.0.0.1:49161/?revision=8#intro`。

`verify-r8.cjs` 替代历史 `verify-r7.cjs`：六组同时间缩放、六个原引擎形变采样、减少动态固定姿态、无描述文字节点、V6 壳/卡片/声音/timeline 保持检查及 24 张离线画面通过。JavaScript 语法和 diff check 通过。离线输出在 ignored `output/verification/v0.1.1-intro-revision-8/`。

实际 IAB 截图确认三角/圆形及英文展开的全屏画面，没有介绍短句或六角色标签；岛与新角色分开。证据：`browser-zh-fullscreen-triangle.jpg`、`browser-zh-fullscreen-sphere.jpg`、`browser-en-fullscreen-opening.jpg`。实际播放从头自然完成 22 秒并进入 Setup；audio state 为 running，2647 次 RAF 记录，最大间隔 59.6 ms（开场 0.249 秒），两处审批/回答转场记录最大间隔 9.4 ms。`browser-playback.json` 保存紧凑回执。完整播放未持续记录全屏状态，不将静帧全屏证明推广为完整全屏播放；声音 running 也不代表真人耳感已确认。

用户视觉与音画感受仍 pending。确认后再同步原生，构建并复验强制首启、第二次不重播和系统中英语言。当前没有修改 Native Swift 或 V6 已批准媒体，不动 v0.1.0 公证发布。
