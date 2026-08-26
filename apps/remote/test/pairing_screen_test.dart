import 'package:cinelark_remote/controller/remote_controller.dart';
import 'package:cinelark_remote/screens/pairing_screen.dart';
import 'package:cinelark_remote/widgets/cinelark_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retry remounts the scanner without starting it prematurely', (
    tester,
  ) async {
    final controller = _RetryController();
    addTearDown(controller.dispose);
    var scannerBuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PairingScreen(
          controller: controller,
          scannerBuilder: (_, _) {
            scannerBuildCount += 1;
            return const ColoredBox(color: Colors.black);
          },
        ),
      ),
    );

    expect(find.text('Pairing failed'), findsOneWidget);
    expect(scannerBuildCount, 0);

    await tester.tap(find.text('Scan Again'));
    await tester.pumpAndSettle();

    expect(find.text('CineLark Remote'), findsOneWidget);
    expect(find.byType(CineLarkMark), findsOneWidget);
    expect(scannerBuildCount, 1);
  });
}

class _RetryController extends RemoteController {
  _RetryController() {
    phase = RemoteConnectionPhase.failed;
  }

  @override
  Future<void> retryPairing() async {
    phase = RemoteConnectionPhase.unpaired;
  }
}
