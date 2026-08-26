import 'package:cinelark_remote/controller/remote_controller.dart';
import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:cinelark_remote/services/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initialization opens device selection without auto-connecting',
    () async {
      final devices = [_pairedMac('11111111-1111-4111-8111-111111111111')];
      final store = _MemoryPairedMacStore(devices);
      final controller = RemoteController(store: store);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.phase, RemoteConnectionPhase.deviceSelection);
      expect(controller.pairedMac, isNull);
      expect(controller.pairedMacs, devices);
    },
  );

  test('forget removes only the selected device', () async {
    final first = _pairedMac('11111111-1111-4111-8111-111111111111');
    final second = _pairedMac('22222222-2222-4222-8222-222222222222');
    final store = _MemoryPairedMacStore([first, second]);
    final controller = RemoteController(store: store)
      ..pairedMacs = [first, second]
      ..pairedMac = first
      ..phase = RemoteConnectionPhase.connected;
    addTearDown(controller.dispose);

    await controller.forget();

    expect(controller.phase, RemoteConnectionPhase.deviceSelection);
    expect(controller.pairedMac, isNull);
    expect(controller.pairedMacs, [second]);
    expect(store.saved, [second]);
  });
}

class _MemoryPairedMacStore implements PairedMacStore {
  _MemoryPairedMacStore(this.saved);

  List<PairedMac> saved;

  @override
  Future<List<PairedMac>> loadAll() async => List.of(saved);

  @override
  Future<void> saveAll(List<PairedMac> pairedMacs) async {
    saved = List.of(pairedMacs);
  }
}

PairedMac _pairedMac(String serviceId) => PairedMac(
  serviceId: serviceId,
  name: 'CineLark — Test Mac',
  platform: HostPlatform.macOS,
  host: '192.168.1.10',
  port: 19421,
  fingerprint: 'a' * 43,
  deviceId: '33333333-3333-4333-8333-333333333333',
  credential: 'b' * 43,
);
