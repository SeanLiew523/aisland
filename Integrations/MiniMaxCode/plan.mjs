#!/usr/bin/env node
// Emits reviewable install/remove inputs. Never inspects or changes source profiles.
import { readFile, realpath, stat } from 'node:fs/promises';
import { dirname, join, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validConfig } from './scripts/core.mjs';

export async function buildPlan({ source = 'minimaxCodeDesktop', profileID = 'desktop', dataDir,
  bridgeSocketPath, nodePath, desktopVerified = false }) {
  if (source === 'minimaxCodeCLI' && !desktopVerified) throw new Error('Desktop runtime verification must precede CLI installation');
  if (![dataDir, nodePath].every(value => typeof value === 'string' && isAbsolute(value) && !/[\x00-\x1f\x7f]/.test(value))) throw new Error('Absolute data and Node paths required');
  const config = { schemaVersion: 1, source, sourceRuntimeVersion: source === 'minimaxCodeDesktop' ? '3.1.0' : '0.5.3',
    profileID, bridgeSocketPath, metadataDatabasePath: join(dataDir, 'v2/sqlite/runtime-state.sqlite'), bridgeTimeoutMs: 150 };
  if (!validConfig(config)) throw new Error('Invalid source configuration');
  const packageRoot = await realpath(dirname(fileURLToPath(import.meta.url)));
  const manifest = JSON.parse(await readFile(join(packageRoot, '.minimax-plugin/plugin.json'), 'utf8'));
  const hooks = JSON.parse(await readFile(join(packageRoot, 'hooks/hooks.json'), 'utf8'));
  for (const path of ['scripts/core.mjs', 'scripts/hook.mjs', 'icon.png']) if (!(await stat(join(packageRoot, path))).isFile()) throw new Error('Missing package file');
  // Render one quoted absolute interpreter. Plugin-root expansion is native hook syntax.
  const quotedNode = '"' + nodePath.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('$', '\\$').replaceAll('`', '\\`') + '"';
  for (const groups of Object.values(hooks.hooks)) for (const group of groups) for (const handler of group.hooks) handler.command = `${quotedNode} "\${PLUGIN_ROOT}/scripts/hook.mjs"`;
  return { schemaVersion: 1, mode: 'dry-run-only', source, packageRoot,
    destination: join(dataDir, 'plugins', manifest.name), config, manifest, hooks,
    copyFiles: ['.minimax-plugin/plugin.json', 'hooks/hooks.json', 'scripts/core.mjs', 'scripts/hook.mjs', 'icon.png'],
    beforeInstall: ['Confirm installed source version and the actual active dataDir.', 'Verify the chosen Node executable without launching MiniMaxCode.',
      'Refuse existing destination unless the exact owned installation and backup are recorded.', 'Copy regular files only; preserve all other plugins and permissions.',
      'Write reviewed config.json and rendered hooks.json; let local watcher rescan, then explicitly enable this plugin in the source UI.'],
    uninstall: ['Disable only aisland-minimaxcode-passive in the source UI.', 'Remove only the recorded owned plugin directory; restore its previous backup if one existed.',
      'Remove only AIsland-owned metadata registry entries. Do not edit or delete source databases.'],
    runtimeGate: 'Source recognition, event delivery, native committed results and exact navigation must be verified live.' };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const request = JSON.parse(process.argv[2] || '{}');
    process.stdout.write(JSON.stringify(await buildPlan(request), null, 2) + '\n');
  } catch { process.stderr.write('Invalid or incomplete install plan inputs. No changes made.\n'); process.exitCode = 1; }
}
