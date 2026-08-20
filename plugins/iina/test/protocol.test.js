'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const {
  base64UrlDecode,
  base64UrlEncode,
  canonicalJson,
  hmacSha256,
  requestHeaders,
  sha256,
  signingInput,
  utf8Bytes,
  verifyEnvelope,
} = require('../src/lib/protocol.js');

function hex(bytes) {
  return Buffer.from(bytes).toString('hex');
}

test('pure JavaScript SHA-256 and HMAC match standard vectors', () => {
  assert.equal(
    hex(sha256('abc')),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
  );
  const key = utf8Bytes('synthetic-key');
  const message = 'CineLark bridge';
  assert.equal(
    hex(hmacSha256(key, message)),
    crypto.createHmac('sha256', Buffer.from(key)).update(message).digest('hex')
  );
});

test('base64url encoding round trips 256-bit pairing material', () => {
  const secret = Array.from({ length: 32 }, (_, index) => index);
  assert.deepEqual(base64UrlDecode(base64UrlEncode(secret)), secret);
});

test('canonical JSON is stable across key order', () => {
  assert.equal(
    canonicalJson({ z: { b: 2, a: 1 }, a: true }),
    '{"a":true,"z":{"a":1,"b":2}}'
  );
});

test('envelope authentication matches the shared vector and detects mutation', () => {
  const vector = JSON.parse(
    readFileSync(resolve(__dirname, '../../../fixtures/conformance/bridge-authentication-vector.json'))
  );
  const secret = base64UrlDecode(vector.secretBase64URL);
  const envelope = vector.envelope;
  assert.equal(verifyEnvelope(envelope, secret), true);
  envelope.payload.a = false;
  assert.equal(verifyEnvelope(envelope, secret), false);
  assert.match(signingInput(envelope), /^1\n[0-9a-f-]{36}\nplayer\.requestState\n/);
});

test('request authentication binds method, URI, timestamp, and nonce', () => {
  const secret = Array(32).fill(5);
  const first = requestHeaders({
    secret,
    method: 'GET',
    uri: '/v1/plugin/commands?after=1',
    timestamp: 42,
    nonce: 'synthetic-nonce-1',
  });
  const second = requestHeaders({
    secret,
    method: 'POST',
    uri: '/v1/plugin/commands?after=1',
    timestamp: 42,
    nonce: 'synthetic-nonce-1',
  });
  assert.notEqual(first['X-CineLark-Signature'], second['X-CineLark-Signature']);
});
