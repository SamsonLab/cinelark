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
const uhdnowSeries = require('./fixtures/uhdnow-series.js');

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

test('series playlist fixture retains observed UHDNow API shape without credentials', () => {
  const [currentEpisode, nextEpisode] = uhdnowSeries.episodes;
  assert.equal(currentEpisode.number, 2);
  assert.equal(currentEpisode.durationSeconds, 2473);
  assert.equal(currentEpisode.asset.id, '01M0DC5ESJ2ZR3AC9C3V80Y4SD');
  assert.equal(nextEpisode.number, 3);
  assert.equal(nextEpisode.durationSeconds, 2963);
  assert.equal(nextEpisode.asset.id, '01M0DC5F4BRJHQ5QWHXHACMFV0');

  for (const episode of uhdnowSeries.episodes) {
    const url = new URL(episode.asset.playbackURL);
    assert.equal(url.hostname, 'v1-vod1.uhdnow.com');
    assert.equal(url.pathname, `/play/video/${episode.asset.id}`);
    assert.equal(url.searchParams.get('token'), '<redacted>');
    assert.equal(/[a-f0-9]{32}/i.test(url.searchParams.get('token')), false);
    assert.equal(url.username, '');
    assert.equal(url.password, '');
  }
});
