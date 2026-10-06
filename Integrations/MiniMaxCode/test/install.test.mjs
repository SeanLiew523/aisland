import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, readdir } from 'node:fs/promises';
import { existsSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { executeRequest, inspectOwnership } from '../scripts/install.mjs';
import { buildPlan, installedFiles, digest, packageRoot } from '../plan.mjs';
import { validDiscovery } from '../scripts/source.mjs';
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

test('Bundled probe is hash-bound, copied exactly and migrates an owned compiled helper without a compiler plan', platform, async () => {
  assert.ok(process.env.AISLAND_TEST_BUNDLED_PROBE_PATH, 'Build MiniMaxCodeSourceProbe and provide its path');
  const f = await fixture();
  try {
    const bundledProbePath = join(f.directory, 'bundled-probe');
    const bytes = await readFile(process.env.AISLAND_TEST_BUNDLED_PROBE_PATH);
    await writeFile(bundledProbePath, bytes, { mode: 0o755 });
    const request = { ...f.request, bundledProbePath, bundledProbeHash: digest(bytes) };
    const plan = await buildPlan(request);
    assert.equal(plan.helperBuild.kind, 'copy-bundled'); assert.equal(plan.helperBuild.compiler, undefined);
    await assert.rejects(buildPlan({ ...request, bundledProbeHash: '0'.repeat(64) }), /hash mismatch/);
    await symlink(bundledProbePath, join(f.directory, 'symlink-probe'));
    await assert.rejects(buildPlan({ ...request, bundledProbePath: join(f.directory, 'symlink-probe') }));
    // Legacy standalone installer remains a fixture-only migration source.
    const old = await executeRequest({ ...f.request, apply: true });
    assert.notEqual(JSON.parse(await readFile(old.receiptPath)).helperHash, digest(bytes));
    assert.equal((await executeRequest(request)).action, 'replace-owned');
    const installed = await executeRequest({ ...request, apply: true });
    assert.deepEqual(await readFile(installed.helperPath), bytes);
    assert.equal(JSON.parse(await readFile(installed.receiptPath)).helperHash, digest(bytes));
    assert.equal((await executeRequest({ ...request, apply: true })).result, 'already-installed');
    const removal = { operation: 'remove', dataDir: request.dataDir, dataDirConfirmed: true, supportDir: request.supportDir, apply: true };
    assert.equal((await executeRequest(removal)).result, 'removed');
  } finally { await f.remove(); }
});

test('Desktop embedded runtime is limited to the exact reviewed executable/version and persists the Node-mode prefix', platform, async () => {
  assert.ok(process.env.AISLAND_TEST_BUNDLED_PROBE_PATH);
  const f = await fixture();
  try {
    const executable = join(f.request.desktopAppPath, 'Contents/MacOS/Fixture');
    // Synthetic public version probe; real official Electron verification belongs to the main flow.
    await writeFile(executable, '#!/bin/sh\nprintf \'%s\' \'{"node":"24.18.0","electron":"42.8.0"}\'\n', { mode: 0o755 });
    const bundledProbePath = process.env.AISLAND_TEST_BUNDLED_PROBE_PATH;
    const request = { ...f.request, nodePath: executable, hookRuntimeKind: 'minimaxDesktopElectron', bundledProbePath,
      bundledProbeHash: digest(await readFile(bundledProbePath)) };
    const plan = await buildPlan(request);
    assert.equal(plan.config.sourceDiscovery.hookRuntimeKind, 'minimaxDesktopElectron');
    assert.ok(validDiscovery(plan.config));
    for (const groups of Object.values(plan.hooks.hooks)) for (const group of groups) for (const hook of group.hooks) assert.ok(hook.command.startsWith('ELECTRON_RUN_AS_NODE=1 "' + executable + '" '));
    assert.equal(validDiscovery({ ...plan.config, sourceDiscovery: { ...plan.config.sourceDiscovery, hookRuntimeKind: 'other' } }), false);
    assert.equal(validDiscovery({ ...plan.config, sourceRuntimeVersion: '3.2.0' }), false);
    await assert.rejects(buildPlan({ ...request, enableCLI: true, desktopVerified: true }), /Desktop-only/);
    await assert.rejects(buildPlan({ ...request, nodePath: process.execPath }), /identity mismatch/);
    await writeFile(executable, '#!/bin/sh\nprintf \'%s\' \'{"node":"24.19.0","electron":"42.8.0"}\'\n', { mode: 0o755 });
    await assert.rejects(buildPlan(request), /embedded runtime version/);
    assert.equal(existsSync(plan.destination), false);
  } finally { await f.remove(); }
});

test('Owned helper relocation isolates a new case and preserves the complete previous helper tree', platform, async () => {
  assert.ok(process.env.AISLAND_TEST_BUNDLED_PROBE_PATH);
  const f = await fixture();
  try {
    const bundledProbePath = process.env.AISLAND_TEST_BUNDLED_PROBE_PATH;
    const base = { ...f.request, bundledProbePath, bundledProbeHash: digest(await readFile(bundledProbePath)) };
    const old = await executeRequest({ ...base, apply: true });
    const oldReceipt = await readFile(old.receiptPath), oldHelper = await readFile(old.helperPath);
    const request = { ...base, supportDir: join(f.directory, 'isolated-support'),
      previousHelperDirectory: old.helperDirectory, bridgeSocketPath: join(f.directory, 'isolated.sock') };
    const plan = await executeRequest(request);
    assert.equal(plan.action, 'replace-owned'); assert.equal(plan.existingReceipt.helperDirectory, old.helperDirectory);
    const installed = await executeRequest({ ...request, apply: true });
    assert.notEqual(installed.helperDirectory, old.helperDirectory);
    assert.deepEqual(await readFile(old.receiptPath), oldReceipt);
    assert.deepEqual(await readFile(old.helperPath), oldHelper);
    const config = JSON.parse(await readFile(join(installed.destination, 'config.json')));
    assert.equal(config.bridgeSocketPath, request.bridgeSocketPath);
    assert.equal(config.sourceDiscovery.probePath, installed.helperPath);
    assert.equal((await executeRequest({ ...request, apply: true })).result, 'already-installed');
    assert.equal((await executeRequest({ ...request, operation: 'remove', previousHelperDirectory: undefined, apply: true })).result, 'removed');
    assert.deepEqual(await readFile(old.receiptPath), oldReceipt);
    assert.deepEqual(await readFile(old.helperPath), oldHelper);
    // A plugin whose own config points elsewhere cannot borrow a valid receipt.
    const oldConfig = JSON.parse(await readFile(join(f.directory, 'support/minimaxcode-passive/receipt.json')));
    assert.equal(oldConfig.helperDirectory, old.helperDirectory);
  } finally { await f.remove(); }
});

test('Relocation requires the exact owned plugin-to-helper binding and rejects changed or foreign helper content', platform, async () => {
  assert.ok(process.env.AISLAND_TEST_BUNDLED_PROBE_PATH);
  const f = await fixture();
  try {
    const bundledProbePath = process.env.AISLAND_TEST_BUNDLED_PROBE_PATH;
    const base = { ...f.request, bundledProbePath, bundledProbeHash: digest(await readFile(bundledProbePath)) };
    const old = await executeRequest({ ...base, apply: true });
    const relocation = { ...base, supportDir: join(f.directory, 'isolated-support'), previousHelperDirectory: old.helperDirectory };
    const bytes = await readFile(old.helperPath);
    await writeFile(old.helperPath, 'CHANGED');
    await assert.rejects(executeRequest({ ...relocation, apply: true }), /Owned helper changed/);
    assert.equal(existsSync(join(relocation.supportDir, 'minimaxcode-passive')), false);
    await writeFile(old.helperPath, bytes, { mode: 0o700 });
    await writeFile(join(old.helperDirectory, 'foreign'), 'KEEP');
    await assert.rejects(executeRequest({ ...relocation, apply: true }), /Unexpected files/);
    assert.equal(await readFile(join(old.helperDirectory, 'foreign'), 'utf8'), 'KEEP');
    await assert.rejects(executeRequest({ ...relocation, previousHelperDirectory: f.request.dataDir }), /Invalid previous helper/);
    await assert.rejects(executeRequest({ ...relocation, operation: 'remove' }), /only admitted/);
  } finally { await f.remove(); }
});


test('Native CLI entry points return JSON through a symlinked package path without applying source changes', platform, async () => {
  const f = await fixture();
  try {
    const alias = join(f.directory, 'package-alias');
    await symlink(packageRoot, alias);
    for (const filename of ['plan.mjs', 'scripts/install.mjs']) {
      const bytes = execFileSync(process.execPath, [join(alias, filename), JSON.stringify(f.request)],
        { env: { PATH: '/usr/bin:/bin', LC_ALL: 'C' }, timeout: 5000, maxBuffer: 65536 });
      const result = JSON.parse(bytes);
      assert.equal(result.mode, 'dry-run-only');
      assert.equal(result.destination, join(f.request.dataDir, 'plugins/aisland-minimaxcode-passive'));
      if (filename === 'scripts/install.mjs') assert.equal(result.action, 'install-new');
      assert.equal(existsSync(result.destination), false);
      assert.equal(existsSync(result.helperDirectory), false);
    }
  } finally { await f.remove(); }
});


test('Missing helper is recovered only for the exact bundled plugin; changed or foreign files survive refusal', platform, async () => {
  const f = await fixture();
  try {
    const bundledProbePath = process.env.AISLAND_TEST_BUNDLED_PROBE_PATH;
    assert.ok(bundledProbePath);
    const request = { ...f.request, bundledProbePath, bundledProbeHash: digest(await readFile(bundledProbePath)) };
    const installed = await executeRequest({ ...request, apply: true });
    const oldConfig = await readFile(join(installed.destination, 'config.json'));
    await rm(installed.helperDirectory, { recursive: true });
    const plan = await executeRequest(request);
    assert.equal(plan.action, 'repair-missing-helper');
    assert.equal(existsSync(installed.helperDirectory), false);
    const hook = join(installed.destination, 'scripts/hook.mjs');
    const original = await readFile(hook);
    await writeFile(hook, 'USER_CHANGED');
    await assert.rejects(executeRequest({ ...request, apply: true }), /changed plugin/);
    assert.equal(await readFile(hook, 'utf8'), 'USER_CHANGED');
    await writeFile(hook, original);
    await writeFile(join(installed.destination, 'foreign'), 'KEEP');
    await assert.rejects(executeRequest({ ...request, apply: true }), /Unexpected files|inventory/);
    assert.equal(await readFile(join(installed.destination, 'foreign'), 'utf8'), 'KEEP');
    await rm(join(installed.destination, 'foreign'));
    const fixed = await executeRequest({ ...request, apply: true });
    assert.equal(fixed.action, 'repair-missing-helper');
    assert.equal(fixed.result, 'installed');
    assert.deepEqual(await readFile(join(fixed.destination, 'config.json')), oldConfig);
    assert.ok(await inspectOwnership(fixed));
    assert.equal((await executeRequest(request)).action, 'already-installed');
  } finally { await f.remove(); }
});
