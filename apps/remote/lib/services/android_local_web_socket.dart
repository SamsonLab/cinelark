import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidLocalWebSocket {
  static const commands = MethodChannel(
    'com.samsonlab.cinelark.remote/websocket',
  );
  static const events = EventChannel(
    'com.samsonlab.cinelark.remote/websocket-events',
  );

  final messages = StreamController<String>();
  StreamSubscription<dynamic>? _eventSubscription;

  Future<void> connect(Uri endpoint, String fingerprint) async {
    debugPrint('[remote-native] event_stream_subscribing');
    _eventSubscription = events.receiveBroadcastStream().listen(
      _receive,
      onError: _receiveError,
    );
    try {
      debugPrint('[remote-native] connect_invoking');
      await commands.invokeMethod<bool>('connect', {
        'endpoint': endpoint.toString(),
        'fingerprint': fingerprint,
      });
      debugPrint('[remote-native] connect_completed');
    } on Object catch (error) {
      debugPrint(
        '[remote-native] connect_failed type=${error.runtimeType} error=$error',
      );
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      rethrow;
    }
  }

  void send(String message) {
    debugPrint('[remote-native] send_invoking chars=${message.length}');
    unawaited(
      commands.invokeMethod<bool>('send', {'message': message}).catchError((
        Object error,
      ) {
        messages.addError(error);
        return false;
      }),
    );
  }

  Future<void> close() async {
    debugPrint('[remote-native] close_invoking');
    await commands.invokeMethod<void>('close');
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await messages.close();
  }

  void _receive(dynamic event) {
    if (event is! Map) {
      messages.addError(
        const FormatException('Invalid native WebSocket event.'),
      );
      return;
    }
    debugPrint('[remote-native] event_received type=${event['type']}');
    switch (event['type']) {
      case 'message':
        final data = event['data'];
        if (data is String) {
          messages.add(data);
        } else {
          messages.addError(
            const FormatException('Invalid native WebSocket message.'),
          );
        }
      case 'closed':
        unawaited(messages.close());
    }
  }

  void _receiveError(Object error) {
    debugPrint(
      '[remote-native] event_error type=${error.runtimeType} error=$error',
    );
    messages.addError(error);
  }
}
