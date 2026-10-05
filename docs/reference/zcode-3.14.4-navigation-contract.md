# ZCode 3.14.4 exact task navigation

This adapter is admitted only for `dev.zcode.app` version `3.14.4`. The installed application's public ASAR renderer was inspected without reading user data or operating the UI. Its `styles-Qlp0Bew7.js` SHA256 is `cf12a79272be1de9fcd35bf2299e388ec33495f315363e89a92108bd67768ad4` (offsets below are UTF-8 byte offsets).

- `j3` (4400529): normal sidebar rows are focusable `li.group/task-item`, with `onClick` and self-targeted Enter/Space handlers selecting their task ID. They do not declare `role=button`.
- `Can` (4450870): grouped rows are `div.group/task-row`, `role=button`, `tabIndex=0`, with the same self-targeted Enter/Space behavior. Selection calls `onSelectTask(workspacePath, taskId, workspaceIdentity)`. Both variants use `bg-selected`.
- `e7t` (4120896): the current task header's More button (`data-testid=workspace-more-button`, aria-label `更多` / `More`) opens a menu containing `复制会话 ID` / `Copy session ID`. Its callback (4129654) passes the header's `activeSessionId` to `M2.handleCopyText`. `M2` (4092670) calls `navigator.clipboard.writeText`; this callback does not share, publish, or invoke an external API. The renderer also logs the copied value itself; AIsland does not retain that value in diagnostics.
- `iEe` (692933): header identity comes from metadata for the selected task ID. Missing metadata is fetched with `readSession(sessionId: activeTaskId)`; `RTe` (687649) maps `session.sessionId` to `taskId`. While identity is absent, the copy item is disabled. Draft mode has no task menu.
- Sidebar context menus copy their row's task ID, which alone cannot establish current content. AIsland uses only the current header menu. The conversation pane separately carries `data-session-id` (3307027), but arbitrary DOM data attributes are not assumed to be accessible through macOS AX.

Navigation first resolves the native indexed title and one exact sidebar row, preferring AXPress. A plain row without AXPress may receive one Enter only after its own AX focus is observed, the focus attribute is settable, and the admitted source process is frontmost. No first-row, directory, or substring fallback exists. Grouped and normal rows are both recognized; their real AX representation still requires native acceptance.

After selection, success requires an exact native ID copied from the current header, restoration of the original clipboard, the selected exact row, unchanged source PID/version/window/foreground, and re-admission of indexed metadata. A generic “New task” heading is not independent identity evidence and does not block this stronger check. A missing/disabled copy item or any mismatch fails navigation.

The existing bounded clipboard transaction keeps original bytes in memory and restores only a stable, bounded value equal to the admitted ID. A concurrent foreign clipboard producer is preserved. An asynchronously dispatched copy gets at least 300 ms of cleanup observation, but a late result cannot count as successful navigation.

Fake source and private named-pasteboard tests cover identity mismatches, duplicates, selection failure, metadata rename, source PID/version/window/focus changes, and clipboard restoration/concurrent producers. No real ZCode UI or general clipboard was used during implementation. Native acceptance must verify row AX behavior, public menu AXPress dispatch, exact restored ID, and visible target content. The `zcode://workspace/open?path=...` URL only opens a workspace and is not a task-ID navigation contract.

2026-10-05 build 57 native retest: the existing owned task completed its new
marker, and clicking its island card from an empty draft selected the exact
body. Current-ID verification returned unavailable. The real header More
control is an AXPopUpButton; the implementation had admitted only AXButton.
The role policy now admits these two button roles while retaining one exact
header ancestor, exact label and AXPress requirements. The public menu was
observed to contain Copy session ID, then closed without copying. This is a
specific live compatibility repair; a new complete-bundle return still must
prove copied-ID and clipboard/foreground validation.

Build 58's native More button opened its menu, but current-ID verification
still failed and left the menu visible. That observation does not establish
whether AX labels, item role/actions/enabled state, or the shared three-second
deadline caused the miss. The installed renderer hash was rechecked unchanged;
it proves the intended callback, not Chromium's current AX attribute mapping.

The adapter now matches the exact public copy label independently in AXValue,
AXTitle and AXDescription, so an empty value cannot mask a title. It admits one
AXMenu that appears only after its own uniquely scoped header press; the copy
item must belong to that menu and retain AXMenuItem, AXPress and enabled=true.
A pre-existing or ambiguous menu fails. A small portion of the original deadline
is reserved for AXCancel on the same menu if copy was not dispatched; cancellation
requires the same PID/version/frontmost/window and freshly unique menu. It never
sends global Escape or extends navigation for menu cleanup. The existing late
clipboard cleanup allowance and exact-ID restoration remain unchanged.

The existing opt-in regular-file marker also emits one bounded copy-stage line.
Fields use fixed stage/reason enums, counts, allowed roles, exact-label match
booleans for each attribute, press/enabled and menu-budget/deadline/cancel booleans, plus the
target hash. Menu labels, body, clipboard bytes and raw IDs are never logged.
These fields are intended to distinguish live compatibility failures; successful
isolated tests are not native acceptance.

Verification: the actual production controller and pasteboard implementation
compiled in a temporary minimal macOS 14 package using scripts/test-clt.sh,
with Swift cross-import overlays disabled. All 24 tests in the two committed
ZCode suites passed. Tests use a fixture SQLite index and a unique named
pasteboard; no production GUI, source user data, or general clipboard is read.
The temporary package is removed after verification. A complete bundle and
native ZCode return-click verification remain the next acceptance step.

Build 59 native retest established the copy path: the unique menu's exact item
label came from AXTitle, AXMenuItem/AXPress/enabled admission succeeded, the
native session ID matched, and the original clipboard was restored. The
remaining failure was selectedRowUnverified while the menu had not yet finished
closing; a subsequent native observation showed the owned target body and no
menu. The adapter therefore waits after its one restored exact copy for the
menu to disappear and the unique exact row to be selected, using the original
total focus deadline. Every poll keeps the same PID/version/frontmost/window;
ready state rechecks indexed metadata and the context after the AX queries.
The wait neither copies again nor reads/writes the clipboard. Timeout, duplicate
or wrong/unselected rows, or changed source/window/index still reject success.

Follow-up verification: the same temporary CLT package compiled the actual
controller, pasteboard implementation and both ZCode suites; all 29 tests
passed. New gate fixtures cover delayed menu/body recovery, open-menu/wrong/
duplicate/unselected rows, original-deadline expiry, context/index changes,
sampling that exhausts the deadline, and mismatched ID/unrestored clipboard.
A focus fixture dispatched exactly one copy and confirmed the private named
pasteboard remained restored throughout identity waiting. The temporary package
was removed. Native acceptance remains pending the next complete-bundle click.
