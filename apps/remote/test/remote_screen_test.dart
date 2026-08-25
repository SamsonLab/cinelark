import 'package:cinelark_remote/controller/remote_controller.dart';
import 'package:cinelark_remote/screens/remote_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('command error dismisses automatically', (tester) async {
    final controller = RemoteController()
      ..phase = RemoteConnectionPhase.connected
      ..errorCode = 'invalidState';
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(controller));

    expect(
      find.text('That control is not available on the current screen.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));

    expect(controller.errorCode, isNull);
    expect(
      find.text('That control is not available on the current screen.'),
      findsNothing,
    );
  });

  testWidgets('command error can be dismissed immediately', (tester) async {
    final controller = RemoteController()
      ..phase = RemoteConnectionPhase.connected
      ..errorCode = 'invalidState';
    addTearDown(controller.dispose);

    await tester.pumpWidget(_testApp(controller));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(controller.errorCode, isNull);
    expect(find.text('Dismiss'), findsNothing);
  });
}

Widget _testApp(RemoteController controller) => MaterialApp(
  home: ListenableBuilder(
    listenable: controller,
    builder: (context, child) => RemoteScreen(controller: controller),
  ),
);
