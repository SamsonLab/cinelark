'use strict';

const { core, event, global } = iina;

const label = global.getLabel();
const labelSessionID = typeof label === 'string' && label.startsWith('cinelark:')
  ? label.slice('cinelark:'.length)
  : null;

let activeSession = null;
let pendingFullscreen = false;
let lastPositionEmission = 0;

function emit(type, payload = {}, replyTo = null) {
  if (!activeSession) return;
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

function snapshot() {
  const idle = Boolean(core.status.idle);
  const paused = Boolean(core.status.paused);
  return {
    state: idle ? 'stopped' : paused ? 'paused' : 'playing',
    positionSeconds: Math.max(0, finiteNumber(core.status.position)),
    durationSeconds: Math.max(0, finiteNumber(core.status.duration)),
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

function emitPosition(replyTo = null) {
  const state = snapshot();
  emit(
    'player.positionChanged',
    {
      positionSeconds: state.positionSeconds,
      durationSeconds: state.durationSeconds,
    },
    replyTo
  );
}

event.on('iina.file-loaded', () => {
  if (!activeSession) return;
  const resumePosition = finiteNumber(activeSession.startPositionSeconds);
  if (resumePosition > 0) core.seekTo(resumePosition);
  if (pendingFullscreen && core.window.loaded) core.window.fullscreen = true;
  emit('player.fileLoaded', {
    playbackID: activeSession.playbackID,
    resumedAtSeconds: Math.max(0, resumePosition),
  });
  emitTracks();
  emitState();
  emitPosition();
});

event.on('iina.window-loaded', () => {
  if (pendingFullscreen) core.window.fullscreen = true;
});

event.on('mpv.pause.changed', () => {
  emitState();
  emitPosition();
});

event.on('mpv.end-file', (details) => {
  const reason = details && typeof details.reason === 'string' ? details.reason : 'unknown';
  emitPosition();
  emit('player.ended', { reason });
});

event.on('iina.window-will-close', () => {
  emitPosition();
  emit('player.closed', { reason: 'window_closed' });
  activeSession = null;
});

global.onMessage('cinelark.command', (command) => {
  if (!command || !command.sessionID || command.sessionID !== labelSessionID) return;

  if (command.type === 'player.play') {
    const payload = command.payload || {};
    if (typeof payload.url !== 'string' || typeof payload.playbackID !== 'string') return;
    activeSession = {
      sessionID: command.sessionID,
      playbackID: payload.playbackID,
      startPositionSeconds: finiteNumber(payload.startPositionSeconds),
    };
    pendingFullscreen = Boolean(payload.presentation && payload.presentation.fullscreen);
    core.open(payload.url);
    return;
  }

  if (!activeSession || command.sessionID !== activeSession.sessionID) return;
  const payload = command.payload || {};
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
      break;
    case 'player.setVolume':
      core.audio.volume = Math.max(0, finiteNumber(payload.volume));
      break;
    case 'player.setMuted':
      core.audio.muted = Boolean(payload.muted);
      break;
    case 'player.selectAudioTrack':
      if (Number.isInteger(payload.id)) core.audio.id = payload.id;
      break;
    case 'player.selectSubtitleTrack':
      if (Number.isInteger(payload.id)) core.subtitle.id = payload.id;
      break;
    case 'player.requestState':
      emitState(command.id);
      emitPosition(command.id);
      emitTracks();
      break;
    default:
      break;
  }
});

setInterval(() => {
  if (!activeSession || core.status.idle) return;
  const now = Date.now();
  if (now - lastPositionEmission >= 2000) {
    lastPositionEmission = now;
    emitPosition();
  }
}, 1000);
