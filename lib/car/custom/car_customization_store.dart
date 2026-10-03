import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda y publica la [CarCustomization]. Cada cambio se aplica al instante (los
/// widgets escuchan este notifier) y se guarda en SharedPreferences poco después:
///  - `car_customization`: todo el modelo en JSON.
///  - `car_autostart` (bool) y `car_autostart_delay` (int, s): aparte, porque los lee
///    el BootReceiver nativo.
///  - `car_companion_package` (String, vacío = apagado) y `car_companion_delay` (int, ms):
///    la app acompañante, también para el BootReceiver.
class CarCustomizationStore extends ChangeNotifier {
  CarCustomizationStore([CarCustomization initial = CarCustomization.defaults, this.persist = false])
    : _value = initial;

  static const key = 'car_customization';

  /// Si es `false` solo vive en memoria (pruebas, `?custom=` en web).
  final bool persist;
  CarCustomization _value;
  Timer? _saveTimer;

  static Set<String> get shapeNames => M3Shape.all.keys.toSet();

  CarCustomization get value => _value;

  /// Carga lo guardado (o los valores por defecto si no hay nada / falla).
  static Future<CarCustomizationStore> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      var v = CarCustomization.defaults;
      final raw = p.getString(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          v = CarCustomization.decode(raw, shapes: shapeNames);
        } catch (e) {
          debugPrint('CarCustomizationStore: JSON inválido, se usan los valores por defecto ($e)');
        }
      }
      // Las claves del inicio automático mandan (las puede tocar otra versión de la app).
      final auto = p.getBool(CarPrefs.kAutostart);
      final delay = p.getInt(CarPrefs.kAutostartDelay);
      final companion = p.getString(CarPrefs.kCompanionPackage);
      final companionDelay = p.getInt(CarPrefs.kCompanionDelay);
      v = v.copyWith(
        startup: v.startup.copyWith(
          autostart: auto,
          autostartDelay: delay == null ? null : CarStartupOpts.delayRange.clamp(delay.toDouble()).round(),
          // Vacío = apagado (se conserva la app elegida); un paquete = encendido con esa app.
          companionEnabled: companion?.isNotEmpty,
          companionPackage: companion == null || companion.isEmpty ? null : companion,
          companionDelayMs: companionDelay == null
              ? null
              : CarStartupOpts.companionDelayRange.clamp(companionDelay.toDouble()).round(),
        ),
      );
      return CarCustomizationStore(v, true);
    } catch (_) {
      return CarCustomizationStore();
    }
  }

  void set(CarCustomization v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
    _scheduleSave();
  }

  void update(CarCustomization Function(CarCustomization c) f) => set(f(_value));

  void resetAll() => set(CarCustomization.defaults);

  void resetSections(Iterable<CarSection> sections) {
    var v = _value;
    for (final s in sections) {
      v = v.resetSection(s);
    }
    set(v);
  }

  /// JSON legible para copiar.
  String export() => _value.encode();

  /// Aplica un JSON exportado. Lanza [FormatException] si no se puede leer.
  void import(String text) => set(CarCustomization.decode(text, shapes: shapeNames));

  void _scheduleSave() {
    if (!persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(flush()));
  }

  /// Guarda ya (sin esperar el debounce).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!persist) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(_value.toJson()));
      await p.setBool(CarPrefs.kAutostart, _value.startup.autostart);
      await p.setInt(CarPrefs.kAutostartDelay, _value.startup.autostartDelay);
      await p.setString(CarPrefs.kCompanionPackage, _value.startup.companionToLaunch);
      await p.setInt(CarPrefs.kCompanionDelay, _value.startup.companionDelayMs);
    } catch (e) {
      debugPrint('CarCustomizationStore: no se pudo guardar ($e)');
    }
  }

  @override
  void dispose() {
    if (_saveTimer != null) unawaited(flush());
    super.dispose();
  }
}
