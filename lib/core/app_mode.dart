import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rol de este dispositivo. Se elige al primer arranque y se guarda.
enum AppMode { car, phone }

class AppConfig {
  AppConfig({this.mode, this.demo = false});

  AppMode? mode;

  /// Modo demo: datos simulados (para web/capturas o probar la tableta sin celular).
  bool demo;

  static const _kMode = 'app_mode';

  static Future<AppConfig> load() async {
    // En web se puede forzar con ?mode=car|phone&demo=1
    if (kIsWeb) {
      final q = Uri.base.queryParameters;
      final m = switch (q['mode']) {
        'car' => AppMode.car,
        'phone' => AppMode.phone,
        _ => null,
      };
      return AppConfig(mode: m, demo: q['demo'] != '0');
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMode);
    return AppConfig(
      mode: AppMode.values.where((m) => m.name == raw).firstOrNull,
      demo: prefs.getBool('demo_mode') ?? false,
    );
  }

  static Future<void> saveMode(AppMode? mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == null) {
      await prefs.remove(_kMode);
    } else {
      await prefs.setString(_kMode, mode.name);
    }
  }
}
