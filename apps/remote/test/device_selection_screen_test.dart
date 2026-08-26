import 'package:cinelark_remote/controller/remote_controller.dart';
import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:cinelark_remote/screens/device_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows named devices before the add-device item', (tester) async {
    final first = _pairedMac(
      serviceId: '11111111-1111-4111-8111-111111111111',
      name: 'CineLark — Living Room Mac',
      host: '192.168.1.10',
      platform: HostPlatform.macOS,
    );
    final second = _pairedMac(
      serviceId: '22222222-2222-4222-8222-222222222222',
      name: 'CineLark — Studio Mac',
      host: '192.168.1.20',
      platform: HostPlatform.windows,
    );
    final third = _pairedMac(
      serviceId: '44444444-4444-4444-8444-444444444444',
      name: 'Media Server',
      host: '192.168.1.30',
      platform: HostPlatform.linux,
    );
    final controller = _DeviceSelectionController([first, second, third]);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: DeviceSelectionScreen(controller: controller)),
    );

    expect(find.text('Living Room Mac'), findsOneWidget);
    expect(find.text('Studio Mac'), findsOneWidget);
    expect(find.text('Media Server'), findsOneWidget);
    expect(find.textContaining('CineLark —'), findsNothing);
    expect(find.byIcon(Icons.apple_rounded), findsOneWidget);
    expect(find.byIcon(Icons.window_rounded), findsOneWidget);
    expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
    expect(find.text('192.168.1.10:19421'), findsOneWidget);
    expect(find.text('Add New Device'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('add-device'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(ValueKey('device-${third.serviceId}'))).dy,
      ),
    );

    await tester.tap(find.text('Studio Mac'));
    await tester.pump();
    expect(controller.selectedDevice, same(second));

    await tester.ensureVisible(find.text('Add New Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Device'));
    await tester.pump();
    expect(controller.addRequested, isTrue);
  });
}

class _DeviceSelectionController extends RemoteController {
  _DeviceSelectionController(List<PairedMac> devices) {
    pairedMacs = devices;
    phase = RemoteConnectionPhase.deviceSelection;
  }

  PairedMac? selectedDevice;
  bool addRequested = false;

  @override
  Future<void> selectDevice(PairedMac device) async {
    selectedDevice = device;
  }

  @override
  Future<void> addDevice() async {
    addRequested = true;
  }
}

PairedMac _pairedMac({
  required String serviceId,
  required String name,
  required String host,
  required HostPlatform platform,
}) => PairedMac(
  serviceId: serviceId,
  name: name,
  platform: platform,
  host: host,
  port: 19421,
  fingerprint: 'a' * 43,
  deviceId: '33333333-3333-4333-8333-333333333333',
  credential: 'b' * 43,
);
