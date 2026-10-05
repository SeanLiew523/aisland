# DeepSeek Harness 桌面源插件（v0.1.1 第一切片）

插件为官方 DeepSeek Harness Desktop 提供未来任务的元数据事件与精确 ID 导航桥。当前已在本机真实桌面 profile 加载，并验证专用任务的成功与中止事件；会话选择、前台与 native 通知声音仍待正式验收 App 检查。详细证据见 [真实接入验证](../../docs/exec-plans/active/v0.1.1-deepseek-live-verification.md)。审批/问答本轮未提供可操作按钮。

## 来源与版本边界

本轮只读核对 `/Applications/DeepSeek Harness.app` 的 0.2.0-rc.2、`com.deepseek.dsh` 和其 ASAR 中以下接口；没有修改应用包，也未读取真实会话、凭证或 profile：

- `@deepseek-ai/dsh-session/lib/index.js`：`session/event(session,event)`、`session/disposed(session)`，`session.id`、`session.header.cwd`、`firstLiveSeq`；事件 envelope 为 `type/seq/time/data`。
- `@deepseek-ai/dsh-agent-loop/lib/index.js`：`turn/start.data.turn` 和 `turn/end.data.{turn,reason}`。
- `@deepseek-ai/dsh-client-ui-workspace/lib/client.js`：公共 `ctx.uiWorkspace.openSession(sessionId)`；返回 `void`，不提供公开选中回执。`selection` 为私有字段，本插件不读取。
- `@deepseek-ai/dsh-client-connection/lib/client.js` 与宿主服务：`ctx.connection.rpc.handle(channel,handler)` 和客户端 `rpc.call(channel,endpoint,payload,signal)`；通道沿用源应用的 trust/auth fence。

在线一手规范同时核对了 [插件打包与 profile](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/develop/basic/publish.md)、[生命周期清理](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/develop/basic/index.md)、[配置 schema](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/develop/basic/config.md)、[客户端模块](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/subsystems/client-modules.md)、[RPC](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/client/connection/src/rpc.ts) 与 [桌面 CLI/profile 管理](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.md)。在线 master 当前为较新开发版本，安装前需再次验证本机版本契约。

## 生命周期与隐私

`package.json` 声明 `dsh.bundle.patch`、`./client` 和 `dsh.client`。宿主注入 `sessions/connection/webServer`，浏览器注入 `connection/uiWorkspace`；`ctx.on` 与 `ctx.effect` 随插件卸载清理。

只转发 `profile_id/session_id/turn_id/sequence/cwd/timestamp`、来源身份、导航目标和粗粒度 `result_reason`；不转发消息正文、标题、tool input、错误详情或任意 hook reason。不存在目录时 `cwd` 为 `""`，不猜成宿主进程目录。

| 源 reason.kind | AIsland event | result_reason |
| --- | --- | --- |
| completed | turnCompleted | completed |
| error / blocked / max-tokens | turnFailed | 原粗枚举 |
| aborted | turnInterrupted | aborted:user/parent/hook/disposed/legacy/unknown |
| interrupted / forked | turnInterrupted | 原粗枚举 |
| 未知扩展 reason | turnFailed | unknown |

旧时间、seed seq、旧 turn 和重复 seq 被抑制；`idle` 不作为完成。已观察对应 `turn/start` 的结束带 `source_observed_start: true`；插件重载后仅见结束仍同步状态，但带 `source_observed_start: false`，native 必须收拢任务且保持静默，避免长期显示运行中或补响完成。源 session disposed 只发 `sessionEnded` 收拢状态。插件重启不恢复旧 turn 为新完成，也不补响桥断连时遗漏的通知。

Bridge 使用 UTF-8 newline JSON，结构为：

```json
{"type":"command","command":{"type":"processRuntimeLifecycleHook","runtimeLifecycleHook":{"source":"deepseekHarness","event":"turnCompleted","profile_id":"desktop","session_id":"real-session-id","turn_id":"2","sequence":42,"cwd":"/project","timestamp":1791000000000,"result_reason":"completed","app_bundle_id":"com.deepseek.dsh","app_conversation_id":"real-session-id","terminal_app":"DeepSeek Harness.app","navigation_socket_path":"/absolute/deepseek-navigation.sock"}}}
```

传输异步、队列最多 256 条、每连接默认 200ms 超时、无重试和历史回放。断连可能丢事件，但不会阻塞来源 agent；没有观察到对应 start 的 native 结束事件也不能提示成功。

## 导航协议

首选 endpoint 为 bridge 同目录 `deepseek-navigation.sock`，权限 `0600`。插件在同目录自建随机 `.ds-*` 私有目录（`0700`）绑定 socket，再以独占 hard link 发布首选路径；Node/libuv 退出时只清理私有绑定路径，外层路径仅在 `dev/ino/uid/mode` 仍匹配时清理。因此被外部替换的 endpoint 不会被 `server.close()` 自动删除。配置目录必须属于当前用户且不可由 group/world 写入。

同目录 `endpoint.aisland-owner.json` 与首选路径 `deepseek-navigation.sock.aisland-current.json` 均为独占创建的 `0600` 普通文件。所有权证明/locator 只含 `version/source/path/requested_path/profile_sha256/uid/dev/ino/bind_directory/directory_dev/directory_ino/source_pid/executable_path`，没有会话、任务或用户正文。读取不跟随 symlink，要求同 uid、单 hard link、最多 2048 字节；profile hash、路径与 socket/private-directory 身份必须完整匹配。

重启时仅在无数据连接探测于最多 200ms 内返回 `ECONNREFUSED`、端点与证明身份再次匹配后，回收本插件残留 socket/证明/私有目录。活动实例、未知 socket、普通文件或 symlink 不会被删除。旧版失效 socket 没有证明时保留，改用同目录固定 `ds-nav-<profile-and-path-hash>.sock`；后续 lifecycle 的 `navigation_socket_path` 发布实际端点。异步 `listen()` 返回 readiness promise；加载/导航失败不阻止 lifecycle，卸载等待初始化完成后清理，禁止卸载后发布端点。

AIsland 导航先从已缓存路径的 current locator 或其 owner proof 验证当前 endpoint，然后才发送请求。除文件身份外，native 核对真实进程 `proc_pidpath`、官方 bundle `com.deepseek.dsh`/`0.2.0-rc.2` 与 bundle executable，并在连接后核对 `LOCAL_PEERPID` 和文件身份。旧任务卡即使仍保存迁移前路径也可使用当前 locator；陌生但可连接的旧 endpoint 不接收导航请求。新版 DeepSeek 需重新核对来源契约。

每个导航连接最多 4096 字节、单条 newline JSON；默认 2 秒内必须收到客户端回执。支持测试独立路径。

请求：

```json
{"version":1,"action":"openSession","request_id":"uuid","profile_id":"desktop","session_id":"real-session-id"}
```

回执：

```json
{"version":1,"request_id":"uuid","profile_id":"desktop","session_id":"real-session-id","status":"dispatched"}
```

`dispatched` 仅表示已将确切 ID 交给公共 `openSession` 且未抛异常；不能证明会话已经可见、会话加载成功或来源已前台。失败回 `status: failed` 与 `reason`：`invalidRequest/profileMismatch/clientUnavailable/clientError`。native 必须对齐 version、request、profile、session；超时不能降级成成功。

宿主通过 source 的认证 `/aisland-deepseek` RPC channel 提供 `poll` 与 `ack`。浏览器默认每 500ms 领取一个导航请求，调用 `openSession(request.session_id)`，回传相同身份与 `dispatched/failed`。源客户端退出或卸载后过期请求回失败；没有执行真实任务的外部 API。`dsh://open` 只可用于独立窗口聚焦步骤，不拼造 `/session` 深链接。

## 安装与卸载

先运行只检查插件本身并打印命令的 dry-run：

```sh
node Integrations/DeepSeek/plan.mjs
```

该脚本不运行 DeepSeek CLI、不读写真实 profile、不退出或打开任何 app。用户已授权本机四来源真实验收；后续安装按官方桌面流程：先启动桌面一次初始化 profile，然后完全退出桌面。保持同一个 `DSH_HOME`，用随包 CLI；npm 安装的 dsh 不能修改 desktop profile。

执行前另存 `$DSH_HOME/profiles/desktop` 下已有 `package.json`、`cordis.patch.yml`、pnpm lock/workspace 配置（默认 DSH_HOME 为 `~/.dsh`），并记录原 bundles 与 dependencies。随后：

```sh
DSH_DESKTOP_CLI='/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh'
"$DSH_DESKTOP_CLI" plugin --profile desktop list
"$DSH_DESKTOP_CLI" plugin --profile desktop add '/absolute/path/to/Integrations/DeepSeek'
```

这是本地预构建 JS bundle，不需要 prepare/build 脚本。源目录需持续存在；打包分发可用 `npm pack` tarball 再 add tarball。官方 CLI 维护依赖与 bundle 激活，保留已有条目；不要重写整个 profile 或覆盖用户 patch。CLI 完成后再打开 Desktop。

卸载同样先完全退出 Desktop，然后执行：

```sh
"$DSH_DESKTOP_CLI" plugin --profile desktop remove '@aisland/deepseek-harness-plugin'
```

这仅去掉该依赖和 bundle layer；若曾手动加过下述 AIsland 配置块，只移除属于 `aisland-deepseek` 的块，保留其他配置。CLI 完成后再打开 Desktop。运行中热卸载由 effect 清理监听器、轮询、RPC route、待回执连接与身份仍匹配的自有 socket/证明。正常退出清理；异常退出的自有残留按上述严格证明与拒绝连接规则自动恢复。升级仍须完全退出 Desktop，再走官方 CLI 安装流程；不在运行中的 source profile 上改插件。

## 可配置项

所有配置只属于 `aisland-deepseek` row。用户 profile 的 patch 晚于 bundle layer；配置替换为整个 config 值，保留已插入组件的 name/id。默认 `profileID: desktop`，如隔离验证改名要明确保持 native 与源一致：

```yaml
- id: aisland-deepseek
  config:
    profileID: desktop
    bridgeSocketPath: /absolute/isolated/bridge.sock
    navigationSocketPath: /absolute/isolated/deepseek-navigation.sock
    bridgeTimeoutMs: 200
    navigationTimeoutMs: 2000
    pollIntervalMs: 500
```

bridge 路径优先配置，随后 `OPEN_ISLAND_SOCKET_PATH`、兼容 `VIBE_ISLAND_SOCKET_PATH`，最终沿 AIsland `BridgeSocketLocation.defaultURL`。导航路径优先配置，随后 `OPEN_ISLAND_DEEPSEEK_NAVIGATION_SOCKET_PATH`，最终 bridge 同目录；实际值附在生命周期 metadata 的 `navigation_socket_path`。桌面从 Finder 启动不必继承 shell 环境变量，生产配置应使用独立 row。

## 当前验证及下一真实验证路线

```sh
node --test Integrations/DeepSeek/test/*.test.mjs
node --check Integrations/DeepSeek/index.mjs
node --check Integrations/DeepSeek/core.mjs
node --check Integrations/DeepSeek/client.js
node Integrations/DeepSeek/plan.mjs
zsh scripts/test-clt.sh --filter DeepSeekNavigationClientTests -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
```

本轮 29 项隔离 JS 测试通过，新增真实子进程 `SIGKILL` 残留恢复、旧版无证明迁移、活动碰撞、未知文件/符号链接、错误 profile/inode、探测期间替换、卸载竞态及 libuv 清理隔离；native 的 8 项定向测试也通过，覆盖当前 locator、缓存旧卡、陌生可连接端点不发请求、对端 PID 匹配、所有权/来源拒绝和完整请求期限。上述构造数据与临时 socket 不能代替真实 source 冷启动和原卡导航验收。早期版本另在临时目录以本机 ASAR 中 Schemastery 3.18.4/Cosmokit 验证插件 import、默认值和非法 timeout 拒绝，没有调用插件 apply。package dry-run 确认宿主、客户端和 patch 均入包。覆盖显式 reason 分类、隐私、并行归属、去重、旧 turn/replay/重启不重响、断 bridge 的源继续、隔离 socket 顺序、ACK 身份匹配/失败/超时及 fakeCordis/client 卸载清理。测试使用构造 session 与 fake RPC，socket 只在临时目录；不能代替 app 插件加载和真实验收。

已用可丢弃测试目录与专用会话验证成功和取消；后续继续检查成功、失败、取消、两个并行任务、重复标题、源退出/恢复、AIsland 重启与桥断连。分别记录确切会话选中、内容加载、macOS 前台及通知声音；完成后卸载确认原 profile 保留。审批/问答下一切片再核对 `approval/request` waterfall 与 userQuestions 的归属、取消及操作回传，未接通前不可显示可操作审批/回答。

## Official linked-plugin loading compatibility

The installed 0.2.0-rc.2 desktop loader shares host packages with linked plugins
only when they are declared as peerDependencies. Schemastery is a host peer,
not an uninstalled local dependency. The native loader initially rejected the
linked plugin, despite its outer bundle appearing enabled in the UI.

This release's connection.rpc getter also retains the provider's Cordis shadow.
Navigation registration declares webServer injection and explicitly passes the
plugin caller to connection.register(ctx, channel, handler). This is the same
authenticated registration route used by rpc.handle; it changes no shared
provider, credentials, SDK or host profile injection. Later hosts without that
method retain the handle path. The installed host now creates the navigation
endpoint and delivers a real tiny task's start and successful terminal event.
Exact visible navigation and native notification acceptance remain separate.
