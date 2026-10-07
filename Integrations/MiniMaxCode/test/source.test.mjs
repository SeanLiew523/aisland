import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, rm, readFile, mkdir, writeFile, symlink } from 'node:fs/promises';
import { existsSync, realpathSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { classifySource, validDiscovery } from '../scripts/source.mjs';
const runFile = promisify(execFile);
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const app = '/Applications/MiniMax Code.app'; const prefix = '/source/mcode-prefix';
const config = { profileID: 'configured-desktop', source: 'minimaxCodeDesktop', sourceRuntimeVersion: '3.1.0',
  sourceDiscovery: { probePath: '/owned/source-probe', desktopAppPath: app, cliPrefix: prefix,
    allowedSources: ['minimaxCodeDesktop', 'minimaxCodeCLI'], profileIDs: { minimaxCodeDesktop: 'desktop', minimaxCodeCLI: 'cli' } } };
const hook = { pid: 300, parentPID: 200, executablePath: '/node/bin/node', startedAtMs: 3000 };
const desktop = { pid: 200, parentPID: 100, executablePath: app + '/Contents/Frameworks/MiniMax Code Helper.app/Contents/MacOS/MiniMax Code Helper', startedAtMs: 2000 };
const terminal = { pid: 100, parentPID: 1, executablePath: '/Applications/iTerm.app/Contents/MacOS/iTerm2', startedAtMs: 1000 };
const cli = { ...desktop, executablePath: '/node/bin/node', tty: '/dev/ttys007' };
const probe = ancestors => ({ schemaVersion: 1, ancestors, desktopApp: { path: app, bundleID: 'com.minimax.agent', version: '3.1.0' } });
function classify(value, { marker = null, version = '0.5.3', options = config, reads = [] } = {}) {
  return classifySource(value, options, { hookPID: 300, now: 4000, canonicalPath: value => value,
    readJSON(path, maximum) { reads.push({ path, maximum });
      if (path === prefix + '/lib/node_modules/@minimax-ai/code/package.json') return { name: '@minimax-ai/code', version };
      if (path === prefix + '/.mcode-active/200.json') return marker; return null; } });
}
test('Shared Desktop config classifies actual runtime and assigns separate profiles', () => {
  assert.deepEqual(classify(probe([hook, desktop, terminal])), { source: 'minimaxCodeDesktop', sourceRuntimeVersion: '3.1.0', profileID: 'desktop' });
  assert.deepEqual(classify(probe([hook, cli, terminal]), { marker: { pid: 200, startedAtMs: 2100 } }),
    { source: 'minimaxCodeCLI', sourceRuntimeVersion: '0.5.3', profileID: 'cli', terminalTTY: '/dev/ttys007', terminalApp: 'iTerm' });
});
test('Reviewed Desktop patch upgrade classifies actual version and preserves profile', () => {
  const value = probe([hook, desktop, terminal]); value.desktopApp.version = '3.1.1';
  assert.deepEqual(classify(value), { source: 'minimaxCodeDesktop', sourceRuntimeVersion: '3.1.1', profileID: 'desktop' });
  const options = { ...config, sourceRuntimeVersion: '3.1.1' };
  assert.equal(validDiscovery(options), true);
  assert.deepEqual(classify(value, { options }), { source: 'minimaxCodeDesktop', sourceRuntimeVersion: '3.1.1', profileID: 'desktop' });
});
test('Original CLI wins inside Desktop terminal; unknown Node never falls back to Desktop', () => {
  const outer = { ...desktop, pid: 100, parentPID: 1, startedAtMs: 1000 };
  assert.equal(classify(probe([hook, cli, outer]), { marker: { pid: 200, startedAtMs: 2100 } }).source, 'minimaxCodeCLI');
  assert.equal(classify(probe([hook, cli, outer])), null);
  const desktopOnly = { ...config, sourceDiscovery: { ...config.sourceDiscovery, allowedSources: ['minimaxCodeDesktop'] } };
  assert.equal(classify(probe([hook, cli, outer]), { marker: { pid: 200, startedAtMs: 2100 }, options: desktopOnly }), null);
  // Hook's interpreter itself may be bundled in Desktop, and must not classify the source.
  assert.equal(classify(probe([{ ...hook, executablePath: desktop.executablePath }, cli, outer]), { marker: { pid: 200, startedAtMs: 2100 } }).source, 'minimaxCodeCLI');
});
test('Missing, stale, future, malformed marker and version drift fail open', () => {
  for (const marker of [null, { pid: 201, startedAtMs: 2100 }, { pid: 200, startedAtMs: 1999 }, { pid: 200, startedAtMs: 3001 },
    { pid: 200, startedAtMs: '2100' }, { pid: 200, startedAtMs: 2100, message: 'PRIVATE' }]) assert.equal(classify(probe([hook, cli, terminal]), { marker }), null);
  assert.equal(classify(probe([hook, cli, terminal]), { marker: { pid: 200, startedAtMs: 2100 }, version: '0.5.4' }), null);
  for (const change of [{ version: '3.2.0' }, { bundleID: 'other.app' }, { path: '/other.app' }]) {
    const value = probe([hook, desktop, terminal]); Object.assign(value.desktopApp, change); assert.equal(classify(value), null);
  }
});
test('Reject forged or inconsistent process chains and unsafe configuration', () => {
  for (const ancestors of [[{ ...hook, pid: 301 }, desktop], [hook, { ...desktop, pid: 201 }], [hook, { ...desktop, startedAtMs: 3500 }],
    [hook, { ...desktop, executablePath: 'relative' }], [hook, { ...desktop, pid: 300 }], [hook, { ...desktop, startedAtMs: 5000 }]]) assert.equal(classify(probe(ancestors)), null);
  assert.equal(classify({ ...probe([hook, desktop]), schemaVersion: 2 }), null);
  for (const change of [{ probePath: 'relative' }, { cliPrefix: '/bad\npath' }, { allowedSources: ['minimaxCodeDesktop', 'minimaxCodeDesktop'] },
    { profileIDs: { minimaxCodeCLI: '' } }, { allowedSources: ['unknown'] }]) assert.ok(!validDiscovery({ ...config, sourceDiscovery: { ...config.sourceDiscovery, ...change } }));
});
test('Reads only reviewed package identity and exact ancestor PID markers, never a directory scan', () => {
  const reads = []; const value = classify(probe([hook, desktop, terminal]), { reads });
  assert.equal(value.source, 'minimaxCodeDesktop');
  assert.deepEqual(reads, [{ path: prefix + '/lib/node_modules/@minimax-ai/code/package.json', maximum: 65536 }, { path: prefix + '/.mcode-active/200.json', maximum: 1024 }]);
  const result = classify(probe([hook, { ...cli, tty: '/dev/ttys007\nPRIVATE' }, terminal]), { marker: { pid: 200, startedAtMs: 2100 } });
  assert.equal(result.terminalTTY, undefined);
});
test('Production metadata reader accepts regular native marker and rejects symlink or oversized marker', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aisland-source-marker-'));
  try {
    const realPrefix = realpathSync(dir); const realApp = join(realPrefix, 'Fixture.app');
    await mkdir(realApp); await mkdir(join(realPrefix, 'lib/node_modules/@minimax-ai/code'), { recursive: true });
    await mkdir(join(realPrefix, '.mcode-active'));
    await writeFile(join(realPrefix, 'lib/node_modules/@minimax-ai/code/package.json'), JSON.stringify({ name: '@minimax-ai/code', version: '0.5.3' }));
    const markerPath = join(realPrefix, '.mcode-active/200.json');
    const options = { ...config, sourceDiscovery: { ...config.sourceDiscovery, desktopAppPath: realApp, cliPrefix: realPrefix } };
    const read = () => classifySource(probe([hook, cli, terminal]), options, { hookPID: 300, now: 4000 });
    await writeFile(markerPath, JSON.stringify({ pid: 200, startedAtMs: 2100 }));
    assert.equal(read().source, 'minimaxCodeCLI');
    await rm(markerPath); const target = join(realPrefix, 'outside-marker');
    await writeFile(target, JSON.stringify({ pid: 200, startedAtMs: 2100 })); await symlink(target, markerPath);
    assert.equal(read(), null);
    await rm(markerPath); await writeFile(markerPath, JSON.stringify({ pid: 200, startedAtMs: 2100 }) + ' '.repeat(1024));
    assert.equal(read(), null);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test('Compiled macOS probe returns real own-process metadata and validates installed app only', { skip: process.platform !== 'darwin' }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'aisland-source-probe-'));
  try {
    const path = join(dir, 'probe');
    await runFile('swiftc', ['-O', join(root, 'scripts/source-probe.swift'), '-o', path], { timeout: 30000 });
    // A freshly compiled binary may incur first-launch OS validation. Installer preflights it.
    const { stdout, stderr } = await runFile(path, [String(process.pid), app], { timeout: 5000 });
    const value = JSON.parse(stdout); assert.equal(stderr, ''); assert.equal(value.schemaVersion, 1);
    assert.equal(value.ancestors[0].pid, process.pid); assert.equal(value.ancestors[0].executablePath, realpathSync(process.execPath));
    assert.ok(value.ancestors[0].startedAtMs <= Date.now()); assert.ok(value.ancestors.length >= 2);
    for (const ancestor of value.ancestors) assert.ok(Object.keys(ancestor).every(key => ['pid', 'parentPID', 'executablePath', 'startedAtMs', 'tty'].includes(key)));
    if (existsSync(app)) {
      assert.equal(value.desktopApp.path, app); assert.equal(value.desktopApp.bundleID, 'com.minimax.agent');
      assert.ok(['3.1.0', '3.1.1'].includes(value.desktopApp.version));
    }
    await runFile(path, [String(process.pid), app], { timeout: 200 });
    assert.deepEqual(JSON.parse((await runFile(path, ['0', app])).stdout).ancestors, []);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
const cliPackage = '/Users/seanliew/.minimax-code/lib/node_modules/@minimax-ai/code';
test('Installed CLI contract owns marker for the normal TUI process lifetime', { skip: !existsSync(join(cliPackage, 'cli.js')) }, async () => {
  const manifest = JSON.parse(await readFile(join(cliPackage, 'package.json'), 'utf8'));
  assert.equal(manifest.name, '@minimax-ai/code'); assert.equal(manifest.version, '0.5.3');
  const registration = await readFile(join(cliPackage, 'chunks/chunk-ZZOIWHZG.js'), 'utf8');
  assert.match(registration, /I="\.mcode-active"/);
  assert.match(registration, /JSON\.stringify\(\{pid:process\.pid,startedAtMs:Date\.now\(\)\}\)/);
  assert.match(registration, /function re\(e=process\.argv\[1\]\)/);
  const entry = await readFile(join(cliPackage, 'cli.js'), 'utf8');
  assert.match(entry, /let p=await s\(\);try\{/); assert.match(entry, /finally\{p\.remove\(\)\}/);
});
