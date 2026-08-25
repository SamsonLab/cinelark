import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/remote_protocol.dart';

class CredentialStore {
  static const _key = 'paired-mac-v1';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(migrateWithBackup: false, resetOnError: true),
  );

  Future<PairedMac?> load() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    try {
      return PairedMac.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } on Object {
      await clear();
      return null;
    }
  }

  Future<void> save(PairedMac pairedMac) =>
      _storage.write(key: _key, value: jsonEncode(pairedMac.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
