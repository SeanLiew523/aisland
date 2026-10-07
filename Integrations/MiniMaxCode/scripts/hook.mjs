#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { projectHook, readBoundedInput, sendOnce } from './core.mjs';
import { resolveSource } from './source.mjs';

// config.json is written only by the reviewed installer, inside this plugin.
// Safe-env hooks do not propagate AIsland paths or original terminal metadata.
try {
  const config = JSON.parse(await readFile(new URL('../config.json', import.meta.url), 'utf8'));
  const input = await readBoundedInput(process.stdin);
  const source = await resolveSource(config);
  if (source) {
    const resolvedConfig = { ...config, ...source };
    const message = projectHook(input, resolvedConfig);
    if (message) {
      const metadata = message.command.runtimeLifecycleHook;
      if (source.terminalTTY) metadata.terminal_tty = source.terminalTTY;
      if (source.terminalApp) metadata.terminal_app = source.terminalApp;
      await sendOnce(message, resolvedConfig);
    }
  }
} catch { /* Fail open. No input, private error body, or decision is printed. */ }
