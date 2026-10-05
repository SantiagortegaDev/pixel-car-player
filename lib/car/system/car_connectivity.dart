import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';

/// Equipo Bluetooth conectado al radio.
@immutable
class BtDevice {
  const BtDevice({required this.name, required this.address, this.profiles = const []});
  final String name;
  final String address;

  /// `a2dp`, `hfp`, `avrcp`…
  final List<String> profiles;

  static BtDevice? fromMap(Object? m) {
    if (m is! Map) return null;
    final name = m['name'];
    final address = m['address'];
    final profiles = m['profiles'];
    return BtDevice(
      name: name is String && name.isNotEmpty ? name : (address is String ? address : 'Bluetooth'),
      address: address is String ? address : '',
      profiles: profiles is List ? profiles.map((e) => '$e').toList() : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BtDevice && other.name == name && other.address == address && listEquals(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(name, address, Object.hashAll(profiles));
}

/// Estado del Bluetooth y del Wi-Fi del radio (`getConnectivityStatus` + eventos `connectivity`).
@immutable
class ConnectivityInfo {
  const ConnectivityInfo({
    this.loaded = false,
    this.btEnabled,
    this.btDevices = const [],
    this.wifiEnabled,
    this.wifiConnected = false,
    this.wifiSsid,
    this.hotspotOn,
    this.hotspotClients,
  });

  final bool loaded;
  final bool? btEnabled;
  final List<BtDevice> btDevices;
  final bool? wifiEnabled;
  final bool wifiConnected;
  final String? wifiSsid;
  final bool? hotspotOn;
  final int? hotspotClients;

  factory ConnectivityInfo.fromMap(Map<String, dynamic> m) {
    bool? b(Object? v) => v is bool ? v : null;
    final ssid = m['wifiSsid'];
    final clients = m['hotspotClients'];
    return ConnectivityInfo(
      loaded: true,
      btEnabled: b(m['btEnabled']),
      btDevices: [for (final d in (m['btDevices'] is List ? m['btDevices'] as List : const [])) ?BtDevice.fromMap(d)],
      wifiEnabled: b(m['wifiEnabled']),
      wifiConnected: m['wifiConnected'] == true,
      // Android devuelve "<unknown ssid>" sin permiso de ubicación.
      wifiSsid: ssid is String && ssid.isNotEmpty && !ssid.contains('unknown ssid') ? ssid.replaceAll('"', '') : null,
      hotspotOn: b(m['hotspotOn']),
      hotspotClients: clients is num ? clients.toInt() : null,
    );
  }

  /// El equipo Bluetooth que más probablemente es el celular (con A2DP si hay).
  BtDevice? get mainBt {
    if (btDevices.isEmpty) return null;
    for (final d in btDevices) {
      if (d.profiles.any((p) => p.toLowerCase().contains('a2dp'))) return d;
    }
    return btDevices.first;
  }

  bool get hasWifiInfo => wifiConnected || hotspotOn == true;

  @override
  bool operator ==(Object other) =>
      other is ConnectivityInfo &&
      other.loaded == loaded &&
      other.btEnabled == btEnabled &&
      listEquals(other.btDevices, btDevices) &&
      other.wifiEnabled == wifiEnabled &&
      other.wifiConnected == wifiConnected &&
      other.wifiSsid == wifiSsid &&
      other.hotspotOn == hotspotOn &&
      other.hotspotClients == hotspotClients;

  @override
  int get hashCode => Object.hash(
    loaded,
    btEnabled,
    Object.hashAll(btDevices),
    wifiEnabled,
    wifiConnected,
    wifiSsid,
    hotspotOn,
    hotspotClients,
  );
}

/// Vigila el Bluetooth y el Wi-Fi del radio para el encabezado y Diagnóstico.
class CarConnectivity extends ChangeNotifier {
  CarConnectivity({NativeBridge? bridge}) : _bridge = bridge ?? NativeBridge.instance;

  final NativeBridge _bridge;
  ConnectivityInfo _info = const ConnectivityInfo();
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _poll;
  bool _started = false;
  bool _disposed = false;

  ConnectivityInfo get info => _info;
  bool get supported => _bridge.isSupported;

  set info(ConnectivityInfo v) {
    if (v == _info || _disposed) return;
    _info = v;
    notifyListeners();
  }

  /// Datos de ejemplo (demo web / capturas).
  void fillSample() => info = ConnectivityInfo.fromMap(const {
    'btEnabled': true,
    'btDevices': [
      {
        'name': 'Pixel 8',
        'address': 'AA:BB:CC:DD:EE:01',
        'profiles': ['a2dp', 'hfp'],
      },
    ],
    'wifiEnabled': true,
    'wifiConnected': false,
    'hotspotOn': true,
    'hotspotClients': 1,
  });

  Future<void> start() async {
    if (_started || !_bridge.isSupported) return;
    _started = true;
    _sub = _bridge.events.where((e) => e['type'] == 'connectivity').listen((e) {
      info = ConnectivityInfo.fromMap(e);
    }, onError: (_) {});
    await _bridge.startConnectivityWatch();
    await refresh();
    // Por si el radio no avisa los cambios.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(refresh()));
  }

  Future<ConnectivityInfo> refresh() async {
    if (!_bridge.isSupported) return _info;
    final m = await _bridge.getConnectivityStatus();
    if (m.isNotEmpty) info = ConnectivityInfo.fromMap(m);
    return _info;
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _sub?.cancel();
    if (_started) unawaited(_bridge.stopConnectivityWatch());
    super.dispose();
  }
}
