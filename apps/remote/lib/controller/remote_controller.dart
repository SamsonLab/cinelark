import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/remote_protocol.dart';
import '../models/remote_state.dart';
import '../services/credential_store.dart';
import '../services/remote_transport.dart';

enum RemoteConnectionPhase {
  loading,
  deviceSelection,
  unpaired,
  connecting,
  awaitingApproval,
  connected,
  reconnecting,
  failed,
}

class RemoteController extends ChangeNotifier with WidgetsBindingObserver {
  RemoteController({PairedMacStore? store})
    : _store = store ?? CredentialStore() {
    _transport = RemoteTransport(
      onEnvelope: _receive,
      onDisconnected: _didDisconnect,
    );
  }

  static const _uuid = Uuid();
  final PairedMacStore _store;
  late final RemoteTransport _transport;

  RemoteConnectionPhase phase = RemoteConnectionPhase.loading;
  List<PairedMac> pairedMacs = const [];
  PairedMac? pairedMac;
  AppSnapshot? appSnapshot;
  TextInputSnapshot? textInputSnapshot;
  PlaybackSnapshot? playbackSnapshot;
  Set<String> capabilities = {};
  String? errorCode;
  String? authenticationError;
  bool isSubmittingLogin = false;

  PairingPayload? _pairingPayload;
  String? _pendingDeviceId;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  String? _pendingText;
  bool _textUpdateInFlight = false;
  bool _commitTextWhenSynchronized = false;

  bool get isPaired => pairedMac != null;
  bool get isConnected => phase == RemoteConnectionPhase.connected;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    pairedMacs = await _store.loadAll();
    pairedMac = null;
    phase = RemoteConnectionPhase.deviceSelection;
    debugPrint('[remote] initialized devices=${pairedMacs.length}');
    notifyListeners();
  }

  Future<void> selectDevice(PairedMac device) async {
    if (!pairedMacs.any((paired) => paired.serviceId == device.serviceId)) {
      return;
    }
    await _leaveCurrentSession(RemoteConnectionPhase.deviceSelection);
    pairedMac = device;
    _reconnectAttempt = 0;
    await reconnect();
  }

  Future<void> showDevices() =>
      _leaveCurrentSession(RemoteConnectionPhase.deviceSelection);

  Future<void> addDevice() =>
      _leaveCurrentSession(RemoteConnectionPhase.unpaired);

  Future<void> retryPairing() =>
      _leaveCurrentSession(RemoteConnectionPhase.unpaired);

  Future<void> removeDevice(PairedMac device) async {
    if (pairedMac?.serviceId == device.serviceId) {
      await _leaveCurrentSession(RemoteConnectionPhase.deviceSelection);
    }
    final updated = List<PairedMac>.unmodifiable(
      pairedMacs.where((paired) => paired.serviceId != device.serviceId),
    );
    await _store.saveAll(updated);
    pairedMacs = updated;
    notifyListeners();
  }

  Future<void> pair(String rawPayload) async {
    final payload = PairingPayload.parse(rawPayload);
    debugPrint(
      '[remote] pairing_payload_valid host=${payload.host} port=${payload.port} '
      'expiresAt=${payload.expiresAt.toIso8601String()}',
    );
    _reconnectTimer?.cancel();
    _pairingPayload = payload;
    _pendingDeviceId = _uuid.v4();
    pairedMac = null;
    errorCode = null;
    phase = RemoteConnectionPhase.connecting;
    debugPrint('[remote] pairing_connecting');
    notifyListeners();
    try {
      await _transport.connect(payload.endpoint, payload.fingerprint);
      debugPrint('[remote] pairing_transport_connected');
    } on Object catch (error) {
      debugPrint(
        '[remote] pairing_connect_failed type=${error.runtimeType} error=$error',
      );
      _pairingPayload = null;
      _pendingDeviceId = null;
      phase = RemoteConnectionPhase.failed;
      errorCode = 'pairingUnavailable';
      notifyListeners();
    }
  }

  Future<void> reconnect() async {
    final paired = pairedMac;
    if (paired == null || _transport.isConnected) return;
    _reconnectTimer?.cancel();
    phase = _reconnectAttempt == 0
        ? RemoteConnectionPhase.connecting
        : RemoteConnectionPhase.reconnecting;
    errorCode = null;
    notifyListeners();
    try {
      debugPrint(
        '[remote] reconnecting host=${paired.host} port=${paired.port} '
        'attempt=$_reconnectAttempt',
      );
      await _transport.connect(paired.endpoint, paired.fingerprint);
      debugPrint('[remote] reconnect_transport_connected');
    } on Object catch (error) {
      debugPrint(
        '[remote] reconnect_failed type=${error.runtimeType} error=$error',
      );
      _scheduleReconnect();
    }
  }

  Future<void> forget() async {
    final selected = pairedMac;
    if (selected == null) {
      await retryPairing();
      return;
    }
    debugPrint('[remote] pairing_removed service=${selected.serviceId}');
    await removeDevice(selected);
  }

  void submitCredentials({
    required String username,
    required String password,
    String? totpCode,
  }) {
    if (!capabilities.contains('auth.remoteEntry') || isSubmittingLogin) return;
    isSubmittingLogin = true;
    authenticationError = null;
    notifyListeners();
    _send('auth.submitCredentials', {
      'username': username,
      'password': password,
      if (totpCode != null && totpCode.trim().isNotEmpty)
        'totpCode': totpCode.trim(),
    });
  }

  void move(String direction) =>
      _send('navigation.move', {'direction': direction});
  void select() => _send('navigation.select');
  void back() => _send('navigation.back');
  void openSection(String section) =>
      _send('navigation.openSection', {'section': section});
  void activateMac() => _send('app.activate');

  void dismissError() {
    if (errorCode == null) return;
    errorCode = null;
    notifyListeners();
  }

  void updateText(String text) {
    final snapshot = textInputSnapshot;
    if (snapshot == null || text.length > snapshot.maximumLength) return;
    _pendingText = text;
    _flushTextUpdate();
  }

  void commitText() {
    final snapshot = textInputSnapshot;
    if (snapshot == null) return;
    if (_textUpdateInFlight ||
        (_pendingText != null && _pendingText != snapshot.text)) {
      _commitTextWhenSynchronized = true;
      _flushTextUpdate();
      return;
    }
    _send('textInput.commit', {
      'sessionID': snapshot.sessionId,
      'revision': snapshot.revision,
    });
  }

  void cancelText() {
    final snapshot = textInputSnapshot;
    if (snapshot == null) return;
    _pendingText = null;
    _commitTextWhenSynchronized = false;
    _send('textInput.cancel', {
      'sessionID': snapshot.sessionId,
      'revision': snapshot.revision,
    });
  }

  void togglePause() => _playbackCommand('playback.togglePause');
  void seekRelative(double seconds) =>
      _playbackCommand('playback.seekRelative', {'seconds': seconds});
  void seekAbsolute(double seconds) =>
      _playbackCommand('playback.seekAbsolute', {'seconds': seconds});
  void setRate(double rate) =>
      _playbackCommand('playback.setRate', {'rate': rate});
  void setFullscreen(bool fullscreen) =>
      _playbackCommand('playback.setFullscreen', {'fullscreen': fullscreen});
  void playPrevious() => _revisionedPlaybackCommand('playback.playPrevious');
  void playNext() => _revisionedPlaybackCommand('playback.playNext');
  void selectAudioTrack(int trackId) => _revisionedPlaybackCommand(
    'playback.selectAudioTrack',
    {'trackID': trackId},
  );
  void selectSubtitleTrack(int? trackId) => _revisionedPlaybackCommand(
    'playback.selectSubtitleTrack',
    {'trackID': trackId},
  );
  void setVolume(double volume) =>
      _playbackCommand('audio.setVolume', {'volume': volume});
  void setMuted(bool muted) =>
      _playbackCommand('audio.setMuted', {'muted': muted});
  void closePlayback() => _playbackCommand('playback.closeAndActivateApp');

  Future<void> _receive(RemoteEnvelope envelope) async {
    debugPrint(
      '[remote] envelope_received type=${envelope.type} '
      'sequence=${envelope.sequence}',
    );
    switch (envelope.type) {
      case 'session.challenge':
        _handleChallenge(envelope.payload);
      case 'pairing.pending':
        debugPrint('[remote] pairing_awaiting_approval');
        phase = RemoteConnectionPhase.awaitingApproval;
        notifyListeners();
      case 'pairing.approved':
        debugPrint('[remote] pairing_approved');
        await _completePairing(envelope.payload);
      case 'pairing.rejected':
        _pairingPayload = null;
        _pendingDeviceId = null;
        phase = RemoteConnectionPhase.failed;
        errorCode = envelope.payload['code'] as String? ?? 'pairingRejected';
        debugPrint('[remote] pairing_rejected code=$errorCode');
        notifyListeners();
      case 'session.authenticated':
        capabilities = _stringSet(envelope.payload['capabilities']);
      case 'session.ready':
        capabilities = _stringSet(envelope.payload['capabilities']);
        _reconnectAttempt = 0;
        phase = RemoteConnectionPhase.connected;
        errorCode = null;
        debugPrint('[remote] session_ready');
        notifyListeners();
      case 'capabilities.changed':
        capabilities = _stringSet(envelope.payload['capabilities']);
        notifyListeners();
      case 'app.snapshot':
        appSnapshot = AppSnapshot.fromJson(envelope.payload);
        notifyListeners();
      case 'textInput.snapshot':
        _receiveTextInput(envelope.payload);
      case 'playback.snapshot':
        final revision = envelope.revision ?? 0;
        if (playbackSnapshot == null ||
            revision >= playbackSnapshot!.revision) {
          playbackSnapshot = PlaybackSnapshot.fromJson(
            envelope.payload,
            revision: revision,
          );
          notifyListeners();
        }
      case 'auth.result':
        isSubmittingLogin = false;
        final succeeded = envelope.payload['succeeded'] == true;
        authenticationError = succeeded
            ? null
            : envelope.payload['code'] as String? ?? 'authenticationFailed';
        notifyListeners();
      case 'command.ack':
        final accepted = envelope.payload['accepted'] == true;
        final acknowledgementCode = envelope.payload['code'] as String?;
        debugPrint(
          '[remote] command_ack accepted=$accepted code=$acknowledgementCode',
        );
        if (accepted) {
          if (errorCode != null) {
            errorCode = null;
            notifyListeners();
          }
        } else {
          errorCode = envelope.payload['code'] as String? ?? 'invalidState';
          if (errorCode == 'staleRevision') {
            _send('app.requestSnapshot');
          }
          notifyListeners();
        }
      case 'session.error':
        final code = envelope.payload['code'] as String? ?? 'internal';
        debugPrint('[remote] session_error code=$code');
        if (code == 'unauthenticated' || code == 'revoked') {
          await forget();
        } else {
          errorCode = code;
          notifyListeners();
        }
      case 'session.revoked':
        await forget();
    }
  }

  void _handleChallenge(Map<String, dynamic> payload) {
    final serviceId = payload['serviceID'] as String?;
    final connectionId = payload['connectionID'] as String?;
    final nonce = payload['nonce'] as String?;
    if (serviceId == null || connectionId == null || nonce == null) {
      throw const FormatException('Invalid Remote challenge.');
    }
    final pairing = _pairingPayload;
    if (pairing != null) {
      if (pairing.serviceId != serviceId ||
          pairing.expiresAt.isBefore(DateTime.now().toUtc())) {
        throw const FormatException(
          'Pairing challenge does not match the code.',
        );
      }
      debugPrint('[remote] challenge_valid sending=pairing.request');
      _transport.send(
        'pairing.request',
        payload: {
          'secret': pairing.secret,
          'deviceID': _pendingDeviceId,
          'deviceName': Platform.isIOS ? 'iPhone Remote' : 'Android Remote',
        },
      );
      return;
    }

    final paired = pairedMac;
    if (paired == null || paired.serviceId != serviceId) {
      throw const FormatException('Unknown CineLark service.');
    }
    final proof = remoteAuthenticationProof(
      credentialBase64Url: paired.credential,
      serviceId: serviceId,
      connectionId: connectionId,
      nonce: nonce,
    );
    _transport.send(
      'session.authenticate',
      payload: {'deviceID': paired.deviceId, 'proof': proof},
    );
  }

  Future<void> _completePairing(Map<String, dynamic> payload) async {
    final pairing = _pairingPayload;
    final deviceId = payload['deviceID'] as String?;
    final credential = payload['credential'] as String?;
    if (pairing == null ||
        deviceId == null ||
        credential == null ||
        credential.length != 43) {
      throw const FormatException('Invalid pairing approval.');
    }
    final paired = PairedMac(
      serviceId: pairing.serviceId,
      name: pairing.name,
      platform: pairing.platform,
      host: pairing.host,
      port: pairing.port,
      fingerprint: pairing.fingerprint,
      deviceId: deviceId,
      credential: credential,
    );
    final updated = List<PairedMac>.unmodifiable([
      paired,
      ...pairedMacs.where((item) => item.serviceId != paired.serviceId),
    ]);
    await _store.saveAll(updated);
    pairedMacs = updated;
    debugPrint('[remote] pairing_credential_saved');
    pairedMac = paired;
    capabilities = _stringSet(payload['capabilities']);
    _pairingPayload = null;
    _pendingDeviceId = null;
    notifyListeners();
  }

  void _receiveTextInput(Map<String, dynamic> payload) {
    final active = payload['active'];
    if (active is! Map) {
      textInputSnapshot = null;
      _pendingText = null;
      _textUpdateInFlight = false;
      _commitTextWhenSynchronized = false;
      notifyListeners();
      return;
    }
    final snapshot = TextInputSnapshot.fromJson(
      Map<String, dynamic>.from(active),
    );
    textInputSnapshot = snapshot;
    _textUpdateInFlight = false;
    if (_pendingText == snapshot.text) _pendingText = null;
    notifyListeners();
    if (_pendingText != null && _pendingText != snapshot.text) {
      _flushTextUpdate();
    } else if (_commitTextWhenSynchronized) {
      _commitTextWhenSynchronized = false;
      commitText();
    }
  }

  void _flushTextUpdate() {
    final snapshot = textInputSnapshot;
    final text = _pendingText;
    if (snapshot == null || text == null || _textUpdateInFlight) return;
    if (text == snapshot.text) {
      _pendingText = null;
      if (_commitTextWhenSynchronized) {
        _commitTextWhenSynchronized = false;
        commitText();
      }
      return;
    }
    _textUpdateInFlight = true;
    _send('textInput.update', {
      'sessionID': snapshot.sessionId,
      'revision': snapshot.revision,
      'text': text,
    });
  }

  void _playbackCommand(
    String type, [
    Map<String, dynamic> additional = const {},
  ]) {
    final snapshot = playbackSnapshot;
    if (snapshot?.playbackId == null) return;
    _send(type, {'playbackID': snapshot!.playbackId, ...additional});
  }

  void _revisionedPlaybackCommand(
    String type, [
    Map<String, dynamic> additional = const {},
  ]) {
    final snapshot = playbackSnapshot;
    if (snapshot?.playbackId == null) return;
    _send(type, {
      'playbackID': snapshot!.playbackId,
      'revision': snapshot.revision,
      ...additional,
    }, snapshot.revision);
  }

  void _send(
    String type, [
    Map<String, dynamic> payload = const {},
    int? revision,
  ]) {
    try {
      _transport.send(type, payload: payload, revision: revision);
    } on Object {
      errorCode = 'disconnected';
      notifyListeners();
    }
  }

  void _didDisconnect(Object? error) {
    if (_disposed) return;
    debugPrint(
      '[remote] transport_disconnected pairing=${_pairingPayload != null} '
      'type=${error?.runtimeType} error=$error',
    );
    if (_pairingPayload != null) {
      phase = RemoteConnectionPhase.failed;
      errorCode = 'pairingUnavailable';
      _pairingPayload = null;
      _pendingDeviceId = null;
      notifyListeners();
      return;
    }
    if (pairedMac != null) {
      _scheduleReconnect();
    } else if (phase != RemoteConnectionPhase.deviceSelection &&
        phase != RemoteConnectionPhase.unpaired) {
      phase = RemoteConnectionPhase.unpaired;
      notifyListeners();
    }
  }

  Future<void> _leaveCurrentSession(RemoteConnectionPhase destination) async {
    debugPrint('[remote] session_left destination=${destination.name}');
    _reconnectTimer?.cancel();
    pairedMac = null;
    _pairingPayload = null;
    _pendingDeviceId = null;
    appSnapshot = null;
    textInputSnapshot = null;
    playbackSnapshot = null;
    capabilities = {};
    errorCode = null;
    authenticationError = null;
    isSubmittingLogin = false;
    _pendingText = null;
    _textUpdateInFlight = false;
    _commitTextWhenSynchronized = false;
    phase = destination;
    notifyListeners();
    await _transport.close();
  }

  void _scheduleReconnect() {
    if (_disposed || pairedMac == null) return;
    phase = RemoteConnectionPhase.reconnecting;
    errorCode = 'disconnected';
    notifyListeners();
    _reconnectTimer?.cancel();
    final seconds = (1 << _reconnectAttempt.clamp(0, 5)).clamp(1, 30);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), reconnect);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && pairedMac != null) {
      reconnect();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    unawaited(_transport.close());
    super.dispose();
  }
}

Set<String> _stringSet(Object? value) =>
    (value as List? ?? const []).whereType<String>().toSet();
