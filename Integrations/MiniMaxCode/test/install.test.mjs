import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, readdir } from 'node:fs/promises';
import { existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { executeRequest, inspectOwnership } from '../scripts/install.mjs';
import { buildPlan, installedFiles } from '../plan.mjs';
const platform = { skip: process.platform !== 'darwin' };
async function fixture() {
  const directory = realpathSync(await mkdtemp(join(tmpdir(), 'aisland-minimax-install-test-')));
  const dataDir = join(directory, 'source'); const supportDir = join(directory, 'support');
  const desktopAppPath = join(directory, 'MiniMax Code.app'); const cliPrefix = join(directory, 'cli');
  await mkdir(dataDir); await mkdir(join(desktopAppPath, 'Contents/MacOS'), { recursive: true });
  await writeFile(join(desktopAppPath, 'Contents/MacOS/Fixture'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  await writeFile(join(desktopAppPath, 'Contents/Info.plist'), '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.minimax.agent</string><key>CFBundleShortVersionString</key><string>3.1.0</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleExecutable</key><string>Fixture</string><key>CFBundleName</key><string>Fixture</string></dict></plist>');
  await mkdir(join(cliPrefix, 'lib/node_modules/@minimax-ai/code'), { recursive: true });
  await writeFile(join(cliPrefix, 'lib/node_modules/@minimax-ai/code/package.json'), JSON.stringify({ name: '@minimax-ai/code', version: '0.5.3' }));
  const request = { dataDir, dataDirConfirmed: true, supportDir, desktopAppPath, cliPrefix, bridgeSocketPath: join(directory, 'bridge.sock'), nodePath: process.execPath, profileID: 'desktop-test', cliProfileID: 'cli-test' };
  return { directory, request, remove: async () => await rm(directory, { recursive: true, force: true }) };
}

test('Dry-run validates actual versions and emits full source proof configuration without writes', platform, async () => {
  const f = await fixture();
  try {
    const plan = await executeRequest(f.request);
    assert.equal(plan.mode, 'dry-run-only'); assert.equal(plan.action, 'install-new');
    assert.equal(existsSync(plan.destination), false); assert.equal(existsSync(plan.supportDir), false);
    assert.deepEqual(plan.config.sourceDiscovery.allowedSources, ['minimaxCodeDesktop']);
    assert.deepEqual(plan.config.sourceDiscovery.profileIDs, { minimaxCodeDesktop: 'desktop-test', minimaxCodeCLI: 'cli-test' });
    assert.ok(plan.copyFiles.includes('scripts/source.mjs')); assert.equal(plan.config.sourceDiscovery.probePath, plan.helperPath);
    assert.equal(Object.keys(plan.fileHashes).length, installedFiles.length);
    await assert.rejects(executeRequest({ ...f.request, dataDirConfirmed: false }), /confirmed active dataDir/);
    await assert.rejects(executeRequest({ ...f.request, apply: 'true' }), /explicit boolean/);
    await assert.rejects(executeRequest({ ...f.request, enableCLI: true }), /Desktop runtime verification/);
    assert.deepEqual((await executeRequest({ ...f.request, enableCLI: true, desktopVerified: true })).config.sourceDiscovery.allowedSources, ['minimaxCodeDesktop', 'minimaxCodeCLI']);
    const infoPath = join(f.request.desktopAppPath, 'Contents/Info.plist'); const original = await readFile(infoPath, 'utf8');
    await writeFile(infoPath, original.replace('3.1.0', '3.2.0')); await assert.rejects(executeRequest(f.request), /Unsupported Desktop/);
    await writeFile(infoPath, original);
    await writeFile(join(f.request.cliPrefix, 'lib/node_modules/@minimax-ai/code/package.json'), JSON.stringify({ name: '@minimax-ai/code', version: '0.5.4' }));
    assert.equal((await executeRequest(f.request)).config.source, "minimaxCodeDesktop");
    await assert.rejects(executeRequest({ ...f.request, enableCLI: true, desktopVerified: true }), /Unsupported CLI/);
    await rm(f.request.cliPrefix, { recursive: true });
    assert.equal((await executeRequest(f.request)).verifiedVersions.cli, null);
  } finally { await f.remove(); }
});
test('Unknown destination, symlink parents and helper path inside source are refused', platform, async () => {
  const f = await fixture();
  try {
    const plan = await buildPlan(f.request);
    await mkdir(plan.destination, { recursive: true });
    await writeFile(join(plan.destination, 'user-owned'), 'KEEP');
    await assert.rejects(executeRequest({ ...f.request, apply: true }), /unrecorded/);
    assert.equal(await readFile(join(plan.destination, 'user-owned'), 'utf8'), 'KEEP');
    await assert.rejects(buildPlan({ ...f.request, supportDir: f.request.dataDir }), /outside the source/);
    await rm(join(f.request.dataDir, 'plugins'), { recursive: true });
    await symlink(f.directory, join(f.request.dataDir, 'plugins'));
    await assert.rejects(buildPlan(f.request), /regular directory/);
  } finally { await f.remove(); }
});
test('Applied install, owned replacement and receipt-verified remove preserve all unrelated source data', platform, async () => {
  const f = await fixture();
  try {
    await mkdir(join(f.request.dataDir, 'plugins/other'), { recursive: true });
    await writeFile(join(f.request.dataDir, 'plugins/other/keep'), 'OTHER');
    await mkdir(join(f.request.dataDir, 'v2/sqlite'), { recursive: true });
    await writeFile(join(f.request.dataDir, 'v2/sqlite/runtime-state.sqlite'), 'DO_NOT_OPEN_OR_CHANGE');
    const installed = await executeRequest({ ...f.request, apply: true });
    assert.equal(installed.result, 'installed'); assert.ok(await inspectOwnership(installed));
    assert.equal((await executeRequest({ ...f.request, apply: true })).result, 'already-installed');
    assert.equal((await executeRequest({ ...f.request, enableCLI: true, desktopVerified: true })).action, 'replace-owned');
    const replaced = await executeRequest({ ...f.request, enableCLI: true, desktopVerified: true, apply: true });
    assert.equal(replaced.result, 'installed'); assert.equal(replaced.action, 'replace-owned');
    assert.deepEqual(JSON.parse(await readFile(join(replaced.destination, 'config.json'))).sourceDiscovery.allowedSources, ['minimaxCodeDesktop', 'minimaxCodeCLI']);
    const original = await readFile(join(replaced.destination, 'scripts/hook.mjs'));
    await writeFile(join(replaced.destination, 'scripts/hook.mjs'), 'USER_CHANGED');
    const removal = { operation: 'remove', dataDir: f.request.dataDir, dataDirConfirmed: true, supportDir: f.request.supportDir };
    await assert.rejects(executeRequest({ ...removal, apply: true }), /Owned plugin file changed/);
    assert.equal(await readFile(join(replaced.destination, 'scripts/hook.mjs'), 'utf8'), 'USER_CHANGED');
    await writeFile(join(replaced.destination, 'scripts/hook.mjs'), original);
    await writeFile(join(replaced.destination, 'unknown-user-file'), 'KEEP');
    await assert.rejects(executeRequest({ ...removal, apply: true }), /Unexpected files/);
    await rm(join(replaced.destination, 'unknown-user-file'));
    const receipt = JSON.parse(await readFile(replaced.receiptPath, 'utf8'));
    await writeFile(replaced.receiptPath, JSON.stringify({ ...receipt, helperPath: join(f.directory, 'unrelated') }));
    await assert.rejects(executeRequest({ ...removal, apply: true }), /receipt or path boundary/);
    await writeFile(replaced.receiptPath, JSON.stringify(receipt));
    await writeFile(replaced.receiptPath, JSON.stringify({ ...receipt, files: { ...receipt.files, '../unrelated': '0'.repeat(64) } }));
    await assert.rejects(executeRequest({ ...removal, apply: true }), /receipt or path boundary/);
    await writeFile(replaced.receiptPath, JSON.stringify(receipt));
    assert.equal((await executeRequest(removal)).action, 'remove-owned'); assert.equal(existsSync(replaced.destination), true);
    const removed = await executeRequest({ ...removal, apply: true });
    assert.equal(removed.result, 'removed'); assert.equal(removed.removedReceipt.owner, receipt.owner);
    assert.equal(existsSync(replaced.destination), false); assert.equal(existsSync(replaced.helperDirectory), false);
    assert.equal(await readFile(join(f.request.dataDir, 'plugins/other/keep'), 'utf8'), 'OTHER');
    assert.equal(await readFile(join(f.request.dataDir, 'v2/sqlite/runtime-state.sqlite'), 'utf8'), 'DO_NOT_OPEN_OR_CHANGE');
    assert.deepEqual(await readdir(f.request.supportDir), []);
    assert.equal((await executeRequest({ ...removal, apply: true })).result, 'already-absent');
  } finally { await f.remove(); }
});
