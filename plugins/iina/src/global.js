'use strict';

const {
  PROTOCOL_VERSION,
  base64UrlDecode,
  createEnvelope,
  requestHeaders,
  verifyEnvelope,
} = require('./lib/protocol.js');

const { global, http, menu, utils } = iina;
const pluginConsole = iina.console;

const PLUGIN_VERSION = '0.1.19';
const KEYCHAIN_SERVICE = 'bridge';
const KEYCHAIN_ACCOUNT = 'pairing-key';
const PORT_START = 43191;
const PORT_END = 43200;
const RETRY_DELAY_MS = 3000;

let connectionGeneration = 0;
let eventSequence = 0;
let lastCommandSequence = 0;
let currentPlayer = null;
let pendingPlayerReuse = null;
let baseURL = null;
let secret = null;
let eventQueue = Promise.resolve();
let transportQuiesced = false;
const pendingTimers = new Set();

function shortID(value) {
  return typeof value === 'string' ? value.slice(0, 8) : 'none';
}

function log(message, fields = {}) {
  if (transportQuiesced) return;
  if (!pluginConsole || typeof pluginConsole.log !== 'function') return;
  pluginConsole.log(`[CineLark/global] ${message} ${JSON.stringify(fields)}`);
}

function scheduleTimer(callback, milliseconds = 0) {
  if (transportQuiesced) return null;
  let timerID = null;
  timerID = setTimeout(() => {
    pendingTimers.delete(timerID);
    if (transportQuiesced) return;
    callback();
  }, milliseconds);
  pendingTimers.add(timerID);
  return timerID;
}

function cancelPendingTimers() {
  for (const timerID of pendingTimers) clearTimeout(timerID);
  pendingTimers.clear();
}

function quiesceTransport() {
  transportQuiesced = true;
  pendingPlayerReuse = null;
  cancelPendingTimers();
}

function resumeTransport() {
  cancelPendingTimers();
  transportQuiesced = false;
}

function delay(milliseconds) {
  return new Promise((resolve) => scheduleTimer(resolve, milliseconds));
}

function runOnMain(operation) {
  return new Promise((resolve, reject) => {
    scheduleTimer(() => {
      try {
        const result = operation();
        if (result && typeof result.then === 'function') {
          result.then(resolve, reject);
        } else {
          resolve(result);
        }
      } catch (error) {
        reject(error);
      }
    }, 0);
  });
}

function authenticatedHeaders(method, uri) {
  return requestHeaders({ secret, method, uri });
}

async function get(uri) {
  return runOnMain(() => http.get(`${baseURL}${uri}`, {
    headers: authenticatedHeaders('GET', uri),
  }));
}

async function post(uri, data) {
  return runOnMain(() => http.post(`${baseURL}${uri}`, {
    headers: {
      ...authenticatedHeaders('POST', uri),
      'Content-Type': 'application/json',
    },
    data,
  }));
}

async function discoverBroker() {
  for (let port = PORT_START; port <= PORT_END; port += 1) {
    const candidate = `http://127.0.0.1:${port}`;
    try {
      const response = await runOnMain(() => http.get(`${candidate}/v1/health`));
      if (
        response.statusCode === 200 &&
        response.data &&
        response.data.protocolVersion === PROTOCOL_VERSION
      ) {
        return candidate;
      }
    } catch (_) {
      // Port probing is expected while CineLark is not running.
      if (transportQuiesced) return null;
    }
  }
  return null;
}

function emit(type, payload = {}, sessionID = null, replyTo = null) {
  if (transportQuiesced || !baseURL || !secret) return;
  const generation = connectionGeneration;
  const envelope = createEnvelope({
    type,
    payload,
    sequence: eventSequence,
    sessionID,
    replyTo,
    secret,
  });
  eventSequence += 1;
  eventQueue = eventQueue
    .then(() => {
      if (transportQuiesced || generation !== connectionGeneration || !baseURL) return null;
      if (type === 'player.fileLoaded' || type === 'player.ended' || type === 'player.closed') {
        log('forwarding lifecycle event to broker', {
          type,
          session: shortID(sessionID),
          reason: payload.reason || null,
        });
      }
      return post('/v1/plugin/events', envelope);
    })
    .catch(() => {
      if (transportQuiesced) return;
      log('broker event delivery failed; reconnecting', { type });
      if (generation === connectionGeneration) baseURL = null;
    });
}

function emitBeforeTeardown(type, payload = {}, sessionID = null, replyTo = null) {
  if (transportQuiesced || !baseURL || !secret) return;
  const uri = '/v1/plugin/events';
  const envelope = createEnvelope({
    type,
    payload,
    sequence: eventSequence,
    sessionID,
    replyTo,
    secret,
  });
  eventSequence += 1;
  try {
    const request = http.post(`${baseURL}${uri}`, {
      headers: {
        ...authenticatedHeaders('POST', uri),
        'Content-Type': 'application/json',
      },
      data: envelope,
    });
    if (request && typeof request.catch === 'function') request.catch(() => null);
  } catch (_) {
    // Teardown is already in progress; no retry may outlive the plugin owner.
  }
}

function createManagedPlayer(command) {
  const playerID = global.createPlayerInstance({
    label: 'cinelark:managed',
    disableWindowAnimation: false,
    disableUI: false,
    enablePlugins: false,
  });
  currentPlayer = { id: playerID, sessionID: command.sessionID };
  log('created managed player', {
    playerID,
    session: shortID(command.sessionID),
  });
  global.postMessage(playerID, 'cinelark.command', command);
}

function handleCommand(command) {
  if (transportQuiesced) return;
  if (!verifyEnvelope(command, secret) || command.sequence <= lastCommandSequence) {
    return;
  }
  lastCommandSequence = command.sequence;

  if (command.type === 'player.play') {
    if (!currentPlayer) {
      log('dispatching play command to a new player', {
        command: shortID(command.id),
        session: shortID(command.sessionID),
      });
      createManagedPlayer(command);
      return;
    }

    log('dispatching replacement play command', {
      command: shortID(command.id),
      session: shortID(command.sessionID),
      playerID: currentPlayer.id,
    });
    currentPlayer.sessionID = command.sessionID;
    pendingPlayerReuse = { commandID: command.id, command };
    global.postMessage(currentPlayer.id, 'cinelark.command', command);
    scheduleTimer(() => {
      if (!pendingPlayerReuse || pendingPlayerReuse.commandID !== command.id) return;
      log('replacement acknowledgement timed out; preserving the same-player invariant', {
        command: shortID(command.id),
      });
      pendingPlayerReuse = null;
      emit(
        'bridge.error',
        {
          code: 'replacement_timeout',
          message: 'The managed player did not acknowledge content replacement.',
        },
        command.sessionID,
        command.id
      );
    }, 500);
    return;
  }

  if (!currentPlayer || command.sessionID !== currentPlayer.sessionID) {
    emit(
      'bridge.error',
      { code: 'stale_session', message: 'The command does not match the active player.' },
      command.sessionID,
      command.id
    );
    return;
  }
  global.postMessage(currentPlayer.id, 'cinelark.command', command);
}

async function hello() {
  const envelope = createEnvelope({
    type: 'bridge.hello',
    payload: {
      pluginVersion: PLUGIN_VERSION,
      protocolVersion: PROTOCOL_VERSION,
    },
    sequence: eventSequence,
    secret,
  });
  eventSequence += 1;
  const response = await post('/v1/plugin/hello', envelope);
  if (
    response.statusCode !== 200 ||
    !response.data ||
    response.data.protocolVersion !== PROTOCOL_VERSION
  ) {
    throw new Error('Bridge protocol negotiation failed');
  }
  emit('bridge.ready', {
    pluginVersion: PLUGIN_VERSION,
    protocolVersion: PROTOCOL_VERSION,
  });
  log('connected to CineLark broker', { pluginVersion: PLUGIN_VERSION });
}

async function poll(generation) {
  while (generation === connectionGeneration && baseURL && !transportQuiesced) {
    const uri = `/v1/plugin/commands?after=${lastCommandSequence}`;
    try {
      const response = await get(uri);
      if (response.statusCode !== 200 || !response.data || !Array.isArray(response.data.commands)) {
        throw new Error('Invalid command response');
      }
      const commands = response.data.commands;
      if (transportQuiesced) {
        const hasAuthenticatedPlayCommand = commands.some(
          (command) => command.type === 'player.play' && verifyEnvelope(command, secret)
        );
        if (!hasAuthenticatedPlayCommand) break;
        resumeTransport();
      }
      // HTTP promises resolve on IINA's NSURLSession delegate queue. Managed
      // player APIs are main-run-loop-only, so use IINA's timer polyfill as the
      // documented queue hop before creating a player or posting its command.
      for (const command of commands) {
        scheduleTimer(() => handleCommand(command), 0);
      }
    } catch (_) {
      if (transportQuiesced) break;
      baseURL = null;
      break;
    }
  }
}

async function connect() {
  if (transportQuiesced) return;
  const generation = ++connectionGeneration;

  try {
    // Do not touch Keychain while CineLark is absent. This prevents IINA from
    // presenting an authorization dialog on every background retry.
    baseURL = await discoverBroker();
    if (transportQuiesced) return;
    if (!baseURL) throw new Error('Broker unavailable');

    if (!secret) {
      const storedSecret = await runOnMain(
        () => utils.keychainRead(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
      );
      if (transportQuiesced) return;
      if (typeof storedSecret !== 'string') {
        throw new Error('CineLark Bridge is waiting for Keychain pairing.');
      }
      const decoded = base64UrlDecode(storedSecret);
      if (decoded.length !== 32) throw new Error('Invalid pairing key');
      secret = decoded;
    }

    eventSequence = 0;
    lastCommandSequence = 0;
    await hello();
    if (transportQuiesced) return;
    await poll(generation);
  } catch (error) {
    if (transportQuiesced) return;
    if (error && error.statusCode === 401) secret = null;
    baseURL = null;
  }

  if (transportQuiesced) return;
  await delay(RETRY_DELAY_MS);
  if (!transportQuiesced && generation === connectionGeneration) connect();
}

global.onMessage('cinelark.player-ack', (ack) => {
  if (transportQuiesced) return;
  if (!ack || !pendingPlayerReuse || ack.commandID !== pendingPlayerReuse.commandID) return;
  log('managed player acknowledged replacement', { command: shortID(ack.commandID) });
  pendingPlayerReuse = null;
});

global.onMessage('cinelark.event', (event) => {
  if (transportQuiesced) return;
  if (!event || typeof event.type !== 'string') return;
  if (event.type === 'player.fileLoaded' || event.type === 'player.ended' || event.type === 'player.closed') {
    log('received lifecycle event from managed player', {
      type: event.type,
      session: shortID(event.sessionID),
      reason: event.payload && event.payload.reason ? event.payload.reason : null,
    });
  }
  const forward = event.type === 'player.closed' ? emitBeforeTeardown : emit;
  forward(event.type, event.payload || {}, event.sessionID || null, event.replyTo || null);
  const endedWithoutReuse =
    event.type === 'player.ended' && event.payload && event.payload.reason !== 'eof';
  if (event.type === 'player.closed' || endedWithoutReuse) {
    if (currentPlayer && currentPlayer.sessionID === event.sessionID) currentPlayer = null;
  }
});

global.onMessage('cinelark.player-will-close', () => {
  currentPlayer = null;
  quiesceTransport();
});

menu.addItem(
  menu.item('Reconnect CineLark Bridge', () => {
    resumeTransport();
    baseURL = null;
    secret = null;
    connect();
  })
);

connect();
