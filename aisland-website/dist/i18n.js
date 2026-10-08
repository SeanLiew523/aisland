/* Static, reviewed page copy. Translation never replaces the native recording. */
(() => {
  const copy = {
    zh: {
      description: 'AIsland，把编程 Agent 的状态、权限请求与会话入口放进 Mac 的刘海。原生 macOS，本地运行，免费开源。',
      navigation: '网站导航', featuresLink: '功能', githubProject: 'AIsland GitHub 项目',
      download: '下载', downloadMac: '下载 Mac 版',
      tagline: '让 Agent 的每一步，都有回应。', scrollReveal: '向下滚动，看看它如何工作。',
      intro: '思考、等待、完成。\n让状态在 Mac 刘海里有了表情。\n把注意力留给眼前的工作。',
      captureLabel: '原生界面 / MacBook 实机录制',
      videoDescription: 'AIsland 原生界面录制：运行中、回答、授权、会话与完成；首页单独播放空闲角色',
      chaptersLabel: '原生演示片段',
      chapter0: '运行中', chapter1: '回答', chapter2: '授权', chapter3: '会话', chapter4: '完成',
      play: '▶ 播放', pause: 'Ⅱ 暂停', playLabel: '播放原生演示', pauseLabel: '暂停原生演示',
      caption0: '等待下一步，也有自己的表情。', caption1: 'Agent 正在运行，三点轻轻脉冲。',
      caption2: '等待回答，暖黄色提醒接住问题。', caption3: '需要授权，粉色提醒等你决定。',
      caption4: '多个 Agent，一眼看清。', caption5: '完成之后，回到你的工作。',
      captureNote: '原生渲染录制 · 示例会话 · macOS 原版壁纸合成背景',
      agentsLabel: '支持的部分 Agent', workflowLabel: '01 — 工作流', workflowAside: '少些切换，多些创造。',
      featureHeading: '状态有了表情。\n下一步，一眼明白。',
      featureIntro: '思考时轻轻脉冲，等待时柔和眨眼。\n授权与回答各有状态色，关键时刻提醒你。',
      statesLabel: '真实录制的状态动效',
      idleName: '空闲', idleNote: '轻轻注视', thinkingName: '思考', thinkingNote: '三点脉冲',
      approvalName: '等待授权', approvalNote: '粉色提醒', answerName: '等待回答', answerNote: '暖黄色提醒',
      idleAlt: '空闲时的原生视线与眨眼', thinkingAlt: '思考时的原生三点脉冲',
      approvalAlt: '等待授权时的粉色原生表情', answerAlt: '等待回答时的暖黄色原生表情',
      observeLabel: '[ 01 / 观察 ]', decideLabel: '[ 02 / 决定 ]', returnLabel: '[ 03 / 返回 ]',
      observeHeading: '多个 Agent，一眼看清。', decideHeading: '需要决定，就在此刻。', returnHeading: '从状态，回到现场。',
      observeCopy: '运行、等待输入、完成。把分散的会话状态聚在一起，随时知道谁需要你。',
      decideCopy: '查看支持的权限请求，允许或拒绝；接住 Agent 的提问，让工作继续推进。',
      returnCopy: '从会话入口回到对应终端或桌面应用。可用动作随 Agent 和接入方式而不同。',
      sessionsAlt: '原生应用的示例会话列表', permissionAlt: '原生应用的示例权限请求', completeAlt: '原生应用的示例完成状态',
      essentialsLabel: '02 — 为 Mac 而生', nativeLabel: '01 / 原生', localLabel: '02 / 本地', openLabel: '03 / 开源',
      nativeHeading: '为 Mac 而生。', localHeading: '就在你的本机。', openHeading: '开放，也属于你。',
      nativeCopy: 'Swift 与 AppKit。刘海屏和外接屏各有适配。',
      localCopy: '无需账号，无遥测。数据留在你的 Mac。',
      openCopy: 'GPL-3.0 开源。阅读源码，打造自己的岛。',
      closingEyebrow: '下一段工作，从这里开始。',
      releaseNote: 'macOS 14+ · Apple Silicon / Intel · v0.1.1 · 已完成 Apple 公证',
      footerCredit: '基于 OPEN ISLAND / 免费开源',
    },
    en: {
      description: 'AIsland brings coding agent status, permission requests, and session shortcuts into your Mac’s notch. Native macOS. Local first. Free and open source.',
      navigation: 'Site navigation', featuresLink: 'Features', githubProject: 'AIsland on GitHub',
      download: 'Download', downloadMac: 'Download for Mac',
      tagline: 'Keep every agent in sight.', scrollReveal: 'Scroll to see it in action.',
      intro: 'Thinking. Waiting. Done.\nAgent status, right in your Mac’s notch.\nStay focused on the work in front of you.',
      captureLabel: 'NATIVE UI / CAPTURED ON MACBOOK',
      videoDescription: 'Recorded native AIsland interface: running, answer, approval, sessions and done; a separate idle character loops on the homepage',
      chaptersLabel: 'Native demo chapters',
      chapter0: 'Running', chapter1: 'Answer', chapter2: 'Approval', chapter3: 'Sessions', chapter4: 'Done',
      play: '▶ Play', pause: 'Ⅱ Pause', playLabel: 'Play native demo', pauseLabel: 'Pause native demo',
      caption0: 'Even waiting has an expression.', caption1: 'Working, with a gentle three-dot pulse.',
      caption2: 'A warm yellow alert when a question needs you.', caption3: 'A pink alert when your permission is needed.',
      caption4: 'Every agent, at a glance.', caption5: 'All done. Back to your flow.',
      captureNote: 'Native UI capture · Example sessions · Original macOS wallpaper composited behind',
      agentsLabel: 'Some supported agents', workflowLabel: '01 — THE WORKFLOW', workflowAside: 'LESS SWITCHING. MORE BUILDING.',
      featureHeading: 'A face for every state.\nKnow what’s next.',
      featureIntro: 'Gentle pulses while thinking. Soft blinks while waiting.\nDistinct colors for permissions and questions, right when you need them.',
      statesLabel: 'Recorded native state animations',
      idleName: 'Idle', idleNote: 'A gentle gaze', thinkingName: 'Thinking', thinkingNote: 'Three-dot pulse',
      approvalName: 'Permission needed', approvalNote: 'A pink alert', answerName: 'Answer needed', answerNote: 'A warm yellow alert',
      idleAlt: 'Native idle gaze and blinking', thinkingAlt: 'Native three-dot thinking pulse',
      approvalAlt: 'Pink native expression awaiting permission', answerAlt: 'Warm yellow native expression awaiting an answer',
      observeLabel: '[ 01 / OBSERVE ]', decideLabel: '[ 02 / DECIDE ]', returnLabel: '[ 03 / RETURN ]',
      observeHeading: 'Every agent, at a glance.', decideHeading: 'Decide when it matters.', returnHeading: 'Back to where you left off.',
      observeCopy: 'Running, waiting for input, or done. Bring scattered sessions together and see who needs you.',
      decideCopy: 'Review supported permission requests, approve or deny, and answer your agent’s questions to keep work moving.',
      returnCopy: 'Jump from a session back to its terminal or desktop app. Available actions depend on the agent and integration.',
      sessionsAlt: 'Example session list in the native application', permissionAlt: 'Example permission request in the native application', completeAlt: 'Example completed session in the native application',
      essentialsLabel: '02 — BUILT TO BELONG', nativeLabel: '01 / NATIVE', localLabel: '02 / LOCAL', openLabel: '03 / OPEN',
      nativeHeading: 'Made for Mac.', localHeading: 'Right on your Mac.', openHeading: 'Open. Make it yours.',
      nativeCopy: 'Swift and AppKit. Adapted for notched MacBooks and external displays.',
      localCopy: 'No account. No telemetry. Your data stays on your Mac.',
      openCopy: 'Open source under GPL-3.0. Read the code and build your own island.',
      closingEyebrow: 'YOUR NEXT SESSION STARTS HERE.',
      releaseNote: 'macOS 14+ · Apple Silicon / Intel · v0.1.1 · Apple notarized',
      footerCredit: 'BUILT ON OPEN ISLAND / FREE & OPEN SOURCE',
    },
  };
  let language = 'zh';
  try { if (localStorage.getItem('aisland-language') === 'en') language = 'en'; } catch { /* Storage is optional. */ }
  const t = key => copy[language][key];
  window.AIslandI18n = Object.freeze({ t });

  function applyLanguage() {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    document.querySelectorAll('[data-i18n]').forEach(element => {
      const lines = t(element.dataset.i18n).split('\n');
      element.replaceChildren(...lines.flatMap((line, i) => i ? [document.createElement('br'), document.createTextNode(line)] : [document.createTextNode(line)]));
    });
    for (const [data, attribute] of [['i18nAlt', 'alt'], ['i18nAria', 'aria-label'], ['i18nContent', 'content']]) {
      document.querySelectorAll(`[data-${data.replace(/[A-Z]/g, letter => '-' + letter.toLowerCase())}]`).forEach(element => element.setAttribute(attribute, t(element.dataset[data])));
    }
    const button = document.querySelector('#language-switch');
    button.textContent = language === 'zh' ? 'EN' : '中文';
    button.lang = language === 'zh' ? 'en' : 'zh-CN';
    const label = language === 'zh' ? '切换为英文' : 'Switch to Chinese';
    button.setAttribute('aria-label', label);
    button.title = label;
    document.dispatchEvent(new CustomEvent('aisland:languagechange'));
  }
  document.querySelector('#language-switch').addEventListener('click', () => {
    language = language === 'zh' ? 'en' : 'zh';
    try { localStorage.setItem('aisland-language', language); } catch { /* Storage is optional. */ }
    applyLanguage();
  });
  applyLanguage();
})();
