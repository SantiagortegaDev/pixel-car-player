import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de conexión y pantalla de la tableta.
class CarPrefs {
  CarPrefs({this.manualIp, this.btAddress, this.btName, this.keepScreenOn = true, this.demo = false});

  /// IP manual del celular (vacía = no se usa).
  String? manualIp;

  /// Dirección MAC del celular emparejado para RFCOMM. `null` = solo Wi-Fi.
  String? btAddress;
  String? btName;

  bool keepScreenOn;
  bool demo;

  static const _kIp = 'car_manual_ip';
  static const _kBt = 'car_bt_address';
  static const _kBtName = 'car_bt_name';
  static const _kScreen = 'car_keep_screen_on';
  static const kDemo = 'demo_mode'; // compartido con AppConfig

  /// Inicio automático (los lee el BootReceiver nativo; ver CONTRACT.md §2).
  /// Los escribe `CarCustomizationStore` junto con el resto de la personalización.
  static const kAutostart = 'car_autostart';
  static const kAutostartDelay = 'car_autostart_delay';

  /// App acompañante que el BootReceiver abre detrás (vacío = ninguna) y su espera (ms).
  static const kCompanionPackage = 'car_companion_package';
  static const kCompanionDelay = 'car_companion_delay';

  static Future<CarPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return CarPrefs(
        manualIp: p.getString(_kIp),
        btAddress: p.getString(_kBt),
        btName: p.getString(_kBtName),
        keepScreenOn: p.getBool(_kScreen) ?? true,
        demo: p.getBool(kDemo) ?? false,
      );
    } catch (_) {
      return CarPrefs();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      Future<void> setOrRemove(String k, String? v) async => (v == null || v.isEmpty) ? p.remove(k) : p.setString(k, v);
      await setOrRemove(_kIp, manualIp?.trim());
      await setOrRemove(_kBt, btAddress);
      await setOrRemove(_kBtName, btName);
      await p.setBool(_kScreen, keepScreenOn);
      await p.setBool(kDemo, demo);
    } catch (_) {}
  }
}

/// Identificador estable de esta instalación (va en `hello` y en `car_beacon`, v2).
class LinkIdentity {
  LinkIdentity._();

  static const key = 'car_install_id';
  static String? _cached;

  /// 16 caracteres hex aleatorios.
  static String generate([math.Random? rnd]) {
    final r = rnd ?? math.Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Lee el id guardado o crea uno nuevo (si no se puede guardar, dura lo que la app).
  static Future<String> load() async {
    final c = _cached;
    if (c != null) return c;
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString(key);
      if (id == null || id.length < 8) {
        id = generate();
        await p.setString(key, id);
      }
      return _cached = id;
    } catch (_) {
      return _cached = generate();
    }
  }
}
