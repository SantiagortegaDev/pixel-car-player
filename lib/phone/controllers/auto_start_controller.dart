import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BondedDevice {
  const BondedDevice(this.name, this.address);
  final String name;
  final String address;
}

/// Estado en vivo (`getAutoStartStatus`).
class AutoStartStatus {
  const AutoStartStatus({
    this.btCarConnected = false,
    this.btDevice,
    this.wifiSsid,
    this.matches = false,
    this.transmitterRunning = false,
    this.reason = '',
    this.known = false,
    this.associated = false,
  });

  /// El Bluetooth del carro está asociado con CompanionDeviceManager.
  final bool associated;
  final bool btCarConnected;
  final String? btDevice;
  final String? wifiSsid;
  final bool matches;
  final bool transmitterRunning;
  final String reason;

  /// false = todavía no se consultó (o el nativo no respondió).
  final bool known;

  factory AutoStartStatus.fromMap(Map<String, dynamic> m) {
    String? s(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return AutoStartStatus(
      btCarConnected: m['btCarConnected'] == true,
      btDevice: s(m['btDevice']),
      wifiSsid: s(m['wifiSsid']),
      matches: m['matches'] == true,
      transmitterRunning: m['transmitterRunning'] == true,
      reason: s(m['reason']) ?? '',
      known: m.isNotEmpty,
      associated: m['associated'] == true,
    );
  }
}

/// Encendido/apagado automático del transmisor al subir/bajar del carro (batería).
///
/// Reglas `{enabled, btAddresses, wifiSsids, stopAfterMinutes}`: el nativo las usa
/// (CompanionDeviceManager / ACL Bluetooth / red Wi-Fi). Se guardan también en prefs
/// `phone_autostart_*` para la copia de seguridad y por si el nativo aún no responde.
class AutoStartController extends ChangeNotifier {
  AutoStartController(this._bridge, {required this.supported});

  final NativeBridge _bridge;
  final bool supported;

  static const kEnabled = 'phone_autostart_enabled';
  static const kBt = 'phone_autostart_bt';
  static const kWifi = 'phone_autostart_wifi';
  static const kStop = 'phone_autostart_stop_minutes';
  static const kAssociated = 'phone_autostart_associated';

  bool enabled = false;
  List<String> btAddresses = const [];
  List<String> wifiSsids = const [];
  int stopAfterMinutes = 5;

  /// Dirección asociada con CompanionDeviceManager (vacía = sin asociar).
  String associated = '';

  List<BondedDevice> bonded = const [];
  bool bondedLoaded = false;
  AutoStartStatus status = const AutoStartStatus();
  bool saving = false;
  bool associating = false;
  bool _disposed = false;

  Map<String, dynamic> get rules => {
    'enabled': enabled,
    'btAddresses': btAddresses,
    'wifiSsids': wifiSsids,
    'stopAfterMinutes': stopAfterMinutes,
  };

  Future<void> init() async {
    await loadPrefs();
    if (supported) {
      try {
        final r = await _bridge.getAutoStartRules();
        if (r.containsKey('enabled')) {
          enabled = r['enabled'] == true;
          btAddresses = _strings(r['btAddresses']);
          wifiSsids = _strings(r['wifiSsids']);
          stopAfterMinutes =
              ((r['stopAfterMinutes'] as num?)?.toInt() ?? stopAfterMinutes)
                  .clamp(0, 30);
          await _savePrefs();
        } else if (enabled) {
          // El nativo no tiene reglas (reinstalación / restauración): re-aplicar.
          await apply();
        }
      } catch (_) {}
    }
    _notify();
  }

  Future<void> loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool(kEnabled) ?? false;
      btAddresses = p.getStringList(kBt) ?? const [];
      wifiSsids = p.getStringList(kWifi) ?? const [];
      stopAfterMinutes = (p.getInt(kStop) ?? 5).clamp(0, 30);
      associated = p.getString(kAssociated) ?? '';
    } catch (_) {}
  }

  static List<String> _strings(Object? v) => v is List
      ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet().toList()
      : const [];

  Future<void> loadBonded() async {
    if (!supported) {
      bonded = const [
        BondedDevice('Radio del carro', '00:1A:7D:DA:71:13'),
        BondedDevice('Pixel Buds Pro', 'F4:7D:EF:20:6C:31'),
        BondedDevice('Tableta K24', 'A0:C9:A0:12:9E:4B'),
      ];
    } else {
      try {
        bonded = (await _bridge.getBondedDevices())
            .map(
              (m) => BondedDevice(
                '${m['name'] ?? ''}'.trim().isEmpty
                    ? 'Sin nombre'
                    : '${m['name']}',
                '${m['address'] ?? ''}',
              ),
            )
            .where((d) => d.address.isNotEmpty)
            .toList();
      } catch (_) {
        bonded = const [];
      }
    }
    bondedLoaded = true;
    _notify();
  }

  Future<void> refreshStatus({bool transmitterRunning = false}) async {
    if (_disposed) return;
    if (!supported) {
      status = AutoStartStatus(
        btCarConnected: true,
        btDevice: 'Radio del carro',
        wifiSsid: wifiSsids.isNotEmpty ? wifiSsids.first : 'Tableta K24',
        matches: true,
        transmitterRunning: transmitterRunning,
        reason: enabled
            ? 'Conectado al Bluetooth del carro: transmisor encendido'
            : 'Encendido automático desactivado',
        known: true,
      );
      _notify();
      return;
    }
    try {
      status = AutoStartStatus.fromMap(await _bridge.getAutoStartStatus());
    } catch (_) {}
    _notify();
  }

  /// Activa/desactiva. [suggestSsid] (el hotspot guardado del carro) se agrega si aún no
  /// hay redes elegidas.
  Future<void> setEnabled(bool v, {String? suggestSsid}) async {
    enabled = v;
    if (v && wifiSsids.isEmpty && (suggestSsid ?? '').trim().isNotEmpty) {
      wifiSsids = [suggestSsid!.trim()];
    }
    await apply();
  }

  Future<void> toggleBt(String address, bool on) async {
    final s = {...btAddresses};
    on ? s.add(address) : s.remove(address);
    btAddresses = s.toList();
    await apply();
  }

  Future<bool> addWifi(String ssid) async {
    ssid = ssid.trim();
    if (ssid.isEmpty || wifiSsids.contains(ssid)) return false;
    wifiSsids = [...wifiSsids, ssid];
    await apply();
    return true;
  }

  Future<void> removeWifi(String ssid) async {
    wifiSsids = wifiSsids.where((s) => s != ssid).toList();
    await apply();
  }

  /// Mientras se arrastra el slider (sin guardar).
  void previewStop(int minutes) {
    stopAfterMinutes = minutes.clamp(0, 30);
    _notify();
  }

  Future<void> setStopAfter(int minutes) async {
    stopAfterMinutes = minutes.clamp(0, 30);
    await apply();
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kEnabled, enabled);
      await p.setStringList(kBt, btAddresses);
      await p.setStringList(kWifi, wifiSsids);
      await p.setInt(kStop, stopAfterMinutes);
    } catch (_) {}
  }

  /// Guarda en prefs y en el nativo (`setAutoStartRules`).
  Future<bool> apply() async {
    saving = true;
    _notify();
    var ok = true;
    await _savePrefs();
    if (supported) {
      try {
        ok = await _bridge.setAutoStartRules(rules);
      } catch (_) {
        ok = false;
      }
    }
    saving = false;
    _notify();
    return ok;
  }

  /// Asocia el Bluetooth del carro (diálogo del sistema). Devuelve el mensaje a mostrar.
  Future<({bool ok, String message})> associate() async {
    if (associating) return (ok: false, message: '');
    associating = true;
    _notify();
    try {
      final address = btAddresses.isNotEmpty ? btAddresses.first : null;
      if (!supported) {
        associated = address ?? '00:1A:7D:DA:71:13';
        await _saveAssociated();
        return (
          ok: true,
          message:
              'Vinculado (demo): en el celular se abre el diálogo de Android.',
        );
      }
      final r = await _bridge.associateCarDevice(address: address);
      if (r['ok'] == true) {
        associated = '${r['address'] ?? address ?? ''}';
        await _saveAssociated();
        final name = '${r['name'] ?? ''}'.trim();
        // Si el usuario eligió en el diálogo un equipo que no estaba marcado, se suma.
        if (associated.isNotEmpty && !btAddresses.contains(associated)) {
          btAddresses = [...btAddresses, associated];
          await apply();
        }
        return (
          ok: true,
          message: name.isEmpty ? 'Carro vinculado.' : 'Vinculado con «$name».',
        );
      }
      final e = '${r['error'] ?? ''}'.trim();
      return (
        ok: false,
        message: e.isEmpty
            ? 'No se pudo vincular con el carro.'
            : 'No se pudo vincular: $e',
      );
    } catch (e) {
      return (ok: false, message: 'No se pudo vincular: $e');
    } finally {
      associating = false;
      _notify();
    }
  }

  Future<void> _saveAssociated() async {
    try {
      (await SharedPreferences.getInstance()).setString(
        kAssociated,
        associated,
      );
    } catch (_) {}
  }

  String nameFor(String address) =>
      bonded.where((d) => d.address == address).firstOrNull?.name ?? address;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
