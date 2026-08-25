class AppSnapshot {
  const AppSnapshot({
    required this.phase,
    required this.selectedSection,
    required this.sections,
    this.errorCode,
  });

  factory AppSnapshot.fromJson(Map<String, dynamic> value) => AppSnapshot(
    phase: value['phase'] as String? ?? 'launching',
    selectedSection: value['selectedSection'] as String? ?? 'home',
    sections: (value['sections'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    errorCode: value['errorCode'] as String?,
  );

  final String phase;
  final String selectedSection;
  final List<String> sections;
  final String? errorCode;
}

class TextInputSnapshot {
  const TextInputSnapshot({
    required this.sessionId,
    required this.kind,
    required this.text,
    required this.maximumLength,
    required this.revision,
  });

  factory TextInputSnapshot.fromJson(Map<String, dynamic> value) =>
      TextInputSnapshot(
        sessionId: value['sessionID'] as String,
        kind: value['kind'] as String? ?? 'text',
        text: value['text'] as String? ?? '',
        maximumLength: value['maximumLength'] as int? ?? 512,
        revision: value['revision'] as int? ?? 0,
      );

  final String sessionId;
  final String kind;
  final String text;
  final int maximumLength;
  final int revision;
}

class PlaybackTrack {
  const PlaybackTrack({
    required this.id,
    required this.kind,
    required this.title,
    required this.selected,
  });

  factory PlaybackTrack.fromJson(Map<String, dynamic> value) => PlaybackTrack(
    id: value['id'] as int,
    kind: value['kind'] as String,
    title:
        value['title'] as String? ??
        value['language'] as String? ??
        '${value['kind']} ${value['id']}',
    selected: value['selected'] as bool? ?? false,
  );

  final int id;
  final String kind;
  final String title;
  final bool selected;
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.revision,
    required this.playbackId,
    required this.state,
    required this.title,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.speed,
    required this.volume,
    required this.muted,
    required this.fullscreen,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.audioTracks,
    required this.subtitleTracks,
  });

  factory PlaybackSnapshot.fromJson(
    Map<String, dynamic> value, {
    required int revision,
  }) => PlaybackSnapshot(
    revision: revision,
    playbackId: value['playbackID'] as String?,
    state: value['state'] as String? ?? 'idle',
    title: value['title'] as String?,
    positionSeconds: (value['positionSeconds'] as num?)?.toDouble() ?? 0,
    durationSeconds: (value['durationSeconds'] as num?)?.toDouble() ?? 0,
    speed: (value['speed'] as num?)?.toDouble() ?? 1,
    volume: (value['volume'] as num?)?.toDouble() ?? 0,
    muted: value['muted'] as bool? ?? false,
    fullscreen: value['fullscreen'] as bool? ?? false,
    canPlayPrevious: value['canPlayPrevious'] as bool? ?? false,
    canPlayNext: value['canPlayNext'] as bool? ?? false,
    audioTracks: _tracks(value['audioTracks']),
    subtitleTracks: _tracks(value['subtitleTracks']),
  );

  final int revision;
  final String? playbackId;
  final String state;
  final String? title;
  final double positionSeconds;
  final double durationSeconds;
  final double speed;
  final double volume;
  final bool muted;
  final bool fullscreen;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final List<PlaybackTrack> audioTracks;
  final List<PlaybackTrack> subtitleTracks;

  bool get isActive => playbackId != null && state != 'idle';
  bool get isPlaying => state == 'playing';
}

List<PlaybackTrack> _tracks(Object? value) => (value as List? ?? const [])
    .whereType<Map>()
    .map((track) => PlaybackTrack.fromJson(Map<String, dynamic>.from(track)))
    .toList(growable: false);
