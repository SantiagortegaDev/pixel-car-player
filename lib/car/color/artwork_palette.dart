import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/theme/colors.dart';

/// Colores derivados de la carátula, ajustados para verse bien (y leerse)
/// sobre el azul marino Harmonix.
@immutable
class ArtworkPalette {
  const ArtworkPalette({
    required this.accent,
    required this.accentBright,
    required this.accentDim,
    required this.backdrop,
  });

  /// Acento vibrante (botón play, slider, glow).
  final Color accent;

  /// Variante clara (artista, línea activa de letras).
  final Color accentBright;

  /// Variante oscura (final del gradiente del botón play).
  final Color accentDim;

  /// Color oscuro dominante para teñir el fondo.
  final Color backdrop;

  static const harmonix = ArtworkPalette(
    accent: HarmonixColors.accent,
    accentBright: HarmonixColors.accentBright,
    accentDim: HarmonixColors.accentDim,
    backdrop: HarmonixColors.background,
  );

  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) => ArtworkPalette(
    accent: Color.lerp(a.accent, b.accent, t)!,
    accentBright: Color.lerp(a.accentBright, b.accentBright, t)!,
    accentDim: Color.lerp(a.accentDim, b.accentDim, t)!,
    backdrop: Color.lerp(a.backdrop, b.backdrop, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is ArtworkPalette &&
      other.accent == accent &&
      other.accentBright == accentBright &&
      other.accentDim == accentDim &&
      other.backdrop == backdrop;

  @override
  int get hashCode => Object.hash(accent, accentBright, accentDim, backdrop);
}

class ArtworkPaletteTween extends Tween<ArtworkPalette> {
  ArtworkPaletteTween({super.begin, super.end});
  @override
  ArtworkPalette lerp(double t) => ArtworkPalette.lerp(begin!, end!, t);
}

/// Extrae la paleta de una imagen codificada (PNG/JPEG). Funciona en móvil
/// y en web (decodifica con el motor de Flutter a 48 px y lee RGBA).
Future<ArtworkPalette> extractPalette(Uint8List encoded) async {
  try {
    final codec = await ui.instantiateImageCodec(encoded, targetWidth: 48, targetHeight: 48);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return ArtworkPalette.harmonix;
    return paletteFromRgba(data.buffer.asUint8List());
  } catch (e) {
    debugPrint('extractPalette: $e');
    return ArtworkPalette.harmonix;
  }
}

/// Algoritmo puro (testeable): histograma de tonos ponderado por saturación
/// para el acento "vibrante" + color medio cuantizado para el fondo.
ArtworkPalette paletteFromRgba(Uint8List rgba) {
  const buckets = 36; // 10° cada uno
  final weight = List<double>.filled(buckets, 0);
  final sumR = List<double>.filled(buckets, 0);
  final sumG = List<double>.filled(buckets, 0);
  final sumB = List<double>.filled(buckets, 0);
  final counts = <int, int>{};
  var total = 0;
  var totalWeight = 0.0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    total++;
    // Cuantización 4 bits/canal para el color dominante.
    final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    counts[key] = (counts[key] ?? 0) + 1;

    final mx = math.max(r, math.max(g, b)) / 255.0;
    final mn = math.min(r, math.min(g, b)) / 255.0;
    final v = mx;
    final s = mx == 0 ? 0.0 : (mx - mn) / mx;
    if (s < 0.25 || v < 0.22) continue;
    final h = HSVColor.fromColor(Color.fromARGB(255, r, g, b)).hue;
    final bi = (h / 360 * buckets).floor() % buckets;
    // Más saturado y más luminoso = más "vibrante".
    final w = s * s * (0.35 + v);
    weight[bi] += w;
    sumR[bi] += r * w;
    sumG[bi] += g * w;
    sumB[bi] += b * w;
    totalWeight += w;
  }
  if (total == 0) return ArtworkPalette.harmonix;

  // Backdrop: color cuantizado más frecuente, muy oscurecido y mezclado con navy.
  var bestKey = 0, bestCount = -1;
  counts.forEach((k, c) {
    if (c > bestCount) {
      bestCount = c;
      bestKey = k;
    }
  });
  final dom = Color.fromARGB(
    255,
    ((bestKey >> 8) & 0xF) * 17,
    ((bestKey >> 4) & 0xF) * 17,
    (bestKey & 0xF) * 17,
  );
  final domHsl = HSLColor.fromColor(dom);
  final backdropRaw = domHsl
      .withLightness(0.14)
      .withSaturation(math.min(domHsl.saturation, 0.7))
      .toColor();
  final backdrop = Color.lerp(HarmonixColors.background, backdropRaw, 0.65)!;

  // Imagen casi gris: conservar el acento Harmonix.
  if (totalWeight / total < 0.02) {
    return ArtworkPalette(
      accent: HarmonixColors.accent,
      accentBright: HarmonixColors.accentBright,
      accentDim: HarmonixColors.accentDim,
      backdrop: backdrop,
    );
  }

  // Suavizar con vecinos para no quedarnos con un pico aislado.
  var best = 0;
  var bestScore = -1.0;
  for (var i = 0; i < buckets; i++) {
    final score =
        weight[i] + 0.5 * weight[(i + 1) % buckets] + 0.5 * weight[(i - 1 + buckets) % buckets];
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  final w = weight[best];
  final vib = Color.fromARGB(
    255,
    (sumR[best] / w).round().clamp(0, 255),
    (sumG[best] / w).round().clamp(0, 255),
    (sumB[best] / w).round().clamp(0, 255),
  );
  final hsl = HSLColor.fromColor(vib);
  final sat = hsl.saturation.clamp(0.6, 0.95);
  // Amarillos/verdes se perciben más claros: bajar un poco su luminosidad.
  final hue = hsl.hue;
  final yellowish = hue > 40 && hue < 170;
  final base = HSLColor.fromAHSL(1, hue, sat, yellowish ? 0.56 : 0.64);
  return ArtworkPalette(
    accent: base.toColor(),
    accentBright: base.withLightness(yellowish ? 0.70 : 0.77).toColor(),
    accentDim: base.withLightness(yellowish ? 0.36 : 0.42).toColor(),
    backdrop: backdrop,
  );
}
