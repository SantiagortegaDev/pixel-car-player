import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/theme/colors.dart';

/// Fondo Harmonix: carátula difuminada + tinte del color dominante sobre
/// azul marino, con un halo del color de acento. Hace crossfade al cambiar.
class CarBackground extends StatelessWidget {
  const CarBackground({super.key, required this.artwork, required this.artKey});

  final Uint8List? artwork;
  final Object artKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Color.lerp(HarmonixColors.backgroundDark, p.backdrop, 0.7)!),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: artwork == null
                ? const SizedBox.expand(key: ValueKey('no-art'))
                : _BlurredArt(key: ValueKey(artKey), bytes: artwork!),
          ),
          // Velo azul marino (legibilidad) con degradado lateral: el lado de
          // las letras queda más oscuro.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  p.backdrop.withValues(alpha: 0.55),
                  HarmonixColors.background.withValues(alpha: 0.78),
                  HarmonixColors.backgroundDark.withValues(alpha: 0.88),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          // Halo del acento detrás de la portada.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.62, -0.05),
                radius: 0.9,
                colors: [p.accent.withValues(alpha: 0.22), p.accent.withValues(alpha: 0.0)],
              ),
            ),
          ),
          // Viñeta inferior para el slider/controles.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
                stops: [0, 0.7, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurredArt extends StatelessWidget {
  const _BlurredArt({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.mirror),
        child: Opacity(
          opacity: 0.75,
          child: Transform.scale(
            scale: 1.25,
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              cacheWidth: 160,
            ),
          ),
        ),
      ),
    );
  }
}
