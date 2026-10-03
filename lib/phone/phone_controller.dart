import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
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
  });
  final String device;
  final String transport; // wifi | bt
  final String address;
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

  bool get supported => _bridge.isSupported;

  TransmitterStatus status = const TransmitterStatus();
  SourceApp source = SourceApp.spotify;
  bool autoStart = true;
  bool notificationAccess = false;
  bool bluetoothPermission = false;
  bool notificationsPermission = false;
  bool busy = false;
  List<String> localIps = const [];

  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  bool get permissionsOk => notificationAccess;
  bool get runtimeOk => bluetoothPermission && notificationsPermission;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final p = await SharedPreferences.getInstance();
      final pkg = p.getString(_kSource);
      source = SourceApp.values.firstWhere(
        (s) => s.name == pkg,
        orElse: () => SourceApp.spotify,
      );
      autoStart = p.getBool(_kAutoStart) ?? true;
    } catch (_) {}

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

    _sub = _bridge.events.listen((e) {
      if (e['type'] == 'transmitterStatus') _applyStatus(e);
    });
    await refreshPermissions();
    _applyStatus(await _bridge.getTransmitterStatus());
    localIps = await _bridge.getLocalIps();
    _notify();
    if (autoStart && permissionsOk && !status.running) {
      await start();
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
      refreshPermissions();
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
    super.dispose();
  }
}
