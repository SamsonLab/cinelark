'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const protocol = require('../src/lib/protocol.js');

const globalSource = readFileSync(resolve(__dirname, '../src/global.js'), 'utf8');

async function settlePromises(iterations = 20) {
  for (let index = 0; index < iterations; index += 1) await Promise.resolve();
}

test('broker commands hop through the main-run-loop timer before using global player APIs', async () => {
  const secret = Array.from({ length: 32 }, (_, index) => index);
  const secretString = protocol.base64UrlEncode(secret);
  const sessionID = '6f55936d-5950-44fd-a696-f989d41785cc';
  const command = protocol.createEnvelope({
    type: 'player.play',
    sequence: 1,
    sessionID,
    secret,
    payload: {
      playbackID: sessionID,
      url: 'https://media.example/video?token=<redacted>',
      startPositionSeconds: 0,
    },
  });
  const timers = [];
  const calls = [];
  let deliveredCommand = false;

  const iinaGlobal = {
    createPlayerInstance: (options) => {
      calls.push(['createPlayerInstance', options]);
      return 17;
    },
    postMessage: (target, name, data) => calls.push(['postMessage', target, name, data]),
    onMessage: () => {},
  };
  const context = {
    iina: {
      console: { log: () => {} },
      global: iinaGlobal,
      http: {
        get: (url) => {
          if (url.endsWith('/v1/health')) {
            return Promise.resolve({
              statusCode: 200,
              data: { protocolVersion: protocol.PROTOCOL_VERSION },
            });
          }
          if (url.includes('/v1/plugin/commands?')) {
            if (!deliveredCommand) {
              deliveredCommand = true;
              return Promise.resolve({ statusCode: 200, data: { commands: [command] } });
            }
            return new Promise(() => {});
          }
          return Promise.reject(new Error('Unexpected GET'));
        },
        post: () => Promise.resolve({
          statusCode: 200,
          data: { protocolVersion: protocol.PROTOCOL_VERSION },
        }),
      },
      menu: {
        item: (_title, action) => action,
        addItem: () => {},
      },
      utils: { keychainRead: () => secretString },
    },
    require: (path) => {
      assert.equal(path, './lib/protocol.js');
      return protocol;
    },
    setTimeout: (callback) => {
      timers.push(callback);
      return timers.length;
    },
    Promise,
    Date,
    Math,
  };
  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  await settlePromises();

  assert.deepEqual(calls, []);
  assert.equal(timers.length, 1);
  timers.shift()();
  assert.equal(calls[0][0], 'createPlayerInstance');
  assert.deepEqual(calls[1].slice(0, 3), ['postMessage', 17, 'cinelark.command']);
});

test('broker discovery does not touch Keychain while CineLark is absent', async () => {
  let keychainReads = 0;
  const timers = [];
  const context = {
    iina: {
      global: { onMessage: () => {} },
      http: {
        get: () => Promise.reject(new Error('Broker unavailable')),
        post: () => Promise.reject(new Error('Unexpected POST')),
      },
      menu: { item: (_title, action) => action, addItem: () => {} },
      utils: { keychainRead: () => { keychainReads += 1; return false; } },
    },
    require: () => protocol,
    setTimeout: (callback) => { timers.push(callback); return timers.length; },
    Promise,
    Date,
    Math,
  };

  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  await settlePromises(50);

  assert.equal(keychainReads, 0);
  assert.equal(timers.length, 1);
});

test('automatic broker reconnect reuses the in-memory pairing key', async () => {
  const secret = Array.from({ length: 32 }, (_, index) => index);
  let keychainReads = 0;
  const timers = [];
  const context = {
    iina: {
      global: { onMessage: () => {} },
      http: {
        get: (url) => {
          if (url.endsWith('/v1/health')) {
            return Promise.resolve({
              statusCode: 200,
              data: { protocolVersion: protocol.PROTOCOL_VERSION },
            });
          }
          return Promise.reject(new Error('Long poll disconnected'));
        },
        post: () => Promise.resolve({
          statusCode: 200,
          data: { protocolVersion: protocol.PROTOCOL_VERSION },
        }),
      },
      menu: { item: (_title, action) => action, addItem: () => {} },
      utils: {
        keychainRead: () => {
          keychainReads += 1;
          return protocol.base64UrlEncode(secret);
        },
      },
    },
    require: () => protocol,
    setTimeout: (callback) => { timers.push(callback); return timers.length; },
    Promise,
    Date,
    Math,
  };

  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  await settlePromises(50);
  assert.equal(keychainReads, 1);
  assert.equal(timers.length, 1);

  timers.shift()();
  await settlePromises(50);
  assert.equal(keychainReads, 1);
});
