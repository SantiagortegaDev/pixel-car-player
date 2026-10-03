import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Indicador de carga de MD3 Expressive (`LoadingIndicator.svelte`): una forma que se
/// transforma (softBurst → cookie9 → pentágono → píldora → sunny → cookie4 → óvalo)
/// mientras gira; 4,55 s por ciclo.
class HxLoadingIndicator extends StatefulWidget {
  const HxLoadingIndicator({super.key, this.size = 48, this.color, this.label = 'Cargando'});
  final double size;
  final Color? color;
  final String label;

  @override
  State<HxLoadingIndicator> createState() => _HxLoadingIndicatorState();
}

class _HxLoadingIndicatorState extends State<HxLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4550))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: Center(
          child: SizedBox.square(
            dimension: widget.size * 0.76,
            child: CustomPaint(painter: _MorphPainter(_c, color)),
          ),
        ),
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.anim, this.color) : super(repaint: anim);
  final Animation<double> anim;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final seq = M3Shape.loadingSequence;
    final n = seq.length;
    final f = anim.value * n;
    final i = f.floor() % n;
    // Cada tramo del keyframe usa la curva `--spring` (como animation-timing-function).
    final t = HxMotion.spring.transform(f - f.floor());
    final shape = M3Shape.lerp(seq[i], seq[(i + 1) % n], t);
    canvas.drawPath(shape.toPath(Offset.zero & size, rotation: anim.value * 2 * math.pi), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.color != color;
}
