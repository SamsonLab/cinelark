import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/remote_protocol.dart';
import 'android_local_web_socket.dart';

typedef EnvelopeHandler = FutureOr<void> Function(RemoteEnvelope envelope);
typedef DisconnectHandler = void Function(Object? error);

class RemoteTransport {
  RemoteTransport({required this.onEnvelope, required this.onDisconnected});

  static const _maximumMessageBytes = 65 * 1024;
  static const _uuid = Uuid();

  final EnvelopeHandler onEnvelope;
  final DisconnectHandler onDisconnected;

  WebSocket? _socket;
  AndroidLocalWebSocket? _androidSocket;
  HttpClient? _client;
  StreamSubscription<dynamic>? _subscription;
  int _nextInboundSequence = 0;
  int _nextOutboundSequence = 0;
  bool _closing = false;

  bool get isConnected => _socket != null || _androidSocket != null;

  Future<void> connect(Uri endpoint, String expectedFingerprint) async {
    debugPrint(
      '[remote-transport] connect_requested host=${endpoint.host} '
      'port=${endpoint.port} platform=${Platform.operatingSystem}',
    );
    await close();
    _closing = false;
    _nextInboundSequence = 0;
    _nextOutboundSequence = 0;
    if (Platform.isAndroid) {
      debugPrint('[remote-transport] android_native_transport_selected');
      final socket = AndroidLocalWebSocket();
      _androidSocket = socket;
      _subscription = socket.messages.stream.listen(
        _receive,
        onError: _didDisconnect,
        onDone: () => _didDisconnect(null),
        cancelOnError: true,
      );
      try {
        await socket.connect(endpoint, expectedFingerprint);
        debugPrint('[remote-transport] android_websocket_opened');
      } on Object catch (error) {
        debugPrint(
          '[remote-transport] android_connect_failed '
          'type=${error.runtimeType} error=$error',
        );
        _androidSocket = null;
        await _subscription?.cancel();
        _subscription = null;
        rethrow;
      }
      return;
    }
    var observedPin = false;
    final client = HttpClient(
      context: SecurityContext(withTrustedRoots: false),
    );
    client.connectionTimeout = const Duration(seconds: 8);
    client.badCertificateCallback = (certificate, _, _) {
      final actual = base64Url
          .encode(sha256.convert(certificate.der).bytes)
          .replaceAll('=', '');
      observedPin = _constantTimeEquals(actual, expectedFingerprint);
      return observedPin;
    };
    _client = client;

    try {
      final socket = await WebSocket.connect(
        endpoint.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 10));
      if (!observedPin) {
        await socket.close(WebSocketStatus.policyViolation, 'pin_mismatch');
        throw const HandshakeException('CineLark certificate pin mismatch.');
      }
      debugPrint('[remote-transport] dart_websocket_opened pin=matched');
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _subscription = socket.listen(
        _receive,
        onError: _didDisconnect,
        onDone: () => _didDisconnect(null),
        cancelOnError: true,
      );
    } on Object catch (error) {
      debugPrint(
        '[remote-transport] dart_connect_failed '
        'type=${error.runtimeType} error=$error',
      );
      client.close(force: true);
      _client = null;
      rethrow;
    }
  }

  void send(
    String type, {
    Map<String, dynamic> payload = const {},
    int? revision,
  }) {
    final sequence = _nextOutboundSequence++;
    final envelope = <String, dynamic>{
      'protocolVersion': 1,
      'id': _uuid.v4(),
      'type': type,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'sequence': sequence,
      'revision': ?revision,
      'payload': payload,
    };
    final encoded = jsonEncode(envelope);
    if (utf8.encode(encoded).length > _maximumMessageBytes) {
      throw const FormatException('Remote command is too large.');
    }
    debugPrint(
      '[remote-transport] envelope_sending type=$type sequence=$sequence',
    );
    final androidSocket = _androidSocket;
    if (androidSocket != null) {
      androidSocket.send(encoded);
      return;
    }
    final socket = _socket;
    if (socket == null) throw const SocketException('Remote is disconnected.');
    socket.add(encoded);
  }

  Future<void> close() async {
    debugPrint('[remote-transport] close_requested');
    _closing = true;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.normalClosure, 'client_closed');
    final androidSocket = _androidSocket;
    _androidSocket = null;
    await androidSocket?.close();
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _receive(dynamic message) async {
    try {
      if (message is! String ||
          utf8.encode(message).length > _maximumMessageBytes) {
        throw const FormatException('Invalid Remote message.');
      }
      final envelope = RemoteEnvelope.fromJson(
        Map<String, dynamic>.from(jsonDecode(message) as Map),
      );
      if (envelope.sequence != _nextInboundSequence) {
        throw const FormatException('Remote sequence gap.');
      }
      debugPrint(
        '[remote-transport] envelope_validated type=${envelope.type} '
        'sequence=${envelope.sequence}',
      );
      _nextInboundSequence++;
      await onEnvelope(envelope);
    } on Object catch (error) {
      debugPrint(
        '[remote-transport] receive_failed '
        'type=${error.runtimeType} error=$error',
      );
      await close();
      onDisconnected(error);
    }
  }

  void _didDisconnect(Object? error) {
    debugPrint(
      '[remote-transport] socket_done closing=$_closing '
      'type=${error?.runtimeType} error=$error',
    );
    _socket = null;
    _androidSocket = null;
    _client?.close(force: true);
    _client = null;
    if (!_closing) onDisconnected(error);
  }
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
