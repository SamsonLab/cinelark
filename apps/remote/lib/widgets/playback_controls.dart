import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/remote_controller.dart';
import '../models/remote_state.dart';

class PlaybackControls extends StatefulWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    required this.snapshot,
  });

  final RemoteController controller;
  final PlaybackSnapshot snapshot;

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  double? scrubPosition;
  double? committedSeekPosition;
  double? volumePreview;
  Timer? seekTimeout;

  @override
  void didUpdateWidget(covariant PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.playbackId != widget.snapshot.playbackId) {
      scrubPosition = null;
      committedSeekPosition = null;
      volumePreview = null;
      seekTimeout?.cancel();
    } else if (committedSeekPosition case final target?) {
      final receivedSeek =
          widget.snapshot.revision > oldWidget.snapshot.revision &&
          (widget.snapshot.positionSeconds - target).abs() <= 3;
      if (receivedSeek) {
        committedSeekPosition = null;
        seekTimeout?.cancel();
      }
    }
  }

  @override
  void dispose() {
    seekTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final duration = snapshot.durationSeconds <= 0
        ? 1.0
        : snapshot.durationSeconds;
    final position =
        (scrubPosition ?? committedSeekPosition ?? snapshot.positionSeconds)
            .clamp(0.0, duration);
    final volume = (volumePreview ?? snapshot.volume).clamp(0.0, 100.0);
    final hasSubtitleTracks = snapshot.subtitleTracks.any(
      (track) => track.id != 0,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        const SizedBox(height: 10),
        const Center(
          child: Icon(
            Icons.live_tv_rounded,
            size: 72,
            color: Color(0xff51a8ff),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          snapshot.title ?? 'Playing in IINA',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 30),
        Slider(
          value: position,
          max: duration,
          onChanged: (value) => setState(() => scrubPosition = value),
          onChangeEnd: (value) {
            widget.controller.seekAbsolute(value);
            seekTimeout?.cancel();
            seekTimeout = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() => committedSeekPosition = null);
            });
            setState(() {
              scrubPosition = null;
              committedSeekPosition = value;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_duration(position)),
              Text('-${_duration((duration - position).clamp(0, duration))}'),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              onPressed: snapshot.canPlayPrevious
                  ? widget.controller.playPrevious
                  : null,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 34,
            ),
            IconButton(
              onPressed: () => widget.controller.seekRelative(-15),
              icon: const Icon(Icons.replay_10_rounded),
              iconSize: 36,
            ),
            IconButton.filled(
              onPressed: widget.controller.togglePause,
              icon: Icon(
                snapshot.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 44,
              style: IconButton.styleFrom(fixedSize: const Size.square(76)),
            ),
            IconButton(
              onPressed: () => widget.controller.seekRelative(30),
              icon: const Icon(Icons.forward_30_rounded),
              iconSize: 36,
            ),
            IconButton.filledTonal(
              onPressed: snapshot.canPlayNext
                  ? widget.controller.playNext
                  : null,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 34,
            ),
          ],
        ),
        const SizedBox(height: 28),
        _ControlCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        widget.controller.setMuted(!snapshot.muted),
                    icon: Icon(
                      snapshot.muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: volume,
                      max: 100,
                      onChanged: (value) =>
                          setState(() => volumePreview = value),
                      onChangeEnd: (value) {
                        widget.controller.setVolume(value);
                        setState(() => volumePreview = null);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.speed_rounded,
                      label: '${snapshot.speed.toStringAsFixed(2)}×',
                      onPressed: () => _showRates(context, snapshot.speed),
                    ),
                  ),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.audiotrack_rounded,
                      label: 'Audio',
                      onPressed: snapshot.audioTracks.isEmpty
                          ? null
                          : () => _showTracks(
                              context,
                              title: 'Audio Track',
                              tracks: snapshot.audioTracks,
                              onSelected: widget.controller.selectAudioTrack,
                            ),
                    ),
                  ),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.subtitles_rounded,
                      label: 'Subtitles',
                      onPressed: !hasSubtitleTracks
                          ? null
                          : () => _showSubtitleTracks(context, snapshot),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    widget.controller.setFullscreen(!snapshot.fullscreen),
                icon: Icon(
                  snapshot.fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
                label: Text(
                  snapshot.fullscreen ? 'Exit Full Screen' : 'Full Screen',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: widget.controller.closePlayback,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Close Player'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showRates(BuildContext context, double selected) async {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final rate = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Playback Speed')),
            for (final value in rates)
              ListTile(
                title: Text('${value.toStringAsFixed(2)}×'),
                trailing: value == selected
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (rate != null) widget.controller.setRate(rate);
  }

  Future<void> _showTracks(
    BuildContext context, {
    required String title,
    required List<PlaybackTrack> tracks,
    required ValueChanged<int> onSelected,
  }) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title)),
            for (final track in tracks)
              ListTile(
                title: Text(track.title),
                trailing: track.selected
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, track.id),
              ),
          ],
        ),
      ),
    );
    if (selected != null) onSelected(selected);
  }

  Future<void> _showSubtitleTracks(
    BuildContext context,
    PlaybackSnapshot snapshot,
  ) async {
    final visibleTracks = snapshot.subtitleTracks
        .where((track) => track.id != 0)
        .toList(growable: false);
    final subtitlesOff = !visibleTracks.any((track) => track.selected);
    final selected = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Subtitles')),
            ListTile(
              title: const Text('Off'),
              trailing: subtitlesOff ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, const _SubtitlesOff()),
            ),
            for (final track in visibleTracks)
              ListTile(
                title: Text(track.title),
                trailing: track.selected
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, track.id),
              ),
          ],
        ),
      ),
    );
    if (selected is int) {
      widget.controller.selectSubtitleTrack(selected);
    } else if (selected is _SubtitlesOff) {
      widget.controller.selectSubtitleTrack(null);
    }
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xff151a24),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(padding: const EdgeInsets.all(8), child: child),
  );
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: Column(
      children: [
        Icon(icon),
        const SizedBox(height: 6),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _SubtitlesOff {
  const _SubtitlesOff();
}

String _duration(double seconds) {
  final total = seconds.round().clamp(0, 24 * 60 * 60);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final remainder = total % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
