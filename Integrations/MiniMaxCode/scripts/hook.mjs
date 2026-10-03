#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { projectHook, readBoundedInput, sendOnce } from './core.mjs';

// config.json is written only by the reviewed installer, inside this plugin.
// Safe-env hooks do not propagate AIsland paths or original terminal metadata.
try {
  const config = JSON.parse(await readFile(new URL('../config.json', import.meta.url), 'utf8'));
  const input = await readBoundedInput(process.stdin);
  const message = projectHook(input, config);
  if (message) await sendOnce(message, config);
} catch { /* Fail open. No input, private error body, or decision is printed. */ }
