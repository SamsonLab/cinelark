'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const uhdnowSeries = require('./fixtures/uhdnow-series.js');

const [currentEpisode, nextEpisode] = uhdnowSeries.episodes;

function makeHarness() {
  const eventHandlers = new Map();
  const messageHandlers = new Map();
  const emitted = [];
  const calls = [];
  let interval;
  const timeouts = [];
  const playlistItems = [];

  const core = {
    status: {
      idle: false,
      paused: false,
      position: 12.5,
      duration: 120,
      speed: 1,
    },
    audio: {
      volume: 75,
      muted: false,
      id: 1,
      tracks: [{ id: 1, title: 'Stereo', lang: 'en', codec: 'aac', isSelected: true }],
    },
    subtitle: {
      id: 2,
      tracks: [{ id: 2, title: 'English', lang: 'en', codec: 'srt', isSelected: true }],
    },
    video: {
      tracks: [{ id: 3, title: 'Main', codec: 'hevc', isSelected: true }],
    },
    window: { loaded: true, fullscreen: false },
    open: (url) => {
      calls.push(['open', url]);
      playlistItems.splice(0, playlistItems.length, { filename: url, isPlaying: true });
    },
    pause: () => calls.push(['pause']),
    resume: () => calls.push(['resume']),
    stop: () => {
      calls.push(['stop']);
      core.status.idle = true;
    },
    seek: (seconds, exact) => calls.push(['seek', seconds, exact]),
    seekTo: (seconds) => calls.push(['seekTo', seconds]),
    setSpeed: (speed) => calls.push(['setSpeed', speed]),
  };

  const context = {
    iina: {
      core,
      event: { on: (name, callback) => eventHandlers.set(name, callback) },
      mpv: {
        set: (name, value) => {
          if (name === 'fullscreen') core.window.fullscreen = Boolean(value);
        },
      },
      playlist: {
        list: () => playlistItems.map((item) => ({ ...item })),
        add: (url, at = 0) => {
          calls.push(['playlist.add', url, at]);
          if (at === -1) {
            playlistItems.push({ filename: url, isPlaying: false });
          } else {
            playlistItems.splice(at, 0, { filename: url, isPlaying: false });
          }
        },
      },
      global: {
        getLabel: () => 'cinelark:6f55936d-5950-44fd-a696-f989d41785cc',
        onMessage: (name, callback) => messageHandlers.set(name, callback),
        postMessage: (name, data) => emitted.push([name, data]),
      },
    },
    setInterval: (callback) => {
      interval = callback;
      return 1;
    },
    setTimeout: (callback) => {
      timeouts.push(callback);
      return timeouts.length;
    },
    Date,
    Number,
    Boolean,
    Math,
  };
  const source = readFileSync(resolve(__dirname, '../src/main.js'), 'utf8');
  vm.runInNewContext(source, context, { filename: 'main.js' });
  return {
    calls,
    core,
    emitted,
    eventHandlers,
    messageHandlers,
    playPlaylistItem: (index) => {
      playlistItems.forEach((item, itemIndex) => {
        item.isPlaying = itemIndex === index;
      });
    },
    runInterval: () => interval(),
    runTimeouts: () => {
      while (timeouts.length > 0) timeouts.shift()();
    },
  };
}

function playCommand({
  sessionID = '6f55936d-5950-44fd-a696-f989d41785cc',
  url = currentEpisode.asset.playbackURL,
  startPositionSeconds = 42.5,
} = {}) {
  return {
    id: '4ff6c27e-1415-473f-8764-451d6a3369cb',
    type: 'player.play',
    sessionID,
    payload: {
      playbackID: sessionID,
      url,
      title: currentEpisode.title,
      startPositionSeconds,
      presentation: { fullscreen: true },
    },
  };
}

test('player opens the opaque URL and applies resume only after file-loaded', () => {
  const harness = makeHarness();
  harness.messageHandlers.get('cinelark.command')(playCommand());
  assert.deepEqual(harness.calls, []);
  harness.runTimeouts();
  assert.deepEqual(harness.calls, [['open', currentEpisode.asset.playbackURL]]);

  harness.eventHandlers.get('iina.file-loaded')();
  assert.deepEqual(harness.calls[1], ['seekTo', 42.5]);
  assert.deepEqual(harness.calls[2], ['resume']);
  assert.equal(harness.core.window.fullscreen, true);

  const events = harness.emitted.map(([, value]) => value);
  assert.equal(events.some((value) => value.type === 'player.fileLoaded'), true);
  assert.equal(events.some((value) => value.type === 'player.tracksChanged'), true);
  const serialized = JSON.stringify(events);
  assert.equal(serialized.includes('v1-vod1.uhdnow.com'), false);
  assert.equal(serialized.includes('token='), false);
});

test('managed player accepts a replacement playback session', () => {
  const harness = makeHarness();
  const send = harness.messageHandlers.get('cinelark.command');
  send(playCommand());
  harness.runTimeouts();

  const nextSessionID = '823daa90-8016-44de-88f2-78048f167d22';
  send(
    playCommand({
      sessionID: nextSessionID,
      url: nextEpisode.asset.playbackURL,
      startPositionSeconds: 0,
    })
  );
  harness.runTimeouts();

  assert.deepEqual(
    harness.calls.filter(([name]) => name === 'open'),
    [
      ['open', currentEpisode.asset.playbackURL],
      ['open', nextEpisode.asset.playbackURL],
    ]
  );
});

test('managed player appends and identifies the next native playlist item', () => {
  const harness = makeHarness();
  const sessionID = playCommand().sessionID;
  const nextPlaybackID = '823daa90-8016-44de-88f2-78048f167d22';
  const send = harness.messageHandlers.get('cinelark.command');

  send(playCommand({ sessionID, startPositionSeconds: 0 }));
  harness.runTimeouts();
  send({
    id: 'a1c70256-6834-4c91-bbea-acde18cc63c8',
    type: 'player.enqueue',
    sessionID,
    payload: {
      playbackID: nextPlaybackID,
      url: nextEpisode.asset.playbackURL,
      title: nextEpisode.title,
      startPositionSeconds: 0,
    },
  });
  harness.runTimeouts();

  assert.equal(
    harness.calls.some(
      (call) => call[0] === 'playlist.add'
        && call[1] === nextEpisode.asset.playbackURL
        && call[2] === -1
    ),
    true
  );

  harness.eventHandlers.get('iina.file-loaded')();
  harness.eventHandlers.get('mpv.end-file')({ reason: 'eof' });
  harness.playPlaylistItem(1);
  harness.core.status.idle = false;
  harness.eventHandlers.get('iina.file-loaded')();

  const loadedEvents = harness.emitted
    .map(([, value]) => value)
    .filter((value) => value.type === 'player.fileLoaded');
  assert.equal(loadedEvents.length, 2);
  assert.equal(loadedEvents[1].payload.playbackID, nextPlaybackID);
});

test('natural EOF reports completion after mpv enters its stopped state', () => {
  const harness = makeHarness();
  harness.messageHandlers.get('cinelark.command')(playCommand());
  harness.runTimeouts();
  harness.eventHandlers.get('iina.file-loaded')();

  harness.core.status.position = 0;
  harness.core.status.duration = 0;
  harness.core.status.idle = true;
  harness.core.status.paused = true;
  harness.eventHandlers.get('mpv.pause.changed')();
  harness.eventHandlers.get('mpv.end-file')({ reason: 'eof' });

  const terminalEvents = harness.emitted
    .map(([, value]) => value)
    .filter((value) => value.type === 'player.positionChanged' || value.type === 'player.ended')
    .slice(-2);
  assert.equal(terminalEvents[0].type, 'player.positionChanged');
  assert.deepEqual(
    JSON.parse(JSON.stringify(terminalEvents[0].payload)),
    { positionSeconds: 120, durationSeconds: 120 }
  );
  assert.equal(terminalEvents[1].type, 'player.ended');
  assert.equal(terminalEvents[1].payload.reason, 'eof');
});

test('idle fallback reports short playback when IINA closes the player window', () => {
  const harness = makeHarness();
  harness.messageHandlers.get('cinelark.command')(playCommand({ startPositionSeconds: 0 }));
  harness.runTimeouts();
  harness.eventHandlers.get('iina.file-loaded')();

  harness.core.status.position = 8.25;
  harness.runInterval();
  harness.core.status.position = 0;
  harness.core.status.duration = 0;
  harness.core.status.idle = true;
  harness.eventHandlers.get('mpv.idle-active.changed')();
  harness.runTimeouts();

  const events = harness.emitted.map(([, value]) => value);
  const closed = events.find((value) => value.type === 'player.closed');
  const finalPosition = events
    .filter((value) => value.type === 'player.positionChanged')
    .at(-1);
  assert.equal(closed.payload.reason, 'player_stopped');
  assert.deepEqual(
    JSON.parse(JSON.stringify(finalPosition.payload)),
    { positionSeconds: 8.25, durationSeconds: 120 }
  );
});

test('transport commands map to the public IINA core APIs', () => {
  const harness = makeHarness();
  const send = harness.messageHandlers.get('cinelark.command');
  send(playCommand());
  send({ type: 'player.pause', sessionID: playCommand().sessionID, payload: {} });
  send({
    type: 'player.seekRelative',
    sessionID: playCommand().sessionID,
    payload: { seconds: 15, exact: true },
  });
  send({
    type: 'player.setVolume',
    sessionID: playCommand().sessionID,
    payload: { volume: 55 },
  });
  send({
    type: 'player.selectSubtitleTrack',
    sessionID: playCommand().sessionID,
    payload: { id: 7 },
  });
  assert.equal(harness.calls.length, 0);
  harness.runTimeouts();

  assert.equal(harness.calls.some(([name]) => name === 'pause'), true);
  assert.equal(harness.calls.some((call) => JSON.stringify(call) === '["seek",15,true]'), true);
  assert.equal(harness.core.audio.volume, 55);
  assert.equal(harness.core.subtitle.id, 7);
});

test('position sampling emits sanitized state without the source URL', () => {
  const harness = makeHarness();
  harness.messageHandlers.get('cinelark.command')(playCommand());
  harness.runTimeouts();
  harness.runInterval();
  const position = harness.emitted
    .map(([, value]) => value)
    .find((value) => value.type === 'player.positionChanged');
  assert.deepEqual(
    JSON.parse(JSON.stringify(position.payload)),
    { positionSeconds: 12.5, durationSeconds: 120 }
  );
});
