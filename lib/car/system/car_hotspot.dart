import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';

/// Lo que se sabe del hotspot de la tableta (`getHotspotState` / `setHotspotEnabled`).
@immutable
class HotspotInfo {
  const HotspotInfo({
    this.enabled,
    this.ssid,
    this.password,
    this.method = 'unknown',
    this.canWriteSettings = false,
    this.loaded = false,
    this.configuredSsid,
    this.configuredPassword,
  });

  static const unknown = HotspotInfo();

  /// `null` = no se pudo leer.
  final bool? enabled;
  final String? ssid;
  final String? password;

  /// `localOnly` | `tethering` | `wifiAp` | `system` (encendido por otro) | `none` | `unknown`.
  final String method;

  /// Permiso "Modificar ajustes del sistema" (algunos radios lo piden para encenderlo).
  final bool canWriteSettings;

  /// Ya se consultó al menos una vez.
  final bool loaded;

  /// La red configurada en los ajustes del radio (puede faltar: Android 11+ suele ocultarla).
  final String? configuredSsid;
  final String? configuredPassword;

  /// Nombre y clave a usar/mostrar: los de la red configurada en el radio si se conocen.
  String? get networkSsid => configuredSsid ?? ssid;
  String? get networkPassword => configuredSsid != null ? configuredPassword : password;

  factory HotspotInfo.fromMap(Map<String, dynamic> m, {HotspotInfo? previous}) {
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    final p = previous ?? unknown;
    return HotspotInfo(
      enabled: m['enabled'] is bool ? m['enabled'] as bool : null,
      ssid: str(m['ssid']) ?? p.ssid,
      password: str(m['password']) ?? p.password,
      method: str(m['method']) ?? p.method,
      canWriteSettings: m['canWriteSettings'] is bool ? m['canWriteSettings'] as bool : p.canWriteSettings,
      loaded: true,
      configuredSsid: str(m['configuredSsid']) ?? p.configuredSsid,
      configuredPassword: str(m['configuredPassword']) ?? p.configuredPassword,
    );
  }

  HotspotInfo copyWith({bool? enabled, bool clearEnabled = false, String? method}) => HotspotInfo(
    enabled: clearEnabled ? null : (enabled ?? this.enabled),
    ssid: ssid,
    password: password,
    method: method ?? this.method,
    canWriteSettings: canWriteSettings,
    loaded: loaded,
    configuredSsid: configuredSsid,
    configuredPassword: configuredPassword,
  );

  @override
  bool operator ==(Object other) =>
      other is HotspotInfo &&
      other.enabled == enabled &&
      other.ssid == ssid &&
      other.password == password &&
      other.method == method &&
      other.canWriteSettings == canWriteSettings &&
      other.loaded == loaded &&
      other.configuredSsid == configuredSsid &&
      other.configuredPassword == configuredPassword;

  @override
  int get hashCode =>
      Object.hash(enabled, ssid, password, method, canWriteSettings, loaded, configuredSsid, configuredPassword);
}

/// Aviso para la pantalla: no se pudo encender solo, hay que ir a los ajustes.
@immutable
class HotspotPrompt {
  const HotspotPrompt({required this.canWriteSettings, this.error});
  final bool canWriteSettings;

  /// Código de error nativo (`locationOff`, `permissionDenied`…), si vino.
  final String? error;
}

/// Explicación corta de un código de error de `setHotspotEnabled` (CONTRACT.md §2).
String? hotspotErrorText(Object? code) => switch (code) {
  'locationOff' => 'Android pide tener la ubicación activada para crear el hotspot.',
  'permissionDenied' => 'Falta un permiso (ubicación o dispositivos Wi-Fi cercanos).',
  'tetheringDisallowed' => 'Este radio no permite compartir la conexión desde otras apps.',
  'incompatibleMode' => 'El Wi-Fi está en un modo que no permite el hotspot (desconéctalo de otra red).',
  'noChannel' => 'No hay un canal Wi-Fi libre para el hotspot.',
  'timeout' => 'El radio tardó demasiado en encenderlo.',
  'systemPathsFailed' || 'unsupported' => 'Este radio no deja encenderlo desde otras apps.',
  _ => null,
};

/// Acceso al sistema (inyectable en pruebas).
abstract class HotspotApi {
  bool get supported;
  Future<Map<String, dynamic>> getState();
  /// [allowLocalOnly]: si el radio no deja encender su hotspot, crear uno temporal
  /// (LocalOnlyHotspot, SSID/clave aleatorios).
  Future<Map<String, dynamic>> setEnabled(bool enabled, {bool allowLocalOnly = false});
}

class _BridgeHotspotApi implements HotspotApi {
  _BridgeHotspotApi(this.b);
  final NativeBridge b;
  @override
  bool get supported => b.isSupported;
  @override
  Future<Map<String, dynamic>> getState() => b.getHotspotState();
  @override
  Future<Map<String, dynamic>> setEnabled(bool enabled, {bool allowLocalOnly = false}) =>
      b.setHotspotEnabled(enabled, allowLocalOnly: allowLocalOnly);
}

/// Hotspot del carro: consulta el estado, lo enciende/apaga y, si está activado
/// "Verificar y encender al iniciar", lo revisa al arrancar (y cada N minutos).
class CarHotspot extends ChangeNotifier {
  CarHotspot({NativeBridge? bridge, HotspotApi? api})
    : _api = api ?? _BridgeHotspotApi(bridge ?? NativeBridge.instance);

  final HotspotApi _api;
  HotspotInfo _info = HotspotInfo.unknown;
  bool _busy = false;
  bool _disposed = false;
  Timer? _timer;

  /// Si no se pudo encender solo, la pantalla muestra un diálogo y lo vuelve a `null`.
  final ValueNotifier<HotspotPrompt?> prompt = ValueNotifier(null);

  HotspotInfo get info => _info;
  bool get busy => _busy;
  bool get supported => _api.supported;

  void _set(HotspotInfo v) {
    if (_disposed || v == _info) return;
    _info = v;
    notifyListeners();
  }

  void _setBusy(bool v) {
    if (_disposed || v == _busy) return;
    _busy = v;
    notifyListeners();
  }

  Future<HotspotInfo> refresh() async {
    final m = await _api.getState();
    _set(HotspotInfo.fromMap(m, previous: _info));
    return _info;
  }

  /// Permitir el hotspot temporal (Configuración → Hotspot → avanzado). Apagado = solo se
  /// enciende la red configurada en el radio.
  bool allowTemporary = false;

  /// Enciende/apaga. Devuelve la respuesta nativa (`ok`, `method`, `needsSettings`…).
  Future<Map<String, dynamic>> setEnabled(bool on) async {
    _setBusy(true);
    try {
      final r = await _api.setEnabled(on, allowLocalOnly: on && allowTemporary);
      if (r['ok'] == true) {
        _set(
          HotspotInfo.fromMap({
            'enabled': on,
            'ssid': r['ssid'],
            'password': r['password'],
            'method': r['method'],
          }, previous: _info),
        );
      }
      // Lo confirma el sistema (algunos métodos tardan unos segundos).
      await refresh();
      return r;
    } finally {
      _setBusy(false);
    }
  }

  /// "Verificar y encender": solo si el sistema dice que está **apagado** intenta
  /// encenderlo (la red configurada en el radio; nunca lo apaga ni lo reinicia si ya está
  /// encendido, ni lo toca si no se puede leer el estado). Si no se puede, publica un
  /// [prompt]. Devuelve si quedó encendido.
  Future<bool> ensureOn() async {
    if (!_api.supported) return false;
    final st = await refresh();
    if (st.enabled == true) return true;
    if (st.enabled == null) return false;
    final r = await setEnabled(true);
    final ok = r['ok'] == true && r['needsSettings'] != true;
    if (!ok && !_disposed) {
      final err = r['error'];
      prompt.value = HotspotPrompt(canWriteSettings: _info.canWriteSettings, error: err is String ? err : null);
    }
    return ok;
  }

  /// Revisa cada [minutes] (0 = no).
  void schedule(int minutes) {
    _timer?.cancel();
    _timer = null;
    if (minutes <= 0 || _disposed) return;
    _timer = Timer.periodic(Duration(minutes: minutes), (_) => unawaited(ensureOn()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    prompt.dispose();
    super.dispose();
  }
}
