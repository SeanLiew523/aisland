#!/usr/bin/env node
import { access, realpath, lstat, open } from 'node:fs/promises';
import { constants } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, join, isAbsolute, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { validConfig, supportsDesktopVersion } from './scripts/core.mjs';
import { validDiscovery } from './scripts/source.mjs';
const runFile = promisify(execFile);
export const pluginName = 'aisland-minimaxcode-passive';
export const owner = 'aisland.minimaxcode-passive.installer';
export const packageRoot = dirname(fileURLToPath(import.meta.url));
export const copyFiles = ['.minimax-plugin/plugin.json', 'hooks/hooks.json', 'scripts/core.mjs', 'scripts/source.mjs', 'scripts/hook.mjs', 'icon.png'];
export const installedFiles = [...copyFiles, 'config.json'];
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export const jsonBytes = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');
const cleanPath = value => typeof value === 'string' && isAbsolute(value) && value === resolve(value) && value.length <= 4096 && !/[\x00-\x1f\x7f-\x9f]/.test(value);
export async function regularFile(path, limit = 1024 * 1024) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.size <= 0 || info.size > limit) throw new Error('Expected bounded regular file: ' + path);
    const bytes = Buffer.alloc(limit + 1); const { bytesRead } = await handle.read(bytes, 0, bytes.length, 0);
    if (bytesRead <= 0 || bytesRead > limit) throw new Error('File exceeded limit: ' + path);
    return bytes.subarray(0, bytesRead);
  } finally { await handle.close(); }
}
export async function maybeStat(path) {
  try { return await lstat(path); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
export async function regularDirectory(path) {
  if (!(await lstat(path)).isDirectory()) throw new Error('Expected regular directory: ' + path);
}
async function canonicalDirectory(path, mayCreate = false) {
  if (!cleanPath(path)) throw new Error('Absolute normalized directory required');
  const info = await maybeStat(path);
  if (info) { await regularDirectory(path); return await realpath(path); }
  if (!mayCreate) throw new Error('Required directory does not exist');
  await regularDirectory(dirname(path)); return join(await realpath(dirname(path)), basename(path));
}
export async function renderedFiles(plan) {
  const files = {};
  for (const path of copyFiles) files[path] = await regularFile(join(packageRoot, path));
  files['hooks/hooks.json'] = jsonBytes(plan.hooks);
  files['config.json'] = jsonBytes(plan.config);
  return files;
}
export async function buildPlan(request = {}) {
  const operation = request.operation ?? 'install';
  if (!['install', 'remove'].includes(operation) || request.dataDirConfirmed !== true) throw new Error('Explicit operation and confirmed active dataDir required');
  const dataDir = await canonicalDirectory(request.dataDir);
  const supportDir = await canonicalDirectory(request.supportDir, true);
  const destination = join(dataDir, 'plugins', pluginName);
  const helperDirectory = join(supportDir, 'minimaxcode-passive');
  const helperPath = join(helperDirectory, 'source-probe'); const receiptPath = join(helperDirectory, 'receipt.json');
  if (helperDirectory === destination || helperDirectory.startsWith(dataDir + '/') || dataDir.startsWith(helperDirectory + '/')) throw new Error('Helper must be outside the source data directory');
  const plugins = await maybeStat(join(dataDir, 'plugins'));
  if (plugins && !plugins.isDirectory()) throw new Error('Plugins parent is not a regular directory');
  const common = { schemaVersion: 1, mode: 'dry-run-only', operation, owner, dataDir, supportDir,
    packageRoot, destination, helperDirectory, helperPath, receiptPath,
    runtimeGate: 'UI enablement, actual session results and exact original navigation remain live acceptance checks.' };
  if (request.previousHelperDirectory !== undefined) {
    if (operation !== 'install') throw new Error('Previous helper is only admitted for owned installation relocation');
    const previous = await canonicalDirectory(request.previousHelperDirectory);
    if (basename(previous) !== 'minimaxcode-passive' || previous === helperDirectory || previous.startsWith(dataDir + '/') || dataDir.startsWith(previous + '/')
        || previous.startsWith(helperDirectory + '/') || helperDirectory.startsWith(previous + '/')) throw new Error('Invalid previous helper boundary');
    common.previousHelperDirectory = previous;
  }
  if (operation === 'remove') return common;
  const source = request.source ?? 'minimaxCodeDesktop';
  const enableCLI = request.enableCLI === true || source === 'minimaxCodeCLI';
  if (enableCLI && request.desktopVerified !== true) throw new Error('Desktop runtime verification must precede CLI installation');
  if (![request.nodePath, request.desktopAppPath, request.cliPrefix].every(cleanPath)) throw new Error('Absolute normalized Node, Desktop app and CLI prefix required');
  const nodePath = await realpath(request.nodePath);
  if (!(await lstat(nodePath)).isFile()) throw new Error('Node must be a regular executable');
  await access(nodePath, constants.X_OK);
  const hookRuntimeKind = request.hookRuntimeKind ?? 'node';
  if (!['node', 'minimaxDesktopElectron'].includes(hookRuntimeKind)) throw new Error('Unsupported hook runtime kind');
  if (hookRuntimeKind === 'node' && basename(nodePath) !== 'node') throw new Error('Node executable identity must be explicit');
  const desktopAppPath = await canonicalDirectory(request.desktopAppPath);
  if (!desktopAppPath.endsWith('.app')) throw new Error('Desktop app bundle required');
  const infoPath = join(desktopAppPath, 'Contents/Info.plist'); await regularFile(infoPath, 65536);
  const { stdout } = await runFile('/usr/bin/plutil', ['-convert', 'json', '-o', '-', infoPath], { timeout: 1000, maxBuffer: 65536 });
  const desktop = JSON.parse(stdout);
  if (desktop.CFBundleIdentifier !== 'com.minimax.agent' || !supportsDesktopVersion(desktop.CFBundleShortVersionString)) throw new Error('Unsupported Desktop bundle identity/version');
  if (hookRuntimeKind === 'minimaxDesktopElectron') {
    if (enableCLI || typeof desktop.CFBundleExecutable !== 'string' || !desktop.CFBundleExecutable || desktop.CFBundleExecutable.includes('/')) throw new Error('Desktop runtime requires the reviewed Desktop-only executable');
    const executable = join(desktopAppPath, 'Contents/MacOS', desktop.CFBundleExecutable);
    if (!(await lstat(executable)).isFile()) throw new Error('Desktop runtime must be a regular executable');
    await access(executable, constants.X_OK);
    if (await realpath(executable) !== nodePath) throw new Error('Desktop runtime executable identity mismatch');
    // Reviewed 3.1.0/3.1.1 RunAsNode fuse is independently verified. No GUI/task entry point.
    const { stdout: versions } = await runFile(nodePath, ['-p', 'JSON.stringify({node:process.versions.node,electron:process.versions.electron})'],
      { env: { PATH: '/usr/bin:/bin', LC_ALL: 'C', ELECTRON_RUN_AS_NODE: '1' }, timeout: 1000, maxBuffer: 4096 });
    const runtime = JSON.parse(versions);
    if (runtime.node !== '24.18.0' || runtime.electron !== '42.8.0') throw new Error('Unsupported Desktop embedded runtime version');
  }
  const cliPrefix = enableCLI ? await canonicalDirectory(request.cliPrefix) : request.cliPrefix;
  const cli = enableCLI ? JSON.parse(await regularFile(join(cliPrefix, 'lib/node_modules/@minimax-ai/code/package.json'), 65536)) : null;
  if (enableCLI && (cli.name !== '@minimax-ai/code' || cli.version !== '0.5.3')) throw new Error('Unsupported CLI package identity/version');
  const profileID = request.profileID ?? 'desktop'; const cliProfileID = request.cliProfileID ?? 'cli';
  const config = { schemaVersion: 1, source, sourceRuntimeVersion: source === 'minimaxCodeDesktop' ? desktop.CFBundleShortVersionString : cli.version,
    profileID, bridgeSocketPath: request.bridgeSocketPath, metadataDatabasePath: join(dataDir, 'v2/sqlite/runtime-state.sqlite'), bridgeTimeoutMs: 150,
    sourceDiscovery: { probePath: helperPath, desktopAppPath, cliPrefix, hookRuntimeKind, allowedSources: enableCLI ? ['minimaxCodeDesktop', 'minimaxCodeCLI'] : ['minimaxCodeDesktop'],
      profileIDs: { minimaxCodeDesktop: source === 'minimaxCodeDesktop' ? profileID : 'desktop', minimaxCodeCLI: source === 'minimaxCodeCLI' ? profileID : cliProfileID } } };
  if (!validConfig(config) || !validDiscovery(config)) throw new Error('Invalid source configuration');
  const manifest = JSON.parse(await regularFile(join(packageRoot, '.minimax-plugin/plugin.json')));
  if (manifest.name !== pluginName) throw new Error('Unexpected plugin identity');
  const hooks = JSON.parse(await regularFile(join(packageRoot, 'hooks/hooks.json')));
  const quotedNode = '"' + nodePath.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('$', '\\$').replaceAll('`', '\\`') + '"';
  for (const groups of Object.values(hooks.hooks)) for (const group of groups) for (const handler of group.hooks) handler.command = `${hookRuntimeKind === 'minimaxDesktopElectron' ? 'ELECTRON_RUN_AS_NODE=1 ' : ''}${quotedNode} "\${PLUGIN_ROOT}/scripts/hook.mjs"`;
  const plan = { ...common, source, nodePath, config, manifest, hooks, copyFiles,
    verifiedVersions: { desktop: desktop.CFBundleShortVersionString, cli: cli?.version ?? null },
    helperBuild: { kind: 'compile-source', source: join(packageRoot, 'scripts/source-probe.swift'), output: helperPath, compiler: '/usr/bin/swiftc', preflight: 'Own installer PID only; no source application launch.' },
    beforeInstall: ['Use apply:true only after reviewing this plan.', 'Refuse unknown destination/helper or changed owned hashes.', 'Enable only this plugin in source UI after installation.'],
    uninstall: ['Disable this plugin in source UI.', 'Validate receipt and every owned path/hash before removing.', 'Preserve source sessions, DB, plugin data and every unrelated file.'] };
  plan.fileHashes = Object.fromEntries(Object.entries(await renderedFiles(plan)).map(([path, bytes]) => [path, digest(bytes)]));
  plan.helperSourceHash = digest(await regularFile(plan.helperBuild.source));
  if (request.bundledProbePath !== undefined) {
    if (!cleanPath(request.bundledProbePath) || !/^[a-f0-9]{64}$/.test(request.bundledProbeHash ?? '')) throw new Error('Explicit bundled probe path/hash required');
    const bytes = await regularFile(request.bundledProbePath, 4 * 1024 * 1024);
    await access(request.bundledProbePath, constants.X_OK);
    if (digest(bytes) !== request.bundledProbeHash) throw new Error('Bundled probe hash mismatch');
    plan.helperBuild = { kind: 'copy-bundled', source: plan.helperBuild.source, bundledProbePath: request.bundledProbePath,
      bundledProbeHash: request.bundledProbeHash, output: helperPath, preflight: 'Own installer PID only; no source application launch.' };
  }
  return plan;
}
// Native bundle URLs can contain /tmp aliases or directory symlinks while
// Node resolves import.meta.url to the canonical module path.
if (process.argv[1] && await realpath(process.argv[1]).catch(() => null) === fileURLToPath(import.meta.url)) {
  try { const request = JSON.parse(process.argv[2] || '{}'); process.stdout.write(JSON.stringify(await buildPlan(request), null, 2) + '\n'); }
  catch (error) { process.stderr.write(error.message + '. No changes made.\n'); process.exitCode = 1; }
}
