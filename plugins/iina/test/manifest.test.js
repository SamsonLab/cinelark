'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');

const root = resolve(__dirname, '..');
const manifest = JSON.parse(readFileSync(resolve(root, 'Info.json'), 'utf8'));
const packageManifest = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'));
const globalSource = readFileSync(resolve(root, 'src/global.js'), 'utf8');
const playerSource = readFileSync(resolve(root, 'src/main.js'), 'utf8');

test('plugin version remains aligned across the archive and handshake', () => {
  assert.equal(manifest.version, packageManifest.version);
  assert.match(globalSource, new RegExp(`PLUGIN_VERSION = '${manifest.version.replaceAll('.', '\\.')}'`));
});

test('file-system permission is used only to satisfy IINA core.open authorization', () => {
  assert.deepEqual(manifest.permissions.sort(), ['file-system', 'network-request']);
  const source = `${globalSource}\n${playerSource}`;
  assert.equal(/\b(?:iina\.)?file\.(read|write|delete|move|copy)\b/.test(source), false);
  assert.equal(/utils\.(exec|resolvePath|chooseFile)\b/.test(source), false);
  assert.match(playerSource, /core\.open\(payload\.url\)/);
});
