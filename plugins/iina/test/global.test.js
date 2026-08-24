'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const protocol = require('../src/lib/protocol.js');
const uhdnowSeries = require('./fixtures/uhdnow-series.js');

const globalSource = readFileSync(resolve(__dirname, '../src/global.js'), 'utf8');
const [currentEpisode, nextEpisode] = uhdnowSeries.episodes;

async function settlePromises(iterations = 20) {
  for (let index = 0; index < iterations; index += 1) await Promise.resolve();
}

function timerHarness() {
  const timers = [];
  let isMainTurn = true;

  return {
    timers,
    assertMain: () => assert.equal(isMainTurn, true, 'IINA API called off the main run loop'),
    setTimeout: (callback, milliseconds) => {
      timers.push({ callback, milliseconds });
      return timers.length;
    },
    finishInitialTurn: () => { isMainTurn = false; },
    run: async (timer) => {
      isMainTurn = true;
      timer.callback();
      isMainTurn = false;
      await settlePromises();
    },
    drainImmediate: async () => {
      for (let count = 0; count < 100; count += 1) {
        const index = timers.findIndex((timer) => timer.milliseconds === 0);
        if (index < 0) return;
        const [timer] = timers.splice(index, 1);
        isMainTurn = true;
        timer.callback();
        isMainTurn = false;
        await settlePromises();
      }
      throw new Error('Immediate IINA timer queue did not settle');
    },
  };
}

test('all broker, Keychain, and player IINA APIs execute on the main run loop', async () => {
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
      url: currentEpisode.asset.playbackURL,
      title: currentEpisode.title,
      startPositionSeconds: 0,
    },
  });
  const nextPlaybackID = '823daa90-8016-44de-88f2-78048f167d22';
  const nextCommand = protocol.createEnvelope({
    type: 'player.play',
    sequence: 2,
    sessionID: nextPlaybackID,
    secret,
    payload: {
      playbackID: nextPlaybackID,
      url: nextEpisode.asset.playbackURL,
      title: nextEpisode.title,
      startPositionSeconds: 0,
    },
  });
  const harness = timerHarness();
  const calls = [];
  let deliveredCommand = false;

  const context = {
    iina: {
      global: {
        createPlayerInstance: (options) => {
          harness.assertMain();
          calls.push(['createPlayerInstance', options]);
          return 17;
        },
        postMessage: (target, name, data) => {
          harness.assertMain();
          calls.push(['postMessage', target, name, data]);
        },
        onMessage: () => {},
      },
      http: {
        get: (url) => {
          harness.assertMain();
          if (url.endsWith('/v1/health')) {
            return Promise.resolve({
              statusCode: 200,
              data: { protocolVersion: protocol.PROTOCOL_VERSION },
            });
          }
          if (url.includes('/v1/plugin/commands?')) {
            if (!deliveredCommand) {
              deliveredCommand = true;
              return Promise.resolve({
                statusCode: 200,
                data: { commands: [command, nextCommand] },
              });
            }
            return new Promise(() => {});
          }
          return Promise.reject(new Error('Unexpected GET'));
        },
        post: () => {
          harness.assertMain();
          return Promise.resolve({
            statusCode: 200,
            data: { protocolVersion: protocol.PROTOCOL_VERSION },
          });
        },
      },
      menu: { item: (_title, action) => action, addItem: () => {} },
      utils: {
        keychainRead: () => {
          harness.assertMain();
          return secretString;
        },
      },
    },
    require: (path) => {
      assert.equal(path, './lib/protocol.js');
      return protocol;
    },
    setTimeout: harness.setTimeout,
    Promise,
    Date,
    Math,
  };
  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  harness.finishInitialTurn();
  await harness.drainImmediate();

  const createCalls = calls.filter(([name]) => name === 'createPlayerInstance');
  const messageCalls = calls.filter(([name]) => name === 'postMessage');
  assert.equal(createCalls.length, 1);
  assert.equal(createCalls[0][1].enablePlugins, false);
  assert.equal(createCalls[0][1].label, 'cinelark:managed');
  assert.equal(messageCalls.length, 2);
  assert.deepEqual(messageCalls[0].slice(0, 3), ['postMessage', 17, 'cinelark.command']);
  assert.deepEqual(messageCalls[1].slice(0, 3), ['postMessage', 17, 'cinelark.command']);

  const timeoutIndex = harness.timers.findIndex((timer) => timer.milliseconds === 500);
  assert.notEqual(timeoutIndex, -1);
  const [replacementTimeout] = harness.timers.splice(timeoutIndex, 1);
  await harness.run(replacementTimeout);
  assert.equal(
    calls.filter(([name]) => name === 'createPlayerInstance').length,
    1,
    'replacement timeout must not create a second player window'
  );
});

test('broker discovery does not touch Keychain while CineLark is absent', async () => {
  const harness = timerHarness();
  let keychainReads = 0;
  const context = {
    iina: {
      global: { onMessage: () => {} },
      http: {
        get: () => {
          harness.assertMain();
          return Promise.reject(new Error('Broker unavailable'));
        },
        post: () => Promise.reject(new Error('Unexpected POST')),
      },
      menu: { item: (_title, action) => action, addItem: () => {} },
      utils: { keychainRead: () => { keychainReads += 1; return false; } },
    },
    require: () => protocol,
    setTimeout: harness.setTimeout,
    Promise,
    Date,
    Math,
  };

  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  harness.finishInitialTurn();
  await harness.drainImmediate();

  assert.equal(keychainReads, 0);
  assert.equal(harness.timers.length, 1);
  assert.equal(harness.timers[0].milliseconds, 3000);
});

test('automatic broker reconnect reuses the in-memory pairing key', async () => {
  const secret = Array.from({ length: 32 }, (_, index) => index);
  const harness = timerHarness();
  let keychainReads = 0;
  const context = {
    iina: {
      global: { onMessage: () => {} },
      http: {
        get: (url) => {
          harness.assertMain();
          if (url.endsWith('/v1/health')) {
            return Promise.resolve({
              statusCode: 200,
              data: { protocolVersion: protocol.PROTOCOL_VERSION },
            });
          }
          return Promise.reject(new Error('Long poll disconnected'));
        },
        post: () => {
          harness.assertMain();
          return Promise.resolve({
            statusCode: 200,
            data: { protocolVersion: protocol.PROTOCOL_VERSION },
          });
        },
      },
      menu: { item: (_title, action) => action, addItem: () => {} },
      utils: {
        keychainRead: () => {
          harness.assertMain();
          keychainReads += 1;
          return protocol.base64UrlEncode(secret);
        },
      },
    },
    require: () => protocol,
    setTimeout: harness.setTimeout,
    Promise,
    Date,
    Math,
  };

  vm.runInNewContext(globalSource, context, { filename: 'global.js' });
  harness.finishInitialTurn();
  await harness.drainImmediate();
  assert.equal(keychainReads, 1);

  const reconnectTimerIndex = harness.timers.findIndex((timer) => timer.milliseconds === 3000);
  const [reconnectTimer] = harness.timers.splice(reconnectTimerIndex, 1);
  await harness.run(reconnectTimer);
  await harness.drainImmediate();
  assert.equal(keychainReads, 1);
});
