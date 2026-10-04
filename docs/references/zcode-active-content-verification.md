# ZCode active content verification boundary

2026-10-04: the user observed that selecting an existing sidebar task changes its body while the conversation heading remains `新建任务`. The current exact-heading check therefore rejects this UI. It must not be replaced by selected-row-only success.

The installed public renderer bundle `/Applications/ZCode.app/Contents/Resources/app.asar` contains these contracts in `out/renderer/assets/styles-Qlp0Bew7.js`:

- Local sidebar `li`: `data-testid: Pa(Sn, n.taskId)`, `data-task-item-key: pe`, `group/task-item`, conditional `bg-selected`; click and Enter/Space use the same handler.
- `JQ` content root: `data-session-id: t ?? "draft"`, `data-projection-seq: Fe?.seq ?? ""`. These are stronger identity candidates than the header.
- `out/renderer/assets/index-j49i-A1J.js` forwards the `restoreSession` URL setting into the workspace UI.

The [Chromium macOS platform implementation](https://github.com/chromium/chromium/blob/main/ui/accessibility/platform/ax_platform_node_cocoa.mm) maps DOM identifier to `ax::mojom::StringAttribute::kHtmlId`; it does not establish a `data-session-id` or `data-testid` → AX identifier mapping. The existence of renderer attributes is not proof that AIsland can read them through AX. No new success path is enabled in this change.

The controller now rejects duplicate matching rows inside a project as well as in standalone lookup. Exact heading, selected row and foreground checks remain required. Synthetic tests cover selected-without-content, changed/generic heading, duplicate rows and metadata redaction. They do not establish real UI acceptance.

For a real existing-card click, an explicit regular-file marker `/tmp/aisland-zcode-metadata-diagnostics-enabled` enables a bounded sample only after navigation fails. It writes `/tmp/aisland-zcode-metadata-diagnostics.log` (owner-only, no symlink following, 64 KiB cap). Fields are candidate/selected counts, heading match boolean, available AX attribute names and hashes/exact equality of `AXIdentifier`, `AXDOMIdentifier`, `AXURL`; no raw ID, title, workspace path or body is written. Remove both files after sampling. The marker is neither created nor activated by the app.

Next acceptance gate: prove a read-only active-content stable session identity reachable through the normal product path, then compare it with the indexed target and selected row. A missing identity, duplicate title, draft/no active content, or different session must fail closed. Until that proof exists, a generic heading remains unavailable rather than becoming a successful precision jump.

Build 55 real observation: the owned task replied to `AISLAND-ZCODE-B55-OK`,
but jumping from an empty draft failed with `sidebar-conversation-miss`.
The bounded sample had zero admitted rows and no conversation content root;
this is not yet proof of a heading-only failure. The matching task remained in
the sidebar, and its indexed title was unchanged. Sampling now also records
the first matching label's four ancestors with action/class booleans and the
same redacted attribute metadata, without changing navigation admission.

The installed 3.14.4 main router accepts workspace paths, not native session
IDs. Renderer `restoreSession` is a startup boolean that restores saved tab
state; it is not a deep-link session selector. The workspace route asks for
confirmation and may open a draft. It cannot replace exact conversation focus.

Validation: `swift build --product OpenIslandApp` passed. An isolated temporary package using the actual controller and test file passed all 8 tests with CLT Testing framework flags and cross-import overlays disabled; the package was removed afterward. The ordinary full-package test entry stopped at the existing CLT `Testing` / `_Testing_Foundation` module issue. No app, source task or GUI was launched for this check.
