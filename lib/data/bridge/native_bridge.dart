import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Envoltorio tipado del canal nativo `pcp/native` + `pcp/events`.
/// Ver docs/CONTRACT.md §2. En web/desktop todos los métodos devuelven
/// valores neutros para que la UI funcione en modo demo.
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _method = MethodChannel('pcp/native');
  static const _events = EventChannel('pcp/events');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Stream<Map<String, dynamic>>? _eventStream;

  /// Stream único de eventos nativos (`type`: transmitterStatus | rfcomm | localMedia).
  Stream<Map<String, dynamic>> get events {
    if (!isSupported) return const Stream.empty();
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .asBroadcastStream();
  }

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _method.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeBridge.$method falló: ${e.code} ${e.message}');
      return null;
    }
  }

  // ---- Ambos lados ----
  Future<Map<String, dynamic>> getDeviceInfo() async =>
      Map<String, dynamic>.from(await _call<Map>('getDeviceInfo') ?? const {});
  Future<bool> hasNotificationAccess() async =>
      await _call<bool>('hasNotificationAccess') ?? false;
  Future<void> openNotificationAccessSettings() =>
      _call('openNotificationAccessSettings');
  Future<Map<String, dynamic>> requestRuntimePermissions() async =>
      Map<String, dynamic>.from(
          await _call<Map>('requestRuntimePermissions') ?? const {});
  Future<List<String>> getLocalIps() async =>
      (await _call<List>('getLocalIps') ?? const []).cast<String>();

  // ---- Celular (transmisor) ----
  Future<bool> startTransmitter({String? sourcePackage = 'com.spotify.music'}) async =>
      await _call<bool>('startTransmitter', {'sourcePackage': sourcePackage}) ?? false;
  Future<void> stopTransmitter() => _call('stopTransmitter');
  Future<Map<String, dynamic>> getTransmitterStatus() async =>
      Map<String, dynamic>.from(
          await _call<Map>('getTransmitterStatus') ?? const {'running': false});

  // ---- Tableta (pantalla) ----
  Future<void> setKeepScreenOn(bool on) => _call('setKeepScreenOn', {'on': on});
  Future<String?> getGatewayIp() => _call<String>('getGatewayIp');
  Future<void> acquireMulticastLock() => _call('acquireMulticastLock');
  Future<void> releaseMulticastLock() => _call('releaseMulticastLock');
  Future<List<Map<String, dynamic>>> getBondedDevices() async =>
      (await _call<List>('getBondedDevices') ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<bool> connectRfcomm(String address) async =>
      await _call<bool>('connectRfcomm', {'address': address}) ?? false;
  Future<bool> sendRfcomm(String line) async =>
      await _call<bool>('sendRfcomm', {'line': line}) ?? false;
  Future<void> disconnectRfcomm() => _call('disconnectRfcomm');
  Future<bool> startLocalMediaWatch() async =>
      await _call<bool>('startLocalMediaWatch') ?? false;
  Future<void> stopLocalMediaWatch() => _call('stopLocalMediaWatch');
  Future<bool> localMediaCommand(String action, {int? positionMs}) async =>
      await _call<bool>('localMediaCommand',
          {'action': action, if (positionMs != null) 'positionMs': positionMs}) ??
      false;
}
