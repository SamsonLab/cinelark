import 'dart:convert';

import 'package:cinelark_remote/models/remote_protocol.dart';
import 'package:cinelark_remote/services/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the legacy paired Mac into the ordered device list', () async {
    final legacy = _pairedMac(
      serviceId: '11111111-1111-4111-8111-111111111111',
      name: 'CineLark — Living Room Mac',
    );
    final storage = _MemorySecureValueStore({
      CredentialStore.legacyPairedMacKey: jsonEncode(legacy.toJson()),
    });
    final store = CredentialStore(storage: storage);

    final loaded = await store.loadAll();

    expect(loaded.map((device) => device.serviceId), [legacy.serviceId]);
    expect(storage.values, contains(CredentialStore.pairedMacsKey));
    expect(storage.values, isNot(contains(CredentialStore.legacyPairedMacKey)));
  });

  test('preserves multi-device order across secure storage reloads', () async {
    final first = _pairedMac(
      serviceId: '11111111-1111-4111-8111-111111111111',
      name: 'CineLark — Studio Mac',
    );
    final second = _pairedMac(
      serviceId: '22222222-2222-4222-8222-222222222222',
      name: 'CineLark — Living Room Mac',
    );
    final storage = _MemorySecureValueStore();
    final store = CredentialStore(storage: storage);

    await store.saveAll([first, second]);
    final loaded = await store.loadAll();

    expect(loaded.map((device) => device.serviceId), [
      first.serviceId,
      second.serviceId,
    ]);
  });
}

class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore([Map<String, String>? values])
    : values = {...?values};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

PairedMac _pairedMac({required String serviceId, required String name}) =>
    PairedMac(
      serviceId: serviceId,
      name: name,
      platform: HostPlatform.macOS,
      host: '192.168.1.10',
      port: 19421,
      fingerprint: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      deviceId: '33333333-3333-4333-8333-333333333333',
      credential: 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc',
    );
