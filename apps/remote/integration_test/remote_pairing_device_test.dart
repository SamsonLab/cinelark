import 'dart:async';
import 'dart:convert';

import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:cinelark_remote/services/remote_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delivers a scanned pairing request to the Mac', (tester) async {
    const encodedPayload = String.fromEnvironment(
      'CINELARK_PAIRING_PAYLOAD_BASE64',
    );
    final padding = '=' * ((4 - encodedPayload.length % 4) % 4);
    final rawPayload = utf8.decode(base64Url.decode('$encodedPayload$padding'));
    final pairing = PairingPayload.parse(rawPayload);
    final pending = Completer<RemoteEnvelope>();
    final rejected = Completer<RemoteEnvelope>();
    late final RemoteTransport transport;
    transport = RemoteTransport(
      onEnvelope: (envelope) {
        switch (envelope.type) {
          case 'session.challenge':
            transport.send(
              'pairing.request',
              payload: {
                'secret': pairing.secret,
                'deviceID': 'eec329e3-3968-4b5a-9fa2-d7608d5cc922',
                'deviceName': 'Android Pairing Test',
              },
            );
          case 'pairing.pending':
            if (!pending.isCompleted) pending.complete(envelope);
          case 'pairing.rejected':
            if (!rejected.isCompleted) rejected.complete(envelope);
        }
      },
      onDisconnected: (error) {
        if (!pending.isCompleted) pending.completeError(error ?? 'closed');
        if (!rejected.isCompleted) rejected.completeError(error ?? 'closed');
      },
    );
    addTearDown(transport.close);

    await transport.connect(pairing.endpoint, pairing.fingerprint);

    await pending.future.timeout(const Duration(seconds: 5));
    debugPrint('PAIRING_PENDING_ON_MAC');
    final result = await rejected.future.timeout(const Duration(seconds: 60));
    expect(result.payload['code'], 'pairingRejected');
  });
}
