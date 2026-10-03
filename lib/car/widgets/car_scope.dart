import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/color/artwork_palette.dart';

/// Escala de la UI según el tamaño de la pantalla del carro. 1.0 ≈ 1280×720.
double carScaleFor(Size size) {
  final s = (size.width / 1280) < (size.height / 720) ? size.width / 1280 : size.height / 720;
  return s.clamp(0.74, 1.8);
}

/// Datos visuales compartidos por toda la pantalla del carro: escala y paleta
/// (ya animada) extraída de la carátula.
class CarScope extends InheritedWidget {
  const CarScope({super.key, required this.scale, required this.palette, required super.child});

  final double scale;
  final ArtworkPalette palette;

  static CarScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarScope>()!;

  @override
  bool updateShouldNotify(CarScope old) => old.scale != scale || old.palette != palette;
}

extension CarScopeX on BuildContext {
  double get s => CarScope.of(this).scale;
  ArtworkPalette get palette => CarScope.of(this).palette;
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
