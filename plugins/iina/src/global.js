'use strict';

const {
  PROTOCOL_VERSION,
  base64UrlDecode,
  createEnvelope,
  requestHeaders,
  verifyEnvelope,
} = require('./lib/protocol.js');

const { global, http, menu, utils } = iina;

const PLUGIN_VERSION = '0.1.3';
const KEYCHAIN_SERVICE = 'bridge';
const KEYCHAIN_ACCOUNT = 'pairing-key';
const PORT_START = 43191;
const PORT_END = 43200;
const RETRY_DELAY_MS = 3000;

let connectionGeneration = 0;
let eventSequence = 0;
let lastCommandSequence = 0;
let currentPlayer = null;
let baseURL = null;
let secret = null;
let eventQueue = Promise.resolve();

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function runOnMain(operation) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
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
    }
  }
  return null;
}

function emit(type, payload = {}, sessionID = null, replyTo = null) {
  if (!baseURL || !secret) return;
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
      if (generation !== connectionGeneration || !baseURL) return null;
      return post('/v1/plugin/events', envelope);
    })
    .catch(() => {
      if (generation === connectionGeneration) baseURL = null;
    });
}

function handleCommand(command) {
  if (!verifyEnvelope(command, secret) || command.sequence <= lastCommandSequence) {
    return;
  }
  lastCommandSequence = command.sequence;

  if (command.type === 'player.play') {
    const playerID = global.createPlayerInstance({
      label: `cinelark:${command.sessionID}`,
      disableWindowAnimation: false,
      disableUI: false,
      enablePlugins: false,
    });
    currentPlayer = { id: playerID, sessionID: command.sessionID };
    global.postMessage(playerID, 'cinelark.command', command);
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
}

async function poll(generation) {
  while (generation === connectionGeneration && baseURL) {
    const uri = `/v1/plugin/commands?after=${lastCommandSequence}`;
    try {
      const response = await get(uri);
      if (response.statusCode !== 200 || !response.data || !Array.isArray(response.data.commands)) {
        throw new Error('Invalid command response');
      }
      // HTTP promises resolve on IINA's NSURLSession delegate queue. Managed
      // player APIs are main-run-loop-only, so use IINA's timer polyfill as the
      // documented queue hop before creating a player or posting its command.
      for (const command of response.data.commands) {
        setTimeout(() => handleCommand(command), 0);
      }
    } catch (_) {
      baseURL = null;
      break;
    }
  }
}

async function connect() {
  const generation = ++connectionGeneration;

  try {
    // Do not touch Keychain while CineLark is absent. This prevents IINA from
    // presenting an authorization dialog on every background retry.
    baseURL = await discoverBroker();
    if (!baseURL) throw new Error('Broker unavailable');

    if (!secret) {
      const storedSecret = await runOnMain(
        () => utils.keychainRead(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
      );
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
    await poll(generation);
  } catch (error) {
    if (error && error.statusCode === 401) secret = null;
    baseURL = null;
  }

  await delay(RETRY_DELAY_MS);
  if (generation === connectionGeneration) connect();
}

global.onMessage('cinelark.event', (event) => {
  if (!event || typeof event.type !== 'string') return;
  emit(event.type, event.payload || {}, event.sessionID || null, event.replyTo || null);
  if (event.type === 'player.closed' || event.type === 'player.ended') {
    if (currentPlayer && currentPlayer.sessionID === event.sessionID) currentPlayer = null;
  }
});

menu.addItem(
  menu.item('Reconnect CineLark Bridge', () => {
    baseURL = null;
    secret = null;
    connect();
  })
);

connect();
