import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de conexión y pantalla de la tableta.
class CarPrefs {
  CarPrefs({
    this.manualIp,
    this.btAddress,
    this.btName,
    this.keepScreenOn = true,
    this.demo = false,
  });

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
      Future<void> setOrRemove(String k, String? v) async =>
          (v == null || v.isEmpty) ? p.remove(k) : p.setString(k, v);
      await setOrRemove(_kIp, manualIp?.trim());
      await setOrRemove(_kBt, btAddress);
      await setOrRemove(_kBtName, btName);
      await p.setBool(_kScreen, keepScreenOn);
      await p.setBool(kDemo, demo);
    } catch (_) {}
  }
}
