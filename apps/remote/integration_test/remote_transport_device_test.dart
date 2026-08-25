import 'dart:async';

import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:cinelark_remote/services/remote_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connects to the Mac gateway over the local Wi-Fi route', (
    tester,
  ) async {
    final endpoint = Uri.parse(
      const String.fromEnvironment('CINELARK_REMOTE_ENDPOINT'),
    );
    const fingerprint = String.fromEnvironment('CINELARK_REMOTE_FINGERPRINT');
    final challenge = Completer<RemoteEnvelope>();
    final pairingResult = Completer<RemoteEnvelope>();
    final transport = RemoteTransport(
      onEnvelope: (envelope) {
        if (envelope.type == 'session.challenge' && !challenge.isCompleted) {
          challenge.complete(envelope);
        }
        if ((envelope.type == 'pairing.pending' ||
                envelope.type == 'session.error') &&
            !pairingResult.isCompleted) {
          pairingResult.complete(envelope);
        }
      },
      onDisconnected: (error) {
        if (!challenge.isCompleted) challenge.completeError(error ?? 'closed');
      },
    );
    addTearDown(transport.close);

    await transport.connect(endpoint, fingerprint);

    final envelope = await challenge.future.timeout(const Duration(seconds: 5));
    expect(envelope.payload['protocolMin'], 1);
    expect(envelope.payload['protocolMax'], 1);

    transport.send(
      'pairing.request',
      payload: const {
        'secret': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'deviceID': '4110f4a2-8427-446f-a2ee-6204db604b1b',
        'deviceName': 'Android Integration Test',
      },
    );

    final result = await pairingResult.future.timeout(
      const Duration(seconds: 5),
    );
    expect(result.type, 'session.error');
    expect(result.payload['code'], 'pairingUnavailable');
  });
}
