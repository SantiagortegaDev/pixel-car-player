import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/phone/controllers/auto_start_controller.dart';
import 'package:pixel_car_player/phone/controllers/pairing_controller.dart';
import 'package:pixel_car_player/phone/controllers/phone_settings.dart';
import 'package:pixel_car_player/phone/controllers/updates_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App de la que se leen los metadatos.
enum SourceApp {
  spotify('Spotify', 'com.spotify.music'),
  youtubeMusic('YouTube Music', 'com.google.android.apps.youtube.music'),
  any('Cualquier app', null);

  const SourceApp(this.label, this.package);
  final String label;
  final String? package;
}

class ConnectedCar {
  const ConnectedCar({
    required this.device,
    required this.transport,
    required this.address,
    this.authenticated,
    this.pairing = false,
  });
  final String device;
  final String transport; // wifi | bt
  final String address;

  /// v3: null = el nativo no lo informa (versiones anteriores).
  final bool? authenticated;

  /// v3: esperando el código de emparejamiento.
  final bool pairing;
  bool get isBluetooth => transport == 'bt';
}

class PhoneSession {
  const PhoneSession({
    this.package,
    this.title,
    this.artist,
    this.playing = false,
  });
  final String? package;
  final String? title;
  final String? artist;
  final bool playing;
}

/// Estado del transmisor (evento nativo `transmitterStatus`).
class TransmitterStatus {
  const TransmitterStatus({
    this.running = false,
    this.port,
    this.ips = const [],
    this.clients = const [],
    this.session,
    this.lyricsStatus,
  });

  final bool running;
  final int? port;
  final List<String> ips;
  final List<ConnectedCar> clients;
  final PhoneSession? session;
  final String? lyricsStatus;

  factory TransmitterStatus.fromMap(Map<String, dynamic> m) {
    final s = m['session'];
    return TransmitterStatus(
      running: m['running'] == true,
      port: (m['port'] as num?)?.toInt(),
      ips: ((m['ips'] as List?) ?? const []).map((e) => '$e').toList(),
      clients: ((m['clients'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (c) => ConnectedCar(
              device: '${c['device'] ?? 'Tableta'}',
              transport: '${c['transport'] ?? 'wifi'}',
              address: '${c['address'] ?? ''}',
              authenticated: c['authenticated'] is bool
                  ? c['authenticated'] as bool
                  : null,
              pairing: c['pairing'] == true,
            ),
          )
          .toList(),
      session: s is Map
          ? PhoneSession(
              package: s['package'] as String?,
              title: s['title'] as String?,
              artist: s['artist'] as String?,
              playing: s['playing'] == true,
            )
          : null,
      lyricsStatus: m['lyricsStatus'] as String?,
    );
  }
}

class PhoneController extends ChangeNotifier with WidgetsBindingObserver {
  PhoneController({NativeBridge? bridge})
    : _bridge = bridge ?? NativeBridge.instance;

  final NativeBridge _bridge;
  static const _kSource = 'phone_source';
  static const _kAutoStart = 'phone_autostart';
  static const _kHsSsid = 'phone_car_hotspot_ssid';
  static const _kHsPass = 'phone_car_hotspot_password';
  static const _kHsAuto = 'phone_car_hotspot_autoconnect';
  static const _kCarIp = 'phone_car_ip';

  bool get supported => _bridge.isSupported;

  // v3: sub-controladores (cada uno notifica por su cuenta).
  late final PhoneSettings settings = PhoneSettings();
  late final PairingController pairing = PairingController(
    _bridge,
    supported: supported,
  );
  late final AutoStartController carAutoStart = AutoStartController(
    _bridge,
    supported: supported,
  );
  late final UpdatesController updates = UpdatesController(
    _bridge,
    supported: supported,
  );
  bool _initStarted = false;

  TransmitterStatus status = const TransmitterStatus();
  SourceApp source = SourceApp.spotify;
  bool autoStart = true;
  bool notificationAccess = false;
  bool bluetoothPermission = false;
  bool notificationsPermission = false;
  bool busy = false;
  List<String> localIps = const [];

  // Hotspot del carro (conexión automática del celular).
  String hotspotSsid = '';
  String hotspotPassword = '';
  bool hotspotAuto = false;
  bool hotspotBusy = false;
  bool hotspotLoaded = false;
  bool wifiConnected = false;
  String? wifiSsid;

  /// IP manual del carro (la lee el marcador nativo: `flutter.phone_car_ip`).
  String carIp = '';

  /// SSID que la tableta compartió (evento `hotspotReceived`); `receivedTick`
  /// sube con cada evento para que la tarjeta recargue sus campos.
  String? receivedSsid;
  int receivedTick = 0;

  /// Sube cuando las prefs se recargan (al volver a la app) para refrescar campos.
  int reloadTick = 0;

  // Diagnóstico del enlace.
  List<String> linkLines = const [];
  List<Map<String, dynamic>> linkNetworks = const [];

  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  bool get permissionsOk => notificationAccess;
  bool get runtimeOk => bluetoothPermission && notificationsPermission;

  Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    WidgetsBinding.instance.addObserver(this);
    // Apariencia primero (la pantalla de arranque tapa esta espera).
    await settings.load();
    if (_disposed) return;
    try {
      final p = await SharedPreferences.getInstance();
      final pkg = p.getString(_kSource);
      source = SourceApp.values.firstWhere(
        (s) => s.name == pkg,
        orElse: () => SourceApp.spotify,
      );
      autoStart = p.getBool(_kAutoStart) ?? true;
      hotspotSsid = p.getString(_kHsSsid) ?? '';
      hotspotPassword = p.getString(_kHsPass) ?? '';
      hotspotAuto = p.getBool(_kHsAuto) ?? false;
      carIp = p.getString(_kCarIp) ?? '';
    } catch (_) {}
    hotspotLoaded = true;
    _initV3();

    if (!supported) {
      // Demo para web / capturas.
      notificationAccess = true;
      bluetoothPermission = true;
      notificationsPermission = true;
      localIps = const ['192.168.43.1'];
      status = const TransmitterStatus(
        running: true,
        port: 47321,
        ips: ['192.168.43.1'],
        clients: [
          ConnectedCar(
            device: 'Pantalla K24',
            transport: 'wifi',
            address: '192.168.43.57',
          ),
        ],
        session: PhoneSession(
          package: 'com.spotify.music',
          title: 'Luces de Neón',
          artist: 'Harmonix Band',
          playing: true,
        ),
        lyricsStatus: 'ok',
      );
      _notify();
      return;
    }

    _sub = _bridge.events.listen(handleEvent);
    await refreshPermissions();
    _applyStatus(await _bridge.getTransmitterStatus());
    localIps = await _bridge.getLocalIps();
    _notify();
    if (autoStart && permissionsOk && !status.running) {
      await start();
    }
    // Re-aplica la red sugerida (es inofensivo si ya estaba registrada).
    if (hotspotAuto && hotspotSsid.isNotEmpty) {
      try {
        await _bridge.setHotspotAutoConnect(
          ssid: hotspotSsid,
          password: hotspotPassword,
          enabled: true,
        );
      } catch (_) {}
    }
    await refreshWifi();
  }

  /// Despacha un evento nativo (`pcp/events`). Público para que las pruebas puedan
  /// inyectar eventos (p. ej. `pairNeeded`) sin plataforma.
  void handleEvent(Map<String, dynamic> e) {
    if (_disposed) return;
    switch (e['type']) {
      case 'transmitterStatus':
        _applyStatus(e);
      case 'hotspotReceived':
        if (e['ok'] == false) {
          reloadHotspotPrefs().then((_) => _notify());
        } else {
          onHotspotReceived('${e['ssid'] ?? ''}');
        }
      case 'pairNeeded' || 'pairResult':
        pairing.handleEvent(e);
      case 'updateProgress' || 'updateState':
        updates.handleEvent(e);
    }
  }

  Future<void> _initV3() async {
    await Future.wait([pairing.init(), carAutoStart.init(), updates.init()]);
    if (_disposed) return;
    await updates.maybeAutoCheck();
  }

  /// Restaura una copia (JSON) y vuelve a aplicar lo que vive en el nativo: reglas de
  /// encendido automático y red del hotspot del carro.
  Future<({bool ok, String message})> restoreBackup(String json) async {
    final int n;
    try {
      n = await PhoneBackup.restore(json);
    } on FormatException catch (e) {
      return (ok: false, message: e.message);
    } catch (e) {
      return (ok: false, message: 'No se pudo restaurar: $e');
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      source = SourceApp.values.firstWhere(
        (s) => s.name == p.getString(_kSource),
        orElse: () => SourceApp.spotify,
      );
      autoStart = p.getBool(_kAutoStart) ?? true;
    } catch (_) {}
    await reloadHotspotPrefs();
    await settings.load();
    await pairing.init();
    await carAutoStart.loadPrefs();
    await carAutoStart.apply();
    if (supported && hotspotSsid.isNotEmpty) {
      try {
        await _bridge.setHotspotAutoConnect(
          ssid: hotspotSsid,
          password: hotspotPassword,
          enabled: hotspotAuto,
        );
      } catch (_) {}
    }
    _notify();
    return (ok: true, message: 'Copia restaurada: $n ajustes aplicados.');
  }

  /// La tableta mandó las credenciales de su hotspot: el nativo ya las guardó en
  /// las prefs, aquí se recargan y se avisa a la UI.
  Future<void> onHotspotReceived(String ssid) async {
    await reloadHotspotPrefs();
    receivedSsid = ssid.isNotEmpty
        ? ssid
        : (hotspotSsid.isNotEmpty ? hotspotSsid : null);
    receivedTick++;
    _notify();
    refreshWifi();
  }

  Future<void> reloadHotspotPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      hotspotSsid = p.getString(_kHsSsid) ?? '';
      hotspotPassword = p.getString(_kHsPass) ?? '';
      hotspotAuto = p.getBool(_kHsAuto) ?? false;
      carIp = p.getString(_kCarIp) ?? '';
      reloadTick++;
    } catch (_) {}
  }

  Future<void> setCarIp(String v) async {
    carIp = v.trim();
    try {
      final p = await SharedPreferences.getInstance();
      if (carIp.isEmpty) {
        await p.remove(_kCarIp);
      } else {
        await p.setString(_kCarIp, carIp);
      }
    } catch (_) {}
  }

  /// Redes Wi-Fi + últimas líneas del registro del enlace (vacío sin nativo).
  Future<void> refreshLink() async {
    if (_disposed) return;
    try {
      final d = await _bridge.getLinkDiagnostics();
      final lines = ((d['lines'] as List?) ?? const [])
          .map((e) => '$e')
          .toList();
      var nets = ((d['networks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (nets.isEmpty) nets = await _wifiNetworks();
      linkLines = lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
      linkNetworks = nets;
    } catch (_) {
      linkLines = const [];
      linkNetworks = const [];
    }
    _notify();
  }

  Future<List<Map<String, dynamic>>> _wifiNetworks() async {
    try {
      return (await _bridge.getWifiNetworks())
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearLink() async {
    try {
      await _bridge.clearLinkDiagnostics();
    } catch (_) {}
    linkLines = const [];
    _notify();
  }

  /// Estado del Wi-Fi del celular (vacío en web / sin nativo).
  Future<void> refreshWifi() async {
    if (_disposed || !supported) return;
    try {
      final m = await _bridge.getWifiStatus();
      wifiConnected = m['connected'] == true;
      final s = m['ssid'];
      wifiSsid = (s is String && s.isNotEmpty && s != '<unknown ssid>')
          ? s
          : null;
    } catch (_) {
      wifiConnected = false;
      wifiSsid = null;
    }
    _notify();
  }

  /// Guarda la red del carro y (des)activa la conexión automática.
  /// Devuelve el mensaje a mostrar y si fue exitoso.
  Future<({bool ok, String message})> saveHotspot({
    required String ssid,
    required String password,
    required bool enabled,
  }) async {
    ssid = ssid.trim();
    if (enabled && ssid.isEmpty) {
      return (ok: false, message: 'Escribe el nombre de la red (SSID).');
    }
    if (enabled && password.isNotEmpty && password.length < 8) {
      return (
        ok: false,
        message: 'La contraseña debe tener al menos 8 caracteres.',
      );
    }
    hotspotBusy = true;
    hotspotSsid = ssid;
    hotspotPassword = password;
    hotspotAuto = enabled;
    _notify();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHsSsid, ssid);
      await p.setString(_kHsPass, password);
      await p.setBool(_kHsAuto, enabled);
    } catch (_) {}
    try {
      if (!enabled) {
        if (supported && ssid.isNotEmpty) {
          await _bridge.setHotspotAutoConnect(
            ssid: ssid,
            password: password,
            enabled: false,
          );
        }
        return (ok: true, message: 'Conexión automática desactivada.');
      }
      if (!supported) {
        return (
          ok: true,
          message:
              'Guardado (la conexión automática solo funciona en el celular).',
        );
      }
      final r = await _bridge.setHotspotAutoConnect(
        ssid: ssid,
        password: password,
        enabled: true,
      );
      if (r['ok'] == true) {
        final android10 = r['method'] == 'suggestion'
            ? ' Si aparece «¿Permitir redes sugeridas?», acéptalo.'
            : '';
        return (
          ok: true,
          message:
              'Listo: el celular se unirá solo a «$ssid» cuando esté cerca.$android10',
        );
      }
      final e = r['error'];
      return (
        ok: false,
        message: (e is String && e.isNotEmpty)
            ? e
            : 'No se pudo registrar la red.',
      );
    } catch (e) {
      return (ok: false, message: 'No se pudo registrar la red: $e');
    } finally {
      hotspotBusy = false;
      _notify();
      refreshWifi();
    }
  }

  void _applyStatus(Map<String, dynamic> m) {
    status = TransmitterStatus.fromMap(m);
    if (status.ips.isNotEmpty) localIps = status.ips;
    _notify();
  }

  Future<void> refreshPermissions() async {
    notificationAccess = await _bridge.hasNotificationAccess();
    _notify();
  }

  Future<void> requestPermissions() async {
    final r = await _bridge.requestRuntimePermissions();
    bluetoothPermission = r['bluetoothConnect'] == true;
    notificationsPermission = r['postNotifications'] == true;
    _notify();
  }

  Future<void> openNotificationSettings() =>
      _bridge.openNotificationAccessSettings();

  Future<void> toggle() => status.running ? stop() : start();

  Future<void> start() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      if (!runtimeOk) await requestPermissions();
      final ok = await _bridge.startTransmitter(sourcePackage: source.package);
      if (ok) {
        _applyStatus(await _bridge.getTransmitterStatus());
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      await _bridge.stopTransmitter();
      _applyStatus(await _bridge.getTransmitterStatus());
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> setSource(SourceApp s) async {
    source = s;
    _notify();
    try {
      (await SharedPreferences.getInstance()).setString(_kSource, s.name);
    } catch (_) {}
    if (status.running && supported) {
      await _bridge.stopTransmitter();
      await start();
    }
  }

  Future<void> setAutoStart(bool v) async {
    autoStart = v;
    _notify();
    try {
      (await SharedPreferences.getInstance()).setBool(_kAutoStart, v);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && supported) {
      pairing.refreshPaired();
      updates.refreshInstallPermission();
      // Volvió del instalador (cancelado o falló): sale del estado "instalando".
      if (updates.phase == UpdatePhase.installing) {
        updates.handleEvent(const {'type': 'updateState', 'state': 'idle'});
      }
      refreshPermissions();
      refreshWifi();
      reloadHotspotPrefs().then((_) => _notify());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    settings.dispose();
    pairing.dispose();
    carAutoStart.dispose();
    updates.dispose();
    super.dispose();
  }
}
