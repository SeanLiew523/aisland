// Open Island plugin for OpenCode
// Bridges OpenCode events to the Open Island desktop app via Unix socket.
// Install: copy to ~/.config/opencode/plugins/open-island.js
import { connect } from "net";
import { appendFileSync } from "fs";
import { execFileSync } from "child_process";
import { performance } from "perf_hooks";
import { homedir } from "os";

const DEBUG_LOG = "/tmp/open-island-opencode-debug.log";
function productionDebugLog(msg) {
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

function encodeEnvelope(command) {
  return JSON.stringify({ type: "command", command }) + "\n";
}

function sendToSocket(json, socketPath) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: socketPath }, () => {
        sock.end(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => { buf += chunk.toString(); });
      sock.on("end", () => { resolve(true); });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });
}

function sendAndWaitResponse(json, socketPath, timeoutMs = 300000) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: socketPath }, () => {
        sock.write(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => {
        buf += chunk.toString();
        // BridgeServer sends hello first, then response after processing
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          sock.destroy();
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        }
      });
      sock.on("end", () => {
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        } else {
          resolve(null);
        }
      });
      sock.on("error", () => resolve(null));
      sock.setTimeout(timeoutMs, () => { sock.destroy(); resolve(null); });
    } catch { resolve(null); }
  });
}

// Match RuntimeTTYProbe: self plus at most seven real ancestors, bounded in
// total and per process. Never read inherited TTY or shell session IDs as TTY.
function detectTTY(startPID, runProcess, now) {
  const deadline = now() + 1500;
  const visited = new Set();
  let pid = startPID;
  for (let depth = 0; depth < 8; depth++) {
    if (!Number.isInteger(pid) || pid <= 1 || pid > 2147483647 || visited.has(pid)) return;
    visited.add(pid);
    const remaining = deadline - now();
    if (remaining < 1) return;
    let raw;
    try {
      raw = runProcess("/bin/ps", ["-p", String(pid), "-o", "pid=,ppid=,tty="], {
        timeout: Math.min(200, Math.floor(remaining)), killSignal: "SIGKILL",
        maxBuffer: 1024, stdio: ["ignore", "pipe", "ignore"],
      }).toString();
    } catch { return; }
    if (now() > deadline || Buffer.byteLength(raw) > 1024) return;
    const row = raw.trim();
    // One complete row, numeric PID/PPID and no extra output or PID mismatch.
    const fields = /^([0-9]+)[ \t]+([0-9]+)[ \t]+(\S+)$/.exec(row);
    if (!fields || Number(fields[1]) !== pid) return;
    const parent = Number(fields[2]);
    if (!Number.isInteger(parent) || parent > 2147483647) return;
    const tty = fields[3];
    if (["?", "??", "-"].includes(tty)) { pid = parent; continue; }
    const value = tty.startsWith("/dev/") ? tty.slice(5) : tty;
    if (!/^tty[A-Za-z0-9_.-]+$/.test(value) || Buffer.byteLength(value) > 123 || value.includes("..")) return;
    return `/dev/${value}`;
  }
}

const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
  "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
  "ZELLIJ", "ZELLIJ_PANE_ID", "ZELLIJ_SESSION_NAME",
];

function terminalFields(env, detectedTty) {
  const result = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.ZELLIJ != null) {
    result.terminal_app = "Zellij";
    const paneID = env.ZELLIJ_PANE_ID || "";
    const sessionName = env.ZELLIJ_SESSION_NAME || "";
    if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
  } else if ((env.TERM_PROGRAM || "").toLowerCase().includes("ghostty") || (!env.TERM_PROGRAM && env.GHOSTTY_RESOURCES_DIR)) {
    result.terminal_app = "Ghostty";
    // This server plugin has no trusted native TUI session/source contract.
    // API/session/message events cannot select a surface. Fail closed instead
    // of consuming a startup snapshot or trusting inherited environment IDs.
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  if (detectedTty) result.terminal_tty = detectedTty;
  return result;
}

function normalizeQuestionOption(option) {
  if (typeof option === "string") {
    return { label: option };
  }
  if (!option || typeof option !== "object") {
    return null;
  }

  const label = option.label || option.text || option.value || option.name;
  if (!label) return null;

  return {
    label: String(label),
    description: option.description || option.hint || option.detail || "",
    allows_freeform: Boolean(option.allowsFreeform || option.allows_freeform),
  };
}

function normalizeQuestion(question, index) {
  if (!question || typeof question !== "object") {
    return null;
  }

  const questionText = question.question || question.title || question.prompt;
  if (!questionText) return null;

  const options = Array.isArray(question.options)
    ? question.options.map(normalizeQuestionOption).filter(Boolean)
    : [];
  if (options.length === 0) return null;

  return {
    question: String(questionText),
    header: question.header || question.label || `Question ${index + 1}`,
    options,
    multi_select: Boolean(question.multiSelect || question.multi_select),
  };
}

// Keep only the default export: OpenCode 1.1.53 loads every module export as
// a plugin. Optional dependencies let fixtures exercise the production path.
export default async ({ client, serverUrl }, dependencies = {}) => {
  const environment = dependencies.environment || process.env;
  const detectedTty = detectTTY(dependencies.pid ?? process.pid,
    dependencies.runProcess || execFileSync, dependencies.now || (() => performance.now()));
  const debugLog = dependencies.debugLog || productionDebugLog;
  const socketPath = environment.OPEN_ISLAND_SOCKET_PATH ||
    `${environment.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
  const send = dependencies.sendCommand || (json => sendToSocket(json, socketPath));
  const sendResponse = dependencies.sendAndWaitResponse || (json => sendAndWaitResponse(json, socketPath));
  function makePayload(hookEventName, sessionID, cwd, extra = {}) {
    return {
      type: "processOpenCodeHook",
      openCodeHook: {
        hook_event_name: hookEventName,
        session_id: `opencode-${sessionID}`,
        cwd: cwd || ".",
        ...terminalFields(environment, detectedTty),
        ...extra,
      },
    };
  }

  const serverPort = serverUrl ? parseInt(serverUrl.port) || 4096 : 4096;
  const internalFetch = client?._client?.getConfig?.()?.fetch || null;
  const msgRoles = new Map();
  const sessionCwd = new Map();
  const sessions = new Map();

  function getSession(sid) {
    if (!sessions.has(sid)) sessions.set(sid, { lastAssistantText: "" });
    return sessions.get(sid);
  }

  function mapEvent(ev) {
    const t = ev.type;
    const p = ev.properties || {};

    // session.created
    if (t === "session.created" && p.info) {
      const cwd = p.info.directory || "";
      sessionCwd.set(p.info.id, cwd);
      return makePayload("SessionStart", p.info.id, cwd);
    }

    // session.deleted
    if (t === "session.deleted" && p.info) {
      sessions.delete(p.info.id);
      sessionCwd.delete(p.info.id);
      return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
    }

    // session.updated (archived)
    if (t === "session.updated" && p.info) {
      if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
      if (p.info.time?.archived) {
        sessions.delete(p.info.id);
        sessionCwd.delete(p.info.id);
        return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
      }
      return null;
    }

    // session.status → idle = Stop (busy is ignored; session creation
    // comes from session.created or ensureOpenCodeSessionExists on first event)
    if (t === "session.status" && p.sessionID) {
      if (p.status?.type === "idle") {
        const s = getSession(p.sessionID);
        return makePayload("Stop", p.sessionID, sessionCwd.get(p.sessionID), {
          last_assistant_message: s.lastAssistantText || undefined,
        });
      }
      return null;
    }

    // message.updated — track role for message parts
    if (t === "message.updated" && p.info?.id && p.info?.sessionID) {
      msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID });
      if (msgRoles.size > 200) { msgRoles.delete(msgRoles.keys().next().value); }
      return null;
    }

    // message.part.updated — text
    if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
      const meta = msgRoles.get(p.part.messageID);
      if (!meta) return null;
      const text = p.part.text || "";
      if (meta.role === "user" && text) {
        return makePayload("UserPromptSubmit", meta.sessionID, sessionCwd.get(meta.sessionID), {
          prompt: text,
        });
      }
      if (meta.role === "assistant" && text) {
        getSession(meta.sessionID).lastAssistantText = text;
      }
      return null;
    }

    // message.part.updated — tool
    if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
      const st = p.part.state?.status;
      const cwd = sessionCwd.get(p.part.sessionID);
      const toolName = (p.part.tool || "").charAt(0).toUpperCase() + (p.part.tool || "").slice(1);
      if (st === "running" || st === "pending") {
        return makePayload("PreToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
          tool_input: typeof p.part.state?.input === "string"
            ? p.part.state.input
            : JSON.stringify(p.part.state?.input || {}).slice(0, 200),
        });
      }
      if (st === "completed" || st === "error") {
        return makePayload("PostToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
        });
      }
      return null;
    }

    // permission.asked
    if (t === "permission.asked" && p.id && p.sessionID) {
      const toolName = (p.permission || "").charAt(0).toUpperCase() + (p.permission || "").slice(1);
      const patterns = p.patterns || [];
      const toolInput = { patterns, metadata: p.metadata };
      if (p.permission === "bash" && patterns.length > 0) {
        toolInput.command = patterns.join(" && ");
      }
      if ((p.permission === "edit" || p.permission === "write") && patterns.length > 0) {
        toolInput.file_path = patterns[0];
      }
      return makePayload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
        tool_name: toolName,
        tool_input: JSON.stringify(toolInput).slice(0, 200),
        permission_id: p.id,
        permission_title: `Allow ${toolName}`,
        permission_description: patterns.length > 0
          ? `OpenCode wants to run ${toolName}: ${patterns[0]}`
          : `OpenCode wants to run ${toolName}`,
        _opencode_request_id: p.id,
      });
    }

    // permission.replied
    if (t === "permission.replied" && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    // question.asked
    if (t === "question.asked" && p.id && p.sessionID) {
      const questions = Array.isArray(p.questions)
        ? p.questions.map(normalizeQuestion).filter(Boolean)
        : [];
      return makePayload("QuestionAsked", p.sessionID, sessionCwd.get(p.sessionID), {
        question_id: p.id,
        question_text: (p.questions || []).map(q => q.question).join("; ") || "OpenCode has a question",
        questions,
        _opencode_request_id: p.id,
      });
    }

    // question.replied / question.rejected
    if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    return null;
  }

  return {
    "event": async ({ event }) => {
      try {
        debugLog(`EVENT: ${event.type} | props: ${JSON.stringify(event.properties || {}).slice(0, 300)}`);
        const mapped = mapEvent(event);
        if (mapped) {
          debugLog(`MAPPED: ${mapped.openCodeHook.hook_event_name} sid=${mapped.openCodeHook.session_id}`);
        }
        if (!mapped) return;

        // Permission request — hold connection for approval
        if (mapped.openCodeHook.hook_event_name === "PermissionRequest" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            const reply = directive.type === "allow" ? "once" : "reject";
            const message = directive.type === "deny" ? directive.reason : undefined;
            try {
              await internalFetch(new Request(`http://localhost:${serverPort}/permission/${requestId}/reply`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ reply, message }),
              }));
            } catch {}
          });
          return;
        }

        // Question — hold connection for answer
        if (mapped.openCodeHook.hook_event_name === "QuestionAsked" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            if (directive.type === "answer") {
              try {
                await internalFetch(new Request(`http://localhost:${serverPort}/question/${requestId}/reply`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ answers: [[directive.text]] }),
                }));
              } catch {}
            }
          });
          return;
        }

        // Regular events — fire and forget
        await send(mapped);
      } catch {
        // Fail open: if Open Island is unavailable, don't block OpenCode
      }
    },

    "shell.env": async (input, output) => {
      output.env.OPEN_ISLAND_ACTIVE = "1";
      for (const v of ENV_KEYS) {
        if (environment[v]) output.env["_OI_" + v] = environment[v];
      }
    },
  };
};
