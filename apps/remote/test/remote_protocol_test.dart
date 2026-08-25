import 'dart:convert';

import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart authentication matches the shared Rust and Swift vector', () {
    final proof = remoteAuthenticationProof(
      credentialBase64Url: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      serviceId: 'ad54e7ba-9409-4f54-8c7c-65e781978cf9',
      connectionId: '8dc63877-bf80-4d63-afc0-bec50d1ecb60',
      nonce: 'c3ludGhldGljLW5vbmNl',
    );
    expect(proof, 'mzD1FDUxeqTJFptKfi3MmsuroE65jf6dhK-f3Ar05MU');
  });

  test('pairing payload rejects expired codes', () {
    final value = {
      'protocolVersion': 1,
      'serviceID': 'ad54e7ba-9409-4f54-8c7c-65e781978cf9',
      'name': 'Synthetic Mac',
      'host': 'cinelark.local',
      'port': 43201,
      'fingerprint': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'secret': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'expiresAt': '2020-01-01T00:00:00Z',
    };
    expect(
      () => PairingPayload.parse(jsonEncode(value)),
      throwsFormatException,
    );
  });

  test('pairing payload canonicalizes an uppercase service ID', () {
    final value = {
      'protocolVersion': 1,
      'serviceID': 'AD54E7BA-9409-4F54-8C7C-65E781978CF9',
      'name': 'Synthetic Mac',
      'host': '192.168.20.100',
      'port': 43201,
      'fingerprint': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'secret': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'expiresAt': '2100-01-01T00:00:00Z',
    };

    final payload = PairingPayload.parse(jsonEncode(value));

    expect(payload.serviceId, 'ad54e7ba-9409-4f54-8c7c-65e781978cf9');
  });

  test('Remote envelope retains nullable playback payload values', () {
    final envelope = RemoteEnvelope.fromJson({
      'protocolVersion': 1,
      'id': '0b56e8b4-a79e-4939-8c9b-d4f7c753df61',
      'type': 'playback.selectSubtitleTrack',
      'sentAt': '2026-08-20T03:09:00Z',
      'sequence': 4,
      'revision': 8,
      'payload': {
        'playbackID': '1f3cc671-b430-4e87-994d-e2a1d4fa5e54',
        'trackID': null,
        'revision': 8,
      },
    });
    expect(envelope.payload['trackID'], isNull);
    expect(envelope.revision, 8);
  });

  test('Remote envelope rejects malformed identity and ordering fields', () {
    expect(
      () => RemoteEnvelope.fromJson({
        'protocolVersion': 1,
        'id': 'not-a-uuid',
        'type': 'invalid type',
        'sentAt': 'not-a-date',
        'sequence': -1,
        'payload': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });
}
