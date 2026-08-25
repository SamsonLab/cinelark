'use strict';

const { core, event, global, mpv, playlist } = iina;
const pluginConsole = iina.console;

const label = global.getLabel();
const isCineLarkManagedPlayer = typeof label === 'string' && label.startsWith('cinelark:');

let activeSession = null;
let pendingFullscreen = false;
let pendingAutoplay = false;
let lastPositionEmission = 0;
let lastPositionSeconds = 0;
let lastDurationSeconds = 0;
let hasLoadedCurrentMedia = false;
let terminalEventSent = false;
let lastEndReason = null;
let eofReached = false;
let idleFinalizationPending = false;
let sessionClosed = false;
let queueEntries = [];
let pendingReplacement = null;
let isQuiesced = false;
const pendingTimers = new Set();
const pendingIntervals = new Set();

const EOF_REPLACEMENT_GRACE_MS = 30000;
const COMPLETION_EPSILON_SECONDS = 0.001;
const PLAYBACK_POLL_INTERVAL_MS = 500;

function shortID(value) {
  return typeof value === 'string' ? value.slice(0, 8) : 'none';
}

function log(message, fields = {}) {
  if (isQuiesced) return;
  if (!pluginConsole || typeof pluginConsole.log !== 'function') return;
  pluginConsole.log(`[CineLark/player] ${message} ${JSON.stringify(fields)}`);
}

function scheduleTimer(callback, milliseconds = 0) {
  if (isQuiesced) return null;
  let timerID = null;
  timerID = setTimeout(() => {
    pendingTimers.delete(timerID);
    if (isQuiesced) return;
    callback();
  }, milliseconds);
  pendingTimers.add(timerID);
  return timerID;
}

function scheduleInterval(callback, milliseconds) {
  if (isQuiesced) return null;
  const intervalID = setInterval(() => {
    if (isQuiesced) return;
    callback();
  }, milliseconds);
  pendingIntervals.add(intervalID);
  return intervalID;
}

function quiescePlayer() {
  isQuiesced = true;
  for (const timerID of pendingTimers) clearTimeout(timerID);
  pendingTimers.clear();
  for (const intervalID of pendingIntervals) clearInterval(intervalID);
  pendingIntervals.clear();
}

function onEvent(name, callback) {
  event.on(name, (...args) => {
    if (isQuiesced) return;
    callback(...args);
  });
}

function emit(type, payload = {}, replyTo = null) {
  if (isQuiesced || !activeSession) return;
  if (type === 'player.fileLoaded' || type === 'player.ended' || type === 'player.closed') {
    log('emitting lifecycle event', {
      type,
      session: shortID(activeSession.sessionID),
      playback: shortID(activeSession.playbackID),
      reason: payload.reason || null,
    });
  }
  global.postMessage('cinelark.event', {
    type,
    payload,
    sessionID: activeSession.sessionID,
    replyTo,
  });
}

function finiteNumber(value, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function keepManagedPlayerOpen() {
  mpv.set('keep-open', 'yes');
  try {
    return mpv.getString('keep-open');
  } catch (_) {
    return 'unavailable';
  }
}

function playbackEntry(payload, sessionID) {
  if (!payload || typeof payload.url !== 'string' || typeof payload.playbackID !== 'string') {
    return null;
  }
  return {
    sessionID,
    playbackID: payload.playbackID,
    url: payload.url,
    title: typeof payload.title === 'string' ? payload.title : '',
    startPositionSeconds: Math.max(0, finiteNumber(payload.startPositionSeconds)),
  };
}

function activatePlayingEntry() {
  const items = playlist.list() || [];
  const playingIndex = items.findIndex((item) => item && item.isPlaying);
  const playing = playingIndex >= 0 ? items[playingIndex] : null;
  const entry = playing
    ? queueEntries.find((candidate) => candidate.url === playing.filename)
      || queueEntries[playingIndex]
    : null;
  if (!entry) return null;
  activeSession = entry;
  if (pendingReplacement && pendingReplacement.playbackID === entry.playbackID) {
    pendingReplacement = null;
  }
  return activeSession;
}

function snapshot() {
  const idle = Boolean(core.status.idle);
  const paused = Boolean(core.status.paused);
  const positionSeconds = Math.max(0, finiteNumber(core.status.position));
  const durationSeconds = Math.max(0, finiteNumber(core.status.duration));
  if (positionSeconds > 0) lastPositionSeconds = positionSeconds;
  if (durationSeconds > 0) lastDurationSeconds = durationSeconds;
  return {
    state: idle ? 'stopped' : paused ? 'paused' : 'playing',
    positionSeconds,
    durationSeconds,
    speed: Math.max(0, finiteNumber(core.status.speed, 1)),
    volume: Math.max(0, finiteNumber(core.audio.volume)),
    muted: Boolean(core.audio.muted),
    fullscreen: Boolean(core.window.fullscreen),
  };
}

function sanitizedTrack(track) {
  return {
    id: track.id,
    title: track.title || null,
    formattedTitle: track.formattedTitle || null,
    language: track.lang || null,
    codec: track.codec || null,
    isDefault: Boolean(track.isDefault),
    isForced: Boolean(track.isForced),
    isSelected: Boolean(track.isSelected),
    isExternal: Boolean(track.isExternal),
    width: track.demuxW || null,
    height: track.demuxH || null,
    channelCount: track.demuxChannelCount || null,
    channels: track.demuxChannels || null,
    sampleRate: track.demuxSamplerate || null,
    frameRate: track.demuxFPS || null,
  };
}

function emitTracks() {
  emit('player.tracksChanged', {
    audio: (core.audio.tracks || []).map(sanitizedTrack),
    subtitles: (core.subtitle.tracks || []).map(sanitizedTrack),
    video: (core.video.tracks || []).map(sanitizedTrack),
  });
}

function emitState(replyTo = null) {
  emit('player.stateChanged', snapshot(), replyTo);
}

function emitPosition(replyTo = null, completed = false) {
  const state = snapshot();
  const durationSeconds = Math.max(state.durationSeconds, lastDurationSeconds);
  const positionSeconds = completed && durationSeconds > 0
    ? durationSeconds
    : Math.max(state.positionSeconds, lastPositionSeconds);
  emit(
    'player.positionChanged',
    { positionSeconds, durationSeconds },
    replyTo
  );
}

function applyPendingFullscreen() {
  if (pendingFullscreen && core.window.loaded && !core.window.fullscreen) {
    mpv.set('fullscreen', true);
  }
}

function scheduleIdleFinalization() {
  if (
    !activeSession ||
    !hasLoadedCurrentMedia ||
    sessionClosed ||
    idleFinalizationPending ||
    !core.status.idle
  ) {
    return;
  }
  idleFinalizationPending = true;
  const finalizingPlaybackID = activeSession.playbackID;
  const delayMilliseconds = terminalEventSent && lastEndReason === 'eof'
    ? EOF_REPLACEMENT_GRACE_MS
    : 750;
  log('scheduled idle finalization', {
    playback: shortID(finalizingPlaybackID),
    reason: lastEndReason,
    delayMilliseconds,
  });
  scheduleTimer(() => {
    if (!activeSession || activeSession.playbackID !== finalizingPlaybackID) return;
    idleFinalizationPending = false;
    if (sessionClosed || !core.status.idle) return;
    sessionClosed = true;
    log('idle finalization closed the managed session', {
      playback: shortID(activeSession.playbackID),
      reason: terminalEventSent ? 'playlist_ended' : 'player_stopped',
    });
    if (!terminalEventSent) emitPosition();
    emit('player.closed', {
      reason: terminalEventSent ? 'playlist_ended' : 'player_stopped',
      playbackID: activeSession.playbackID,
    });
    activeSession = null;
    queueEntries = [];
  }, delayMilliseconds);
}

onEvent('iina.file-loaded', () => {
  if (!activatePlayingEntry()) return;
  hasLoadedCurrentMedia = true;
  terminalEventSent = false;
  lastEndReason = null;
  eofReached = false;
  idleFinalizationPending = false;
  lastPositionSeconds = Math.max(0, activeSession.startPositionSeconds);
  lastDurationSeconds = 0;
  const resumePosition = finiteNumber(activeSession.startPositionSeconds);
  if (resumePosition > 0) core.seekTo(resumePosition);
  if (pendingAutoplay) core.resume();
  pendingAutoplay = false;
  applyPendingFullscreen();
  const keepOpen = keepManagedPlayerOpen();
  log('file loaded', {
    session: shortID(activeSession.sessionID),
    playback: shortID(activeSession.playbackID),
    keepOpen,
  });
  emit('player.fileLoaded', {
    playbackID: activeSession.playbackID,
    resumedAtSeconds: Math.max(0, resumePosition),
  });
  emitTracks();
  emitState();
  emitPosition();
});

onEvent('iina.window-loaded', () => {
  applyPendingFullscreen();
});

onEvent('mpv.pause.changed', () => {
  if (!activeSession || !hasLoadedCurrentMedia) {
    log('ignored pause transition while replacement is loading', {
      playback: activeSession ? shortID(activeSession.playbackID) : 'none',
      pending: pendingReplacement ? shortID(pendingReplacement.playbackID) : 'none',
    });
    return;
  }
  emitState();
  emitPosition();
  const paused = Boolean(core.status.paused);
  const completed = playbackReachedCompletion();
  if (paused) {
    log('playback paused', {
      playback: activeSession ? shortID(activeSession.playbackID) : 'none',
      completed,
      positionSeconds: lastPositionSeconds,
      durationSeconds: lastDurationSeconds,
    });
  }
  if (paused && completed) {
    finishPlayback('eof', 'pause-at-completion');
  }
});

function currentEOFReached() {
  try {
    return Boolean(mpv.getFlag('eof-reached'));
  } catch (_) {
    return false;
  }
}

function playbackIsNearEnd() {
  const durationSeconds = Math.max(lastDurationSeconds, finiteNumber(core.status.duration));
  const positionSeconds = Math.max(lastPositionSeconds, finiteNumber(core.status.position));
  if (durationSeconds <= 0) return false;
  const toleranceSeconds = Math.max(2, durationSeconds * 0.01);
  return positionSeconds >= durationSeconds - toleranceSeconds;
}

function playbackReachedCompletion() {
  const durationSeconds = Math.max(lastDurationSeconds, finiteNumber(core.status.duration));
  const positionSeconds = Math.max(lastPositionSeconds, finiteNumber(core.status.position));
  const remainingSeconds = durationSeconds - positionSeconds;
  return durationSeconds > 0
    && remainingSeconds >= -0.5
    && remainingSeconds <= COMPLETION_EPSILON_SECONDS;
}

function pollPlaybackCompletion() {
  if (!activeSession || terminalEventSent || !hasLoadedCurrentMedia) return;
  snapshot();
  if (!playbackReachedCompletion()) return;
  log('polling observed completed playback', {
    playback: shortID(activeSession.playbackID),
    positionSeconds: lastPositionSeconds,
    durationSeconds: lastDurationSeconds,
  });
  // Freeze the final frame before IINA can apply its close-at-end policy. The
  // coordinator will stop this session and open the replacement in this player.
  core.pause();
  finishPlayback('eof', 'completion-poll');
}

function finishPlayback(reason, source) {
  if (!activeSession || !hasLoadedCurrentMedia || terminalEventSent) return;
  terminalEventSent = true;
  lastEndReason = reason;
  log('detected playback end', {
    playback: shortID(activeSession.playbackID),
    reason,
    source,
    positionSeconds: lastPositionSeconds,
    durationSeconds: lastDurationSeconds,
  });
  emitPosition(null, reason === 'eof');
  emit('player.ended', { reason, playbackID: activeSession.playbackID });
  scheduleIdleFinalization();
}

onEvent('mpv.eof-reached.changed', () => {
  if (!activeSession || !hasLoadedCurrentMedia) {
    log('ignored eof-reached transition while replacement is loading', {
      playback: activeSession ? shortID(activeSession.playbackID) : 'none',
      pending: pendingReplacement ? shortID(pendingReplacement.playbackID) : 'none',
    });
    return;
  }
  eofReached = currentEOFReached();
  log('eof-reached property changed', {
    playback: activeSession ? shortID(activeSession.playbackID) : 'none',
    eofReached,
  });
  if (eofReached) finishPlayback('eof', 'eof-reached');
});

// IINA's generic mpv.* plugin callback does not expose mpv's event detail
// object. Observe eof-reached above and use sampled position only as a fallback.
onEvent('mpv.end-file', () => {
  if (!activeSession || !hasLoadedCurrentMedia) {
    log('ignored end-file while replacement is loading', {
      playback: activeSession ? shortID(activeSession.playbackID) : 'none',
      pending: pendingReplacement ? shortID(pendingReplacement.playbackID) : 'none',
    });
    return;
  }
  const naturalEOF = eofReached || currentEOFReached() || playbackIsNearEnd();
  finishPlayback(naturalEOF ? 'eof' : 'unknown', naturalEOF ? 'end-file-fallback' : 'end-file');
});

onEvent('mpv.idle-active.changed', () => {
  scheduleIdleFinalization();
});

event.on('iina.window-will-close', () => {
  if (!isCineLarkManagedPlayer || isQuiesced) return;
  try {
    if ((!activeSession && !pendingReplacement) || sessionClosed) return;
    if (pendingReplacement && !hasLoadedCurrentMedia) {
      activeSession = pendingReplacement;
      pendingReplacement = null;
      terminalEventSent = false;
      lastEndReason = null;
      lastPositionSeconds = Math.max(0, activeSession.startPositionSeconds);
      lastDurationSeconds = 0;
    }
    const nearEnd = hasLoadedCurrentMedia && playbackIsNearEnd();
    log('managed window will close', {
      playback: shortID(activeSession.playbackID),
      terminalEventSent,
      nearEnd,
      positionSeconds: lastPositionSeconds,
      durationSeconds: lastDurationSeconds,
    });
    if (!terminalEventSent && nearEnd) {
      finishPlayback('eof', 'window-close-fallback');
    }
    sessionClosed = true;
    if (!terminalEventSent) emitPosition();
    emit('player.closed', {
      reason: 'window_closed',
      playbackID: activeSession.playbackID,
    });
    activeSession = null;
    queueEntries = [];
    pendingReplacement = null;
  } finally {
    try {
      global.postMessage('cinelark.player-will-close', {});
    } finally {
      quiescePlayer();
    }
  }
});

function handleCommand(command) {
  if (isQuiesced || !isCineLarkManagedPlayer || !command || !command.sessionID) return;
  global.postMessage('cinelark.player-ack', { commandID: command.id });

  if (command.type === 'player.play') {
    const payload = command.payload || {};
    const entry = playbackEntry(payload, command.sessionID);
    if (!entry) return;
    const outgoingSession = activeSession;
    if (outgoingSession) {
      pendingReplacement = entry;
    } else {
      activeSession = entry;
      pendingReplacement = null;
      lastPositionSeconds = Math.max(0, entry.startPositionSeconds);
      lastDurationSeconds = 0;
      terminalEventSent = false;
      lastEndReason = null;
    }
    queueEntries = [entry];
    pendingFullscreen = Boolean(payload.presentation && payload.presentation.fullscreen);
    pendingAutoplay = true;
    hasLoadedCurrentMedia = false;
    eofReached = false;
    idleFinalizationPending = false;
    sessionClosed = false;
    log('received replacement play command', {
      session: shortID(entry.sessionID),
      playback: shortID(entry.playbackID),
      outgoingPlayback: outgoingSession ? shortID(outgoingSession.playbackID) : 'none',
      reusingLoadedWindow: Boolean(core.window.loaded),
    });
    // Keep CineLark's managed window alive at natural EOF. This allows the
    // eof-reached property event to request and open the next episode before
    // IINA applies its normal close-at-end window policy.
    keepManagedPlayerOpen();
    core.open(payload.url);
    return;
  }

  if (!activeSession || command.sessionID !== activeSession.sessionID) return;
  const payload = command.payload || {};
  if (command.type === 'player.enqueue') {
    const entry = playbackEntry(payload, command.sessionID);
    if (!entry || queueEntries.some((candidate) => candidate.playbackID === entry.playbackID)) {
      return;
    }
    queueEntries.push(entry);
    // IINA's JSExport bridge converts an omitted integer argument to 0 even
    // though the Swift implementation declares -1 as its default. Pass -1
    // explicitly so queued episodes are appended after the playing item.
    playlist.add(entry.url, -1);
    return;
  }
  switch (command.type) {
    case 'player.pause':
      core.pause();
      break;
    case 'player.resume':
      core.resume();
      break;
    case 'player.stop':
      emitPosition(command.id);
      core.stop();
      emitState(command.id);
      break;
    case 'player.seekRelative':
      core.seek(finiteNumber(payload.seconds), Boolean(payload.exact));
      break;
    case 'player.seekAbsolute':
      core.seekTo(Math.max(0, finiteNumber(payload.seconds)));
      break;
    case 'player.setSpeed':
      core.setSpeed(Math.max(0.1, finiteNumber(payload.speed, 1)));
      emitState(command.id);
      break;
    case 'player.setVolume':
      core.audio.volume = Math.max(0, finiteNumber(payload.volume));
      emitState(command.id);
      break;
    case 'player.setMuted':
      core.audio.muted = Boolean(payload.muted);
      emitState(command.id);
      break;
    case 'player.setFullscreen':
      mpv.set('fullscreen', Boolean(payload.fullscreen));
      emitState(command.id);
      break;
    case 'player.selectAudioTrack':
      if (Number.isInteger(payload.id)) {
        core.audio.id = payload.id;
        emitTracks();
      }
      break;
    case 'player.selectSubtitleTrack':
      if (Number.isInteger(payload.id)) {
        core.subtitle.id = payload.id;
        emitTracks();
      }
      break;
    case 'player.disableSubtitles':
      mpv.set('sid', 'no');
      emitTracks();
      break;
    case 'player.requestState':
      emitState(command.id);
      emitPosition(command.id);
      emitTracks();
      break;
    default:
      break;
  }
}

// IINA's global message hub invokes listeners on the caller's queue. Broker
// responses arrive on an NSURLSession delegate queue, while player/core APIs
// must execute on the main run loop. IINA timers provide that queue hop.
global.onMessage('cinelark.command', (command) => {
  scheduleTimer(() => handleCommand(command), 0);
});

scheduleInterval(() => {
  if (!activeSession) return;
  pollPlaybackCompletion();
  if (core.status.idle) {
    scheduleIdleFinalization();
    return;
  }
  const now = Date.now();
  if (now - lastPositionEmission >= 1000) {
    lastPositionEmission = now;
    emitPosition();
  }
}, PLAYBACK_POLL_INTERVAL_MS);
