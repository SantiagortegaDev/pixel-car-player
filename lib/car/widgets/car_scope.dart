import 'package:flutter/material.dart';

/// Escala de la UI según el tamaño de la pantalla del carro. 1.0 ≈ 1280×720.
double carScaleFor(Size size) {
  final s = (size.width / 1280) < (size.height / 720) ? size.width / 1280 : size.height / 720;
  return s.clamp(0.74, 1.8);
}

/// Escala compartida por toda la pantalla del carro. Los colores NO viven
/// aquí: salen siempre de `Theme.of(context).colorScheme` (Material You
/// generado desde la carátula).
class CarScope extends InheritedWidget {
  const CarScope({super.key, required this.scale, required super.child});

  final double scale;

  static CarScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarScope>()!;

  @override
  bool updateShouldNotify(CarScope old) => old.scale != scale;
}

extension CarScopeX on BuildContext {
  double get s => CarScope.of(this).scale;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

extension ScaledTextStyle on TextStyle? {
  /// Estilo M3 del tema escalado para la pantalla del carro.
  TextStyle scaled(double k, {Color? color, FontWeight? weight, double? height}) {
    final base = this ?? const TextStyle(fontSize: 14);
    return base.copyWith(
      fontSize: (base.fontSize ?? 14) * k,
      color: color,
      fontWeight: weight,
      height: height,
    );
  }
}

/// Tamaño táctil mínimo para usar manejando.
const double kCarMinTouch = 64;

String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Nombre legible de la app de música.
String? sourceAppName(String? pkg) => switch (pkg) {
  null || '' => null,
  'com.spotify.music' => 'Spotify',
  'com.google.android.apps.youtube.music' => 'YouTube Music',
  'com.apple.android.music' => 'Apple Music',
  'deezer.android.app' => 'Deezer',
  'com.amazon.mp3' => 'Amazon Music',
  'com.soundcloud.android' => 'SoundCloud',
  'com.aspiro.tidal' => 'TIDAL',
  _ => pkg.split('.').last,
};
