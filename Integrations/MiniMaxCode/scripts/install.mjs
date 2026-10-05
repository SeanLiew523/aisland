#!/usr/bin/env node
import { supportsDesktopVersion } from './core.mjs';
import { mkdir, readdir, lstat, writeFile, rename, rm, mkdtemp, access, chmod, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildPlan, owner, installedFiles, regularFile, regularDirectory, maybeStat, renderedFiles, digest, jsonBytes } from '../plan.mjs';
const runFile = promisify(execFile);
const hashValue = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
async function inventory(root, allowed) {
  await regularDirectory(root);
  const result = [];
  async function visit(path) {
    for (const name of (await readdir(path)).sort()) {
      const absolute = join(path, name); const info = await lstat(absolute); const key = relative(root, absolute);
      if (!allowed.includes(info.isDirectory() ? key + '/' : key)) throw new Error('Unexpected files in owned installation');
      if (info.isDirectory()) { result.push(key + '/'); await visit(absolute); }
      else if (info.isFile()) result.push(key);
      else throw new Error('Owned path is not a regular file/directory');
    }
  }
  await visit(root); return result.sort();
}
const expectedPluginInventory = [...installedFiles, '.minimax-plugin/', 'hooks/', 'scripts/'].sort();
async function validateContent(plan, receipt, pluginRoot = plan.destination, helperRoot = plan.helperDirectory) {
  if ((await inventory(pluginRoot, expectedPluginInventory)).join('\n') !== expectedPluginInventory.join('\n')
      || (await inventory(helperRoot, ['receipt.json', 'source-probe'])).join('\n') !== ['receipt.json', 'source-probe'].join('\n')) throw new Error('Unexpected files in owned installation');
  for (const path of installedFiles) if (digest(await regularFile(join(pluginRoot, path))) !== receipt.files[path]) throw new Error('Owned plugin file changed: ' + path);
  if (digest(await regularFile(join(helperRoot, 'source-probe'), 4 * 1024 * 1024)) !== receipt.helperHash) throw new Error('Owned helper changed');
  if (JSON.stringify(JSON.parse(await regularFile(join(helperRoot, 'receipt.json'), 65536))) !== JSON.stringify(receipt)) throw new Error('Receipt changed');
  await access(join(helperRoot, 'source-probe'), constants.X_OK);
}
export async function inspectOwnership(plan) {
  const destination = await maybeStat(plan.destination);
  const newHelper = await maybeStat(plan.helperDirectory);
  const helperDirectory = !newHelper && destination && plan.previousHelperDirectory ? plan.previousHelperDirectory : plan.helperDirectory;
  const helper = await maybeStat(helperDirectory);
  if (!destination && !helper) return null;
  if (!destination?.isDirectory() || !helper?.isDirectory()) throw new Error('Refusing unrecorded or partial existing installation');
  const receipt = JSON.parse(await regularFile(join(helperDirectory, 'receipt.json'), 65536));
  if (receipt.schemaVersion !== 1 || receipt.owner !== owner || receipt.dataDir !== plan.dataDir
      || receipt.destination !== plan.destination || receipt.helperDirectory !== helperDirectory || receipt.helperPath !== join(helperDirectory, 'source-probe')
      || !receipt.files || Array.isArray(receipt.files) || typeof receipt.files !== 'object'
      || Object.keys(receipt.files).sort().join('\n') !== [...installedFiles].sort().join('\n')
      || !Object.values(receipt.files).every(hashValue) || !hashValue(receipt.helperHash) || !hashValue(receipt.helperSourceHash)) throw new Error('Invalid owned receipt or path boundary');
  await validateContent(plan, receipt, plan.destination, helperDirectory);
  // A caller-provided previous path alone proves nothing. The current owned
  // plugin must itself point to exactly this receipt-validated helper.
  if (helperDirectory !== plan.helperDirectory) {
    const config = JSON.parse(await regularFile(join(plan.destination, 'config.json')));
    if (config.sourceDiscovery?.probePath !== receipt.helperPath) throw new Error('Previous helper does not match the owned plugin');
  }
  return receipt;
}
async function preflight(helperPath, plan) {
  const { stdout } = await runFile(helperPath, [String(process.pid), plan.config.sourceDiscovery.desktopAppPath], { timeout: 5000, maxBuffer: 16384 });
  const result = JSON.parse(stdout);
  if (result.schemaVersion !== 1 || result.ancestors?.[0]?.pid !== process.pid) throw new Error('Helper own-PID preflight failed');
  if (typeof result.desktopApp?.path !== 'string' || await realpath(result.desktopApp.path) !== plan.config.sourceDiscovery.desktopAppPath) throw new Error('Helper app-path preflight failed');
  if (result.desktopApp?.bundleID !== 'com.minimax.agent' || !supportsDesktopVersion(result.desktopApp?.version)) throw new Error('Helper bundle-version preflight failed');
  await runFile(helperPath, [String(process.pid), plan.config.sourceDiscovery.desktopAppPath], { timeout: 200, maxBuffer: 16384 });
}
function sameInstallation(plan, receipt) {
  return receipt && receipt.helperDirectory === plan.helperDirectory && receipt.helperSourceHash === plan.helperSourceHash
    && (plan.helperBuild.kind !== 'copy-bundled' || receipt.helperHash === plan.helperBuild.bundledProbeHash)
    && installedFiles.every(path => receipt.files[path] === plan.fileHashes[path]);
}
async function stageInstall(plan, stage) {
  const plugin = join(stage, 'plugin'); const helperDirectory = join(stage, 'helper'); const helper = join(helperDirectory, 'source-probe');
  await mkdir(plugin); await mkdir(helperDirectory);
  const files = await renderedFiles(plan);
  for (const [path, bytes] of Object.entries(files)) {
    if (digest(bytes) !== plan.fileHashes[path]) throw new Error('Package changed during preparation');
    await mkdir(dirname(join(plugin, path)), { recursive: true });
    await writeFile(join(plugin, path), bytes, { flag: 'wx', mode: path === 'config.json' ? 0o600 : 0o644 });
  }
  if (digest(await regularFile(plan.helperBuild.source)) !== plan.helperSourceHash) throw new Error('Helper source changed during preparation');
  if (plan.helperBuild.kind === 'copy-bundled') {
    const bytes = await regularFile(plan.helperBuild.bundledProbePath, 4 * 1024 * 1024);
    if (digest(bytes) !== plan.helperBuild.bundledProbeHash) throw new Error('Bundled probe changed during preparation');
    await writeFile(helper, bytes, { flag: 'wx', mode: 0o700 });
    if (digest(await regularFile(plan.helperBuild.bundledProbePath, 4 * 1024 * 1024)) !== plan.helperBuild.bundledProbeHash) throw new Error('Bundled probe changed during copy');
  } else {
    await runFile('/usr/bin/swiftc', ['-O', plan.helperBuild.source, '-o', helper], { timeout: 30000, maxBuffer: 16384 });
  }
  if (digest(await regularFile(plan.helperBuild.source)) !== plan.helperSourceHash) throw new Error('Helper source changed during compilation');
  await chmod(helper, 0o700);
  await preflight(helper, plan);
  const receipt = { schemaVersion: 1, owner, installedAt: new Date().toISOString(), dataDir: plan.dataDir,
    destination: plan.destination, helperDirectory: plan.helperDirectory, helperPath: plan.helperPath,
    files: plan.fileHashes, helperHash: digest(await regularFile(helper, 4 * 1024 * 1024)), helperSourceHash: plan.helperSourceHash };
  await writeFile(join(helperDirectory, 'receipt.json'), jsonBytes(receipt), { flag: 'wx', mode: 0o600 });
  return { plugin, helperDirectory, receipt };
}
async function publish(plan, staged, stage, previous) {
  const moved = [];
  try {
    // Verify ownership again immediately before the reversible rename transaction.
    const confirmed = await inspectOwnership(plan);
    if (JSON.stringify(confirmed) !== JSON.stringify(previous)) throw new Error('Installation changed during preparation');
    const plugins = join(plan.dataDir, 'plugins'); await mkdir(plugins, { recursive: true }); await regularDirectory(plugins);
    if (previous) {
      await rename(plan.destination, join(stage, 'previous-plugin')); moved.push([join(stage, 'previous-plugin'), plan.destination]);
      if (previous.helperDirectory === plan.helperDirectory) {
        await rename(plan.helperDirectory, join(stage, 'previous-helper')); moved.push([join(stage, 'previous-helper'), plan.helperDirectory]);
      } // Relocation preserves the complete previous helper tree unchanged.
    }
    await rename(staged.plugin, plan.destination); moved.push([plan.destination, staged.plugin]);
    await rename(staged.helperDirectory, plan.helperDirectory); moved.push([plan.helperDirectory, staged.helperDirectory]);
    await preflight(plan.helperPath, plan);
    await inspectOwnership(plan);
  } catch (error) {
    try { for (const [from, to] of moved.reverse()) await rename(from, to); }
    catch { error.preserveStage = true; error.message += '; recovery files preserved at ' + stage; }
    // Preserve a staged tree if content changed during publishing, even after rollback.
    if (moved.length > 0 && !error.preserveStage) {
      try { await validateContent(plan, staged.receipt, staged.plugin, staged.helperDirectory); }
      catch { error.preserveStage = true; error.message += '; changed files preserved at ' + stage; }
    }
    throw error;
  }
}
async function removeOwned(plan) {
  const previous = await inspectOwnership(plan);
  if (!previous) return { ...plan, mode: 'applied', result: 'already-absent' };
  const stage = await mkdtemp(join(plan.supportDir, '.aisland-minimaxcode-remove-'));
  const moved = [];
  try {
    const confirmed = await inspectOwnership(plan);
    if (JSON.stringify(confirmed) !== JSON.stringify(previous)) throw new Error('Installation changed before removal');
    await rename(plan.destination, join(stage, 'plugin')); moved.push([join(stage, 'plugin'), plan.destination]);
    await rename(plan.helperDirectory, join(stage, 'helper')); moved.push([join(stage, 'helper'), plan.helperDirectory]);
    await validateContent(plan, previous, join(stage, 'plugin'), join(stage, 'helper'));
  } catch (error) {
    try { for (const [from, to] of moved.reverse()) await rename(from, to); }
    catch { error.preserveStage = true; error.message += '; recovery files preserved at ' + stage; }
    if (!error.preserveStage) await rm(stage, { recursive: true, force: false });
    throw error;
  }
  // Only this invocation's staging tree contains the receipt-verified owned files.
  await rm(stage, { recursive: true, force: false });
  return { ...plan, mode: 'applied', result: 'removed', removedReceipt: previous };
}
export async function executeRequest(request = {}) {
  if (request.apply !== undefined && typeof request.apply !== 'boolean') throw new Error('apply must be an explicit boolean');
  const plan = await buildPlan(request); const receipt = await inspectOwnership(plan);
  const action = plan.operation === 'remove' ? (receipt ? 'remove-owned' : 'already-absent')
    : sameInstallation(plan, receipt) ? 'already-installed' : receipt ? 'replace-owned' : 'install-new';
  if (request.apply !== true) return { ...plan, action, existingReceipt: receipt, mode: 'dry-run-only' };
  if (plan.operation === 'remove') return await removeOwned(plan);
  if (action === 'already-installed') return { ...plan, action, mode: 'applied', result: action, receipt };
  await mkdir(plan.supportDir, { recursive: false }).catch(async error => { if (error.code !== 'EEXIST') throw error; await regularDirectory(plan.supportDir); });
  const stage = await mkdtemp(join(plan.supportDir, '.aisland-minimaxcode-install-'));
  let preserveStage = false;
  try {
    const staged = await stageInstall(plan, stage);
    await publish(plan, staged, stage, receipt);
    return { ...plan, action, mode: 'applied', result: 'installed', receipt: staged.receipt };
  } catch (error) { preserveStage = error.preserveStage === true; throw error; }
  finally { if (!preserveStage) await rm(stage, { recursive: true, force: false }); }
}
// Native bundle URLs can contain /tmp aliases or directory symlinks while
// Node resolves import.meta.url to the canonical module path.
if (process.argv[1] && await realpath(process.argv[1]).catch(() => null) === fileURLToPath(import.meta.url)) {
  try { process.stdout.write(JSON.stringify(await executeRequest(JSON.parse(process.argv[2] || '{}')), null, 2) + '\n'); }
  catch (error) { process.stderr.write(error.message + '\n'); process.exitCode = 1; }
}
