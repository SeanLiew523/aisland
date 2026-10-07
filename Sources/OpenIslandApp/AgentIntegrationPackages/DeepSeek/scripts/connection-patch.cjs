// Runs only in Desktop's reviewed Electron-as-Node configuration process.
// Reads the profile patch as opaque configuration; accesses only our exact row.
// Never reads session data, auth/provider properties or credentials.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const [anchor, filename, bridgeSocketPath, navigationSocketPath, mode] = process.argv.slice(2);
try {
  if (!anchor?.startsWith('/') || !filename?.startsWith('/') || !['status', 'update'].includes(mode)) throw new Error('Invalid request');
  const { parseDocument, isSeq, isMap } = createRequire(anchor)('yaml');
  const exists = fs.existsSync(filename);
  if (exists) { const s = fs.lstatSync(filename); if (!s.isFile() || s.size > 1048576) throw new Error('Invalid patch'); }
  const original = exists ? fs.readFileSync(filename, 'utf8') : '';
  const document = parseDocument(original || '[]\n', { customTags: [{ tag: 'tag:yaml.org,2002:js', resolve: value => value }] });
  if (document.errors.length || !isSeq(document.contents)) throw new Error('Invalid patch');
  const matches = document.contents.items.map((item, index) => ({ item, index })).filter(({ item, index }) =>
    isMap(item) && document.getIn([index, 'id']) === 'aisland-deepseek' && !item.has('insert'));
  if (matches.some(({ index }) => { const name = document.getIn([index, 'name']); return name && name !== '@aisland/deepseek-harness-plugin'; })) throw new Error('Foreign row');
  const last = matches.at(-1);
  const current = last && ['profileID', 'bridgeSocketPath', 'navigationSocketPath'].every((key, i) =>
    document.getIn([last.index, 'config', key]) === ['desktop', bridgeSocketPath, navigationSocketPath][i]);
  if (mode === 'status') { process.stdout.write(JSON.stringify({ isCurrent: !!current })); return; }
  if (current) { process.stdout.write('{"isCurrent":true,"changed":false}'); return; }
  // Retain unrelated patches, comments, source-disabled intent and custom poll/timeout values.
  const index = last?.index ?? document.contents.items.length;
  if (!last) document.add({ id: 'aisland-deepseek', name: '@aisland/deepseek-harness-plugin', config: {} });
  const config = document.getIn([index, 'config']);
  if (config && !isMap(config)) throw new Error('Unsupported config');
  for (const [key, value] of Object.entries({ profileID: 'desktop', bridgeSocketPath, navigationSocketPath })) document.setIn([index, 'config', key], value);
  if ((fs.existsSync(filename) ? fs.readFileSync(filename, 'utf8') : '') !== original) throw new Error('Changed configuration');
  const temporary = filename + '.aisland-' + process.pid + '-' + Date.now();
  const permissions = exists ? fs.statSync(filename).mode & 0o777 : 0o600;
  try { fs.writeFileSync(temporary, String(document), { flag: 'wx', mode: permissions }); fs.renameSync(temporary, filename); }
  finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  process.stdout.write('{"isCurrent":true,"changed":true}');
} catch { process.stderr.write('AIsland owned connection patch could not be updated.\n'); process.exitCode = 1; }
