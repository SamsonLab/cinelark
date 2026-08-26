import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/remote_protocol.dart';

abstract interface class PairedMacStore {
  Future<List<PairedMac>> loadAll();
  Future<void> saveAll(List<PairedMac> pairedMacs);
}

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureValueStore implements SecureValueStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(migrateWithBackup: false, resetOnError: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class CredentialStore implements PairedMacStore {
  CredentialStore({SecureValueStore? storage})
    : _storage = storage ?? FlutterSecureValueStore();

  static const pairedMacsKey = 'paired-macs-v2';
  static const legacyPairedMacKey = 'paired-mac-v1';

  final SecureValueStore _storage;

  @override
  Future<List<PairedMac>> loadAll() async {
    final encoded = await _storage.read(pairedMacsKey);
    if (encoded != null) {
      try {
        return _decodeList(encoded);
      } on Object {
        await _storage.delete(pairedMacsKey);
      }
    }

    final legacy = await _storage.read(legacyPairedMacKey);
    if (legacy == null) return const [];
    try {
      final pairedMac = PairedMac.fromJson(
        Map<String, dynamic>.from(jsonDecode(legacy) as Map),
      );
      final pairedMacs = [pairedMac];
      await saveAll(pairedMacs);
      return pairedMacs;
    } on Object {
      await _storage.delete(legacyPairedMacKey);
      return const [];
    }
  }

  @override
  Future<void> saveAll(List<PairedMac> pairedMacs) async {
    await _storage.write(
      pairedMacsKey,
      jsonEncode(pairedMacs.map((mac) => mac.toJson()).toList()),
    );
    await _storage.delete(legacyPairedMacKey);
  }

  static List<PairedMac> _decodeList(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! List) throw const FormatException('Invalid paired Macs.');
    final byServiceId = <String, PairedMac>{};
    for (final item in value) {
      if (item is! Map) throw const FormatException('Invalid paired Mac.');
      final pairedMac = PairedMac.fromJson(Map<String, dynamic>.from(item));
      byServiceId[pairedMac.serviceId] = pairedMac;
    }
    return List.unmodifiable(byServiceId.values);
  }
}
