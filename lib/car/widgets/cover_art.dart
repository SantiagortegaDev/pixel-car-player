import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Portada Material You: esquinas 28, elevación M3 y crossfade + leve zoom al
/// cambiar de canción. Al pausar se encoge un poco (como Android).
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.artwork,
    required this.artKey,
    required this.size,
    this.radius = 28,
    this.elevation = 6,
    this.playing = true,
    this.heroTag,
  });

  final Uint8List? artwork;
  final Object artKey;
  final double size;
  final double radius;
  final double elevation;
  final bool playing;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(radius);
    Widget card = Material(
      color: cs.surfaceContainerHighest,
      elevation: elevation,
      shadowColor: cs.shadow,
      borderRadius: r,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size,
        height: size,
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
    );
    if (heroTag != null) card = Hero(tag: heroTag!, child: card);
    return AnimatedScale(
      scale: playing ? 1.0 : 0.94,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: card,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.primaryContainer,
      child: Center(
        child: Icon(Icons.music_note_rounded, color: cs.onPrimaryContainer, size: size * 0.4),
      ),
    );
  }
}
