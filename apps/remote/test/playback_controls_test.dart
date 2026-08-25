import 'package:cinelark_remote/controller/remote_controller.dart';
import 'package:cinelark_remote/models/remote_state.dart';
import 'package:cinelark_remote/widgets/playback_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('subtitles are disabled when no selectable tracks exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = RemoteController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            controller: controller,
            snapshot: _snapshot(
              subtitleTracks: const [
                PlaybackTrack(
                  id: 0,
                  kind: 'subtitle',
                  title: 'Off',
                  selected: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Subtitles'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('subtitle sheet marks Off when no track is selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = RemoteController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            controller: controller,
            snapshot: _snapshot(
              subtitleTracks: const [
                PlaybackTrack(
                  id: 7,
                  kind: 'subtitle',
                  title: 'English',
                  selected: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Subtitles'));
    await tester.pumpAndSettle();

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}

PlaybackSnapshot _snapshot({List<PlaybackTrack> subtitleTracks = const []}) =>
    PlaybackSnapshot(
      revision: 1,
      playbackId: '7a2ec760-2cdd-4dd4-ae5e-c1e31c014dbe',
      state: 'playing',
      title: 'Synthetic Playback',
      positionSeconds: 10,
      durationSeconds: 120,
      speed: 1,
      volume: 50,
      muted: false,
      fullscreen: false,
      canPlayPrevious: false,
      canPlayNext: false,
      audioTracks: const [],
      subtitleTracks: subtitleTracks,
    );
