#!/usr/bin/env node
// Print a reviewable plan only. Never executes the CLI or mutates a profile.
import { readFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const directory = realpathSync(process.argv[2] || dirname(fileURLToPath(import.meta.url)));
const manifest = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
if (manifest.name !== '@aisland/deepseek-harness-plugin' || manifest.dsh?.bundle?.patch !== './cordis.patch.yml' || manifest.exports?.['./client'] !== './client.js') throw new Error('Unexpected plugin manifest');
for (const name of ['index.mjs', 'core.mjs', 'client.js', 'cordis.patch.yml']) readFileSync(join(directory, name));
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const cli = quote('/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh');
console.log([
  'DRY RUN ONLY — no commands executed and no profile inspected or changed.',
  'Before installation/removal: initialize Desktop once, then fully quit Desktop.',
  'Record/backup the existing desktop profile package.json, user patch and pnpm lock/workspace files first.',
  `List: ${cli} plugin --profile desktop list`,
  `Install: ${cli} plugin --profile desktop add ${quote(directory)}`,
  `Remove: ${cli} plugin --profile desktop remove ${quote(manifest.name)}`,
  'After the command completes, reopen Desktop for the changed plugin composition.',
].join('\n'));
