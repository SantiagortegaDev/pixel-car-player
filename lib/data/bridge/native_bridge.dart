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
  /// Inicio automático: el receptor de arranque lee la preferencia `car_autostart`.
  /// Android 10+ exige el permiso "mostrar sobre otras apps" para abrir la app sola.
  Future<bool> canDrawOverlays() async =>
      await _call<bool>('canDrawOverlays') ?? true;
  Future<void> openOverlaySettings() => _call('openOverlaySettings');
  Future<void> openBatteryOptimizationSettings() =>
      _call('openBatteryOptimizationSettings');
  Future<bool> localMediaCommand(String action, {int? positionMs}) async =>
      await _call<bool>('localMediaCommand',
          {'action': action, 'positionMs': ?positionMs}) ??
      false;
  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // ---- Tableta: hotspot del carro ----
  /// `{enabled: bool?, ssid: String?, password: String?, method: String,
  ///   canWriteSettings: bool}`; `enabled` null = no se pudo leer.
  Future<Map<String, dynamic>> getHotspotState() async =>
      _map(await _call<Map>('getHotspotState'));

  /// Intenta encender/apagar el hotspot (tethering → wifiAp → localOnly).
  /// `{ok: bool, method: 'tethering'|'wifiAp'|'localOnly'|'none',
  ///   needsSettings: bool, ssid: String?, password: String?}`.
  Future<Map<String, dynamic>> setHotspotEnabled(bool enabled) async =>
      _map(await _call<Map>('setHotspotEnabled', {'enabled': enabled}));
  Future<void> openHotspotSettings() => _call('openHotspotSettings');
  Future<void> openWriteSettings() => _call('openWriteSettings');

  /// IPs vecinas (tabla ARP): clientes del hotspot de la tableta.
  Future<List<String>> getNeighborIps() async =>
      (await _call<List>('getNeighborIps') ?? const []).cast<String>();

  // ---- Tableta: visualizador con el audio real (Visualizer, sesión 0) ----
  Future<bool> requestAudioPermission() async =>
      await _call<bool>('requestAudioPermission') ?? false;

  /// Empieza a emitir eventos `{type:'fft', bands: List<double>(64, 0..1), rms: double}`
  /// a ~30 fps. false si no hay permiso o el equipo no lo soporta.
  Future<bool> startVisualizer() async =>
      await _call<bool>('startVisualizer') ?? false;
  Future<void> stopVisualizer() => _call('stopVisualizer');

  // ---- Tableta: app acompañante (p. ej. la de música Bluetooth del radio) ----
  /// `[{package, label, icon: Uint8List(PNG 96px)?}]` ordenado por nombre.
  Future<List<Map<String, dynamic>>> getLaunchableApps() async =>
      (await _call<List>('getLaunchableApps') ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// Abre [package]; con [background] vuelve a traer Pixel Car Player al frente
  /// después de [delayMs] para que la otra app quede corriendo detrás.
  Future<bool> launchApp(String package,
          {bool background = true, int delayMs = 1500}) async =>
      await _call<bool>('launchApp', {
        'package': package,
        'background': background,
        'delayMs': delayMs,
      }) ??
      false;
  Future<void> bringToFront() => _call('bringToFront');

  // ---- Celular: conectarse solo al hotspot del carro ----
  /// Registra (o quita con enabled=false) la red del carro para conexión automática.
  /// `{ok: bool, method: 'suggestion'|'legacy'|'none', error: String?}`.
  Future<Map<String, dynamic>> setHotspotAutoConnect(
          {required String ssid, required String password, required bool enabled}) async =>
      _map(await _call<Map>('setHotspotAutoConnect',
          {'ssid': ssid, 'password': password, 'enabled': enabled}));

  /// `{connected: bool, ssid: String?}` (ssid puede faltar sin permiso de ubicación).
  Future<Map<String, dynamic>> getWifiStatus() async =>
      _map(await _call<Map>('getWifiStatus'));
}
