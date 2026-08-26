import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum HostPlatform {
  macOS('macos'),
  windows('windows'),
  linux('linux'),
  unknown('unknown');

  const HostPlatform(this.wireValue);

  factory HostPlatform.parse(Object? value) => switch (value) {
    'macos' => HostPlatform.macOS,
    'windows' => HostPlatform.windows,
    'linux' => HostPlatform.linux,
    _ => HostPlatform.unknown,
  };

  final String wireValue;
}

class PairingPayload {
  const PairingPayload({
    required this.serviceId,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.secret,
    required this.expiresAt,
  });

  factory PairingPayload.parse(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['protocolVersion'] != 1) {
      throw const FormatException('Unsupported CineLark pairing code.');
    }
    final payload = PairingPayload(
      serviceId: _requiredString(value, 'serviceID').toLowerCase(),
      name: _requiredString(value, 'name'),
      platform: value.containsKey('platform')
          ? HostPlatform.parse(value['platform'])
          : HostPlatform.macOS,
      host: _requiredString(value, 'host'),
      port: _requiredInt(value, 'port'),
      fingerprint: _requiredString(value, 'fingerprint'),
      secret: _requiredString(value, 'secret'),
      expiresAt: DateTime.parse(_requiredString(value, 'expiresAt')).toUtc(),
    );
    if (!Uuid.isValidUUIDFormat(fromString: payload.serviceId) ||
        payload.name.length > 80 ||
        payload.host.length > 255 ||
        payload.port < 1 ||
        payload.port > 65535 ||
        !_isBase64Url256(payload.fingerprint) ||
        !_isBase64Url256(payload.secret) ||
        payload.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw const FormatException(
        'The CineLark pairing code is invalid or expired.',
      );
    }
    return payload;
  }

  final String serviceId;
  final String name;
  final HostPlatform platform;
  final String host;
  final int port;
  final String fingerprint;
  final String secret;
  final DateTime expiresAt;

  Uri get endpoint =>
      Uri(scheme: 'wss', host: host, port: port, path: '/v1/remote');
}

class PairedMac {
  const PairedMac({
    required this.serviceId,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.deviceId,
    required this.credential,
  });

  factory PairedMac.fromJson(Map<String, dynamic> value) {
    final paired = PairedMac(
      serviceId: _requiredString(value, 'serviceID'),
      name: _requiredString(value, 'name'),
      platform: value.containsKey('platform')
          ? HostPlatform.parse(value['platform'])
          : HostPlatform.macOS,
      host: _requiredString(value, 'host'),
      port: _requiredInt(value, 'port'),
      fingerprint: _requiredString(value, 'fingerprint'),
      deviceId: _requiredString(value, 'deviceID'),
      credential: _requiredString(value, 'credential'),
    );
    if (!Uuid.isValidUUIDFormat(fromString: paired.serviceId) ||
        !Uuid.isValidUUIDFormat(fromString: paired.deviceId) ||
        paired.port < 1 ||
        paired.port > 65535 ||
        !_isBase64Url256(paired.fingerprint) ||
        !_isBase64Url256(paired.credential)) {
      throw const FormatException('Invalid paired Mac record.');
    }
    return paired;
  }

  final String serviceId;
  final String name;
  final HostPlatform platform;
  final String host;
  final int port;
  final String fingerprint;
  final String deviceId;
  final String credential;

  Uri get endpoint =>
      Uri(scheme: 'wss', host: host, port: port, path: '/v1/remote');

  String get displayName {
    final normalized = name.trim().replaceFirst(_legacyNamePrefix, '').trim();
    if (normalized.isNotEmpty) return normalized;
    return switch (platform) {
      HostPlatform.macOS => 'Mac',
      HostPlatform.windows => 'Windows PC',
      HostPlatform.linux => 'Linux PC',
      HostPlatform.unknown => 'Computer',
    };
  }

  Map<String, dynamic> toJson() => {
    'serviceID': serviceId,
    'name': name,
    'platform': platform.wireValue,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'deviceID': deviceId,
    'credential': credential,
  };
}

class RemoteEnvelope {
  const RemoteEnvelope({
    required this.id,
    required this.type,
    required this.sequence,
    required this.payload,
    this.replyTo,
    this.revision,
  });

  factory RemoteEnvelope.fromJson(Map<String, dynamic> value) {
    if (value['protocolVersion'] != 1 || value['payload'] is! Map) {
      throw const FormatException('Invalid Remote envelope.');
    }
    final id = _requiredString(value, 'id');
    final type = _requiredString(value, 'type');
    final sequence = _requiredInt(value, 'sequence');
    final replyTo = value['replyTo'] as String?;
    final revision = value['revision'] as int?;
    final sentAt = DateTime.tryParse(_requiredString(value, 'sentAt'));
    if (!Uuid.isValidUUIDFormat(fromString: id) ||
        !_messageType.hasMatch(type) ||
        sequence < 0 ||
        (replyTo != null && !Uuid.isValidUUIDFormat(fromString: replyTo)) ||
        (revision != null && revision < 0) ||
        sentAt == null) {
      throw const FormatException('Invalid Remote envelope.');
    }
    return RemoteEnvelope(
      id: id,
      type: type,
      sequence: sequence,
      replyTo: replyTo,
      revision: revision,
      payload: Map<String, dynamic>.from(value['payload'] as Map),
    );
  }

  final String id;
  final String type;
  final int sequence;
  final String? replyTo;
  final int? revision;
  final Map<String, dynamic> payload;
}

String remoteAuthenticationProof({
  required String credentialBase64Url,
  required String serviceId,
  required String connectionId,
  required String nonce,
}) {
  final padding = '=' * ((4 - credentialBase64Url.length % 4) % 4);
  final credential = base64Url.decode('$credentialBase64Url$padding');
  final input = utf8.encode('$serviceId\n$connectionId\n$nonce');
  return base64Url
      .encode(Hmac(sha256, credential).convert(input).bytes)
      .replaceAll('=', '');
}

String _requiredString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw FormatException('Missing $key.');
  }
  return result;
}

int _requiredInt(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! int) throw FormatException('Missing $key.');
  return result;
}

final _messageType = RegExp(r'^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)+$');
final _base64Url = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _legacyNamePrefix = RegExp(
  r'^cine[\s-]*lark(?:\s*[—–:\-]\s*|\s+)',
  caseSensitive: false,
);

bool _isBase64Url256(String value) {
  if (!_base64Url.hasMatch(value)) return false;
  try {
    return base64Url.decode('$value=').length == 32;
  } on FormatException {
    return false;
  }
}
