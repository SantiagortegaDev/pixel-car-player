import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/theme/colors.dart';

/// Portada estilo Harmonix: esquinas 28, sombra/glow del color de acento y
/// crossfade + leve zoom al cambiar de canción.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.artwork,
    required this.artKey,
    required this.size,
    this.radius = 28,
    this.glow = true,
    this.playing = true,
  });

  final Uint8List? artwork;
  final Object artKey;
  final double size;
  final double radius;
  final bool glow;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(radius);
    return AnimatedScale(
      // Al pausar, la portada "respira" hacia atrás como en reproductores premium.
      scale: playing ? 1.0 : 0.94,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: p.accent.withValues(alpha: playing ? 0.42 : 0.22),
                    blurRadius: size * 0.12,
                    spreadRadius: size * 0.005,
                    offset: Offset(0, size * 0.045),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: size * 0.05,
                    offset: Offset(0, size * 0.02),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 650),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 1.06, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: artwork == null
                ? _Placeholder(key: ValueKey('ph-$artKey'), size: size)
                : Image.memory(
                    artwork!,
                    key: ValueKey(artKey),
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HarmonixColors.surfaceContainerHigh, HarmonixColors.surface],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded, color: p.accent, size: size * 0.36),
      ),
    );
  }
}
