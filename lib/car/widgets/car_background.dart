import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Fondo Material You: `surface` con un lavado muy sutil de la carátula
/// difuminada (teñido por `surface`), como el reproductor de Android.
/// Hace crossfade al cambiar de canción.
class CarBackground extends StatelessWidget {
  const CarBackground({super.key, required this.artwork, required this.artKey});

  final Uint8List? artwork;
  final Object artKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cs.surface),
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
          // Velo de `surface`: el lavado solo se insinúa detrás de la portada.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  cs.surface.withValues(alpha: 0.72),
                  cs.surface.withValues(alpha: 0.9),
                  cs.surface.withValues(alpha: 0.96),
                ],
                stops: const [0, 0.5, 1],
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
        imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80, tileMode: TileMode.mirror),
        child: Transform.scale(
          scale: 1.3,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            cacheWidth: 128,
          ),
        ),
      ),
    );
  }
}
