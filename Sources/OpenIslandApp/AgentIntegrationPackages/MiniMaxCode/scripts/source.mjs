import { execFile } from 'node:child_process';
import { constants, openSync, closeSync, fstatSync, readSync, realpathSync } from 'node:fs';
import { join, isAbsolute, basename } from 'node:path';
import { promisify } from 'node:util';
const runFile = promisify(execFile);
const cleanPath = value => typeof value === 'string' && isAbsolute(value) && Buffer.byteLength(value) <= 4096 && !/[\x00-\x1f\x7f-\x9f]/.test(value);
const pidValue = value => Number.isSafeInteger(value) && value > 1 && value <= 2147483647;
const cleanID = value => typeof value === 'string' && value.trim().length > 0 && Buffer.byteLength(value) <= 1024 && !/[\x00-\x1f\x7f-\x9f]/.test(value);
export function validDiscovery(config) {
  const options = config?.sourceDiscovery;
  return options && typeof options === 'object' && !Array.isArray(options)
    && [options.probePath, options.desktopAppPath, options.cliPrefix].every(cleanPath)
    && options.desktopAppPath.endsWith('.app') && Array.isArray(options.allowedSources) && options.allowedSources.length > 0
    && options.allowedSources.length <= 2 && new Set(options.allowedSources).size === options.allowedSources.length
    && options.allowedSources.every(value => ['minimaxCodeDesktop', 'minimaxCodeCLI'].includes(value))
    && (options.hookRuntimeKind === undefined || options.hookRuntimeKind === 'node'
      || (options.hookRuntimeKind === 'minimaxDesktopElectron' && config.sourceRuntimeVersion === '3.1.0'
        && options.allowedSources.length === 1 && options.allowedSources[0] === 'minimaxCodeDesktop'))
    && (options.profileIDs === undefined || (options.profileIDs && typeof options.profileIDs === 'object'
      && !Array.isArray(options.profileIDs) && Object.keys(options.profileIDs).every(key => ['minimaxCodeDesktop', 'minimaxCodeCLI'].includes(key))
      && Object.values(options.profileIDs).every(cleanID)));
}
function readMetadataJSON(path, maximum) {
  let fd;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const stats = fstatSync(fd);
    if (!stats.isFile() || stats.size > maximum || stats.size <= 0) return null;
    const bytes = Buffer.alloc(maximum + 1);
    const count = readSync(fd, bytes, 0, bytes.length, 0);
    if (count <= 0 || count > maximum) return null;
    return JSON.parse(bytes.subarray(0, count).toString('utf8'));
  } catch { return null; } finally { if (fd !== undefined) closeSync(fd); }
}
function validChain(probe, hookPID, now) {
  if (probe?.schemaVersion !== 1 || !Array.isArray(probe.ancestors) || probe.ancestors.length < 2 || probe.ancestors.length > 16 || probe.ancestors[0]?.pid !== hookPID) return false;
  const ids = new Set();
  return probe.ancestors.every((value, index) => {
    if (!pidValue(value?.pid) || !Number.isSafeInteger(value.parentPID) || value.parentPID < 0 || value.parentPID > 2147483647
      || !cleanPath(value.executablePath) || !Number.isFinite(value.startedAtMs) || value.startedAtMs <= 0 || value.startedAtMs > now
      || ids.has(value.pid)) return false;
    ids.add(value.pid);
    const parent = probe.ancestors[index + 1];
    return !parent || (value.parentPID === parent.pid && value.startedAtMs >= parent.startedAtMs);
  });
}
function terminalName(ancestors) {
  for (const value of ancestors) {
    if (value.executablePath.includes('/iTerm.app/Contents/')) return 'iTerm';
    if (value.executablePath.includes('/Terminal.app/Contents/')) return 'Terminal';
    if (value.executablePath.includes('/Warp.app/Contents/')) return 'Warp';
    if (value.executablePath.includes('/Ghostty.app/Contents/')) return 'Ghostty';
  }
  return undefined;
}
// Injection exists only for deterministic fixtures. Production reads fixed public-package
// metadata and exactly one native PID marker per proven ancestor, never argv/env.
export function classifySource(probe, config, { hookPID = process.pid, now = Date.now(), readJSON = readMetadataJSON, canonicalPath = realpathSync } = {}) {
  if (!validDiscovery(config) || !validChain(probe, hookPID, now)) return null;
  let desktopPath; let prefix;
  try { desktopPath = canonicalPath(config.sourceDiscovery.desktopAppPath); } catch {}
  try { prefix = canonicalPath(config.sourceDiscovery.cliPrefix); } catch {}
  const packageMetadata = prefix ? readJSON(join(prefix, 'lib/node_modules/@minimax-ai/code/package.json'), 65536) : null;
  // Skip the Hook command itself; its interpreter may come from either application.
  for (let index = 1; index < probe.ancestors.length; index += 1) {
    const ancestor = probe.ancestors[index];
    const marker = prefix ? readJSON(join(prefix, '.mcode-active', `${ancestor.pid}.json`), 1024) : null;
    if (packageMetadata?.name === '@minimax-ai/code' && packageMetadata.version === '0.5.3'
        && marker && Object.keys(marker).every(key => ['pid', 'startedAtMs'].includes(key))
        && marker.pid === ancestor.pid && Number.isSafeInteger(marker.startedAtMs)
        && marker.startedAtMs >= ancestor.startedAtMs && marker.startedAtMs <= probe.ancestors[0].startedAtMs) {
      if (!config.sourceDiscovery.allowedSources.includes('minimaxCodeCLI')) return null;
      const tty = typeof ancestor.tty === 'string' && /^\/dev\/tty[A-Za-z0-9._-]+$/.test(ancestor.tty) ? ancestor.tty : undefined;
      return { source: 'minimaxCodeCLI', sourceRuntimeVersion: packageMetadata.version,
        profileID: config.sourceDiscovery.profileIDs?.minimaxCodeCLI ?? config.profileID,
        ...(tty ? { terminalTTY: tty } : {}), ...(terminalName(probe.ancestors.slice(index + 1)) ? { terminalApp: terminalName(probe.ancestors.slice(index + 1)) } : {}) };
    }
    // Unknown/stale Node in a Desktop terminal is not a Desktop runtime proof.
    if (['node', 'nodejs'].includes(basename(ancestor.executablePath).toLowerCase())) return null;
    if (desktopPath && ancestor.executablePath.startsWith(desktopPath + '/Contents/')) {
      // A nearer mcode marker always wins, including mcode in Desktop's terminal.
      if (probe.desktopApp?.path !== desktopPath || probe.desktopApp.bundleID !== 'com.minimax.agent'
          || probe.desktopApp.version !== '3.1.0' || !config.sourceDiscovery.allowedSources.includes('minimaxCodeDesktop')) return null;
      return { source: 'minimaxCodeDesktop', sourceRuntimeVersion: probe.desktopApp.version,
        profileID: config.sourceDiscovery.profileIDs?.minimaxCodeDesktop ?? config.profileID };
    }
  }
  return null;
}
export async function resolveSource(config) {
  if (!validDiscovery(config)) return null;
  try {
    const { stdout } = await runFile(config.sourceDiscovery.probePath, [String(process.pid), config.sourceDiscovery.desktopAppPath],
      { timeout: 200, maxBuffer: 16384, windowsHide: true, encoding: 'utf8' });
    return classifySource(JSON.parse(stdout), config);
  } catch { return null; }
}
