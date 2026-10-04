const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const anchor = process.env.AISLAND_TEST_YAML_ANCHOR;
const helper = path.resolve(__dirname, '../../Sources/OpenIslandApp/AgentIntegrationPackages/DeepSeek/scripts/connection-patch.cjs');
test('owned patch changes only connection fields and retains comments, custom settings and source opt-out', { skip: !anchor }, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'aisland-deepseek-patch-'));
  try {
    const filename = path.join(root, 'cordis.patch.yml');
    const original = '# source comment\n- id: unrelated\n  config:\n    keep: untouched\n- id: aisland-deepseek\n  name: "@aisland/deepseek-harness-plugin"\n  disabled: true\n  config:\n    pollIntervalMs: 1234 # custom preference\n    bridgeSocketPath: /old/bridge.sock\n';
    fs.writeFileSync(filename, original);
    function run(mode) { return spawnSync(process.execPath, [helper, anchor, filename, '/fixture/bridge.sock', '/fixture/navigation.sock', mode], { encoding: 'utf8' }); }
    assert.deepEqual(JSON.parse(run('status').stdout), { isCurrent: false });
    const result = run('update'); assert.equal(result.status, 0, result.stderr);
    const yaml = require('node:module').createRequire(anchor)('yaml');
    const updated = fs.readFileSync(filename, 'utf8');
    const rows = yaml.parse(updated);
    assert.equal(rows[0].config.keep, 'untouched');
    assert.equal(rows[1].disabled, true);
    assert.equal(rows[1].config.pollIntervalMs, 1234);
    assert.equal(rows[1].config.bridgeSocketPath, '/fixture/bridge.sock');
    assert.equal(rows[1].config.navigationSocketPath, '/fixture/navigation.sock');
    assert.ok(updated.includes('# source comment') && updated.includes('# custom preference'));
    assert.equal(run('update').status, 0);
    assert.equal(fs.readFileSync(filename, 'utf8'), updated);
    fs.writeFileSync(filename, '- id: aisland-deepseek\n  name: foreign-module\n  config: {}\n');
    const foreign = fs.readFileSync(filename);
    assert.notEqual(run('update').status, 0);
    assert.deepEqual(fs.readFileSync(filename), foreign);
    fs.writeFileSync(filename, '- id: aisland-deepseek\n  config: one\n  config: two\n');
    const invalid = fs.readFileSync(filename);
    assert.notEqual(run('update').status, 0);
    assert.deepEqual(fs.readFileSync(filename), invalid);
  } finally { fs.rmSync(root, { recursive: true }); }
});
