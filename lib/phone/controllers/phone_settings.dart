import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Animaciones del modo celular.
enum PhoneMotion {
  system('Sistema'),
  full('Completas'),
  reduced('Reducidas');

  const PhoneMotion(this.label);
  final String label;
}

/// Tema claro/oscuro del modo celular.
enum PhoneThemeMode {
  system('Sistema'),
  light('Claro'),
  dark('Oscuro');

  const PhoneThemeMode(this.label);
  final String label;
}

/// Ajustes de apariencia y comportamiento del celular (prefs `phone_*`, por equipo).
///
/// El celular no tiene portada propia ni acceso al color de Material You del sistema
/// desde Flutter, así que el color sale de una semilla fija + variante (como la opción
/// "Color fijo" de la tableta).
class PhoneSettings extends ChangeNotifier {
  static const kThemeMode = 'phone_theme_mode';
  static const kSeed = 'phone_seed_color';
  static const kVariant = 'phone_scheme_variant';
  static const kTextScale = 'phone_text_scale';
  static const kHaptics = 'phone_haptics';
  static const kMotion = 'phone_animations';

  /// Semillas sugeridas (las mismas muestras que "Color fijo" en la tableta).
  static const swatches = <(int, String)>[
    (0xFF3F6D8E, 'Azul acero'),
    (0xFF6750A4, 'Violeta'),
    (0xFFB3261E, 'Rojo'),
    (0xFFE8743B, 'Naranja'),
    (0xFFD4A017, 'Mostaza'),
    (0xFF386A20, 'Verde'),
    (0xFF006A6A, 'Turquesa'),
    (0xFF7D5260, 'Malva'),
    (0xFF0061A4, 'Azul'),
    (0xFFC2185B, 'Fucsia'),
    (0xFF00897B, 'Verde azulado'),
    (0xFF5D4037, 'Café'),
  ];

  static const variantLabels = {
    SchemeVariant.tonalSpot: 'Tonal',
    SchemeVariant.vibrant: 'Vibrante',
    SchemeVariant.expressive: 'Expresivo',
    SchemeVariant.fidelity: 'Fiel',
    SchemeVariant.neutral: 'Neutro',
    SchemeVariant.content: 'Contenido',
    SchemeVariant.monochrome: 'Monocromo',
  };

  /// Tamaños de texto (multiplican el del sistema).
  static const textScales = <(double, String)>[
    (0.9, 'Chico'),
    (1.0, 'Normal'),
    (1.15, 'Grande'),
    (1.3, 'Enorme'),
  ];

  PhoneThemeMode themeMode = PhoneThemeMode.system;
  Color seed = AppTheme.fallbackSeed;
  SchemeVariant variant = SchemeVariant.tonalSpot;
  double textScale = 1.0;
  bool haptics = true;
  PhoneMotion motion = PhoneMotion.system;
  bool loaded = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = PhoneThemeMode.values.firstWhere(
        (m) => m.name == p.getString(kThemeMode),
        orElse: () => PhoneThemeMode.system,
      );
      final s = p.getInt(kSeed);
      seed = s == null
          ? AppTheme.fallbackSeed
          : Color(0xFF000000 | (s & 0xFFFFFF));
      variant = SchemeVariant.values.firstWhere(
        (v) => v.name == p.getString(kVariant),
        orElse: () => SchemeVariant.tonalSpot,
      );
      textScale = (p.getDouble(kTextScale) ?? 1.0).clamp(0.8, 1.4);
      haptics = p.getBool(kHaptics) ?? true;
      motion = PhoneMotion.values.firstWhere(
        (m) => m.name == p.getString(kMotion),
        orElse: () => PhoneMotion.system,
      );
    } catch (_) {}
    HxHaptics.enabled = haptics;
    loaded = true;
    _notify();
  }

  Brightness brightness(Brightness platform) => switch (themeMode) {
    PhoneThemeMode.system => platform,
    PhoneThemeMode.light => Brightness.light,
    PhoneThemeMode.dark => Brightness.dark,
  };

  /// ¿Animaciones reducidas? [platform] = preferencia de accesibilidad del sistema.
  bool reduceMotion(bool platform) => switch (motion) {
    PhoneMotion.system => platform,
    PhoneMotion.full => false,
    PhoneMotion.reduced => true,
  };

  ColorScheme scheme(Brightness platform) => AppTheme.schemeFromSeed(
    seed,
    brightness: brightness(platform),
    variant: variant,
  );

  Future<void> _save(void Function(SharedPreferences p) f) async {
    _notify();
    try {
      f(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  Future<void> setThemeMode(PhoneThemeMode m) {
    themeMode = m;
    return _save((p) => p.setString(kThemeMode, m.name));
  }

  Future<void> setSeed(Color c) {
    seed = c;
    return _save((p) => p.setInt(kSeed, c.toARGB32()));
  }

  Future<void> setVariant(SchemeVariant v) {
    variant = v;
    return _save((p) => p.setString(kVariant, v.name));
  }

  Future<void> setTextScale(double v) {
    textScale = v;
    return _save((p) => p.setDouble(kTextScale, v));
  }

  Future<void> setHaptics(bool v) {
    haptics = v;
    HxHaptics.enabled = v;
    return _save((p) => p.setBool(kHaptics, v));
  }

  Future<void> setMotion(PhoneMotion m) {
    motion = m;
    return _save((p) => p.setString(kMotion, m.name));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    HxHaptics.enabled = false;
    super.dispose();
  }
}
