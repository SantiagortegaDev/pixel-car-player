import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Animación de inicio: una forma MD3 aparece, cambia de círculo → galleta de 9 lados
/// mientras gira, muestra el nombre y luego crece hasta cubrir la pantalla y se desvanece
/// dejando ver el reproductor. Sin rebotes (curvas enfatizadas). No recibe toques.
class CarSplash extends StatefulWidget {
  const CarSplash({super.key, required this.duration, required this.onDone, this.holdAt});
  final Duration duration;
  final VoidCallback onDone;

  /// Congela la animación en ese punto 0..1 (capturas: `?splashAt=0.4`).
  final double? holdAt;

  @override
  State<CarSplash> createState() => _CarSplashState();
}

class _CarSplashState extends State<CarSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    final hold = widget.holdAt;
    if (hold != null) {
      _c.value = hold.clamp(0.0, 1.0);
    } else {
      _c.forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _seg(double t, double a, double b, [Curve c = HxMotion.emphasizedDecel]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final grow = _seg(t, 0, 0.45);
          final morph = _seg(t, 0.1, 0.6, HxMotion.standard);
          final text = _seg(t, 0.25, 0.5);
          final out = _seg(t, 0.62, 1, HxMotion.emphasizedAccel);
          return LayoutBuilder(
            builder: (context, c) {
              final base = math.min(c.maxWidth, c.maxHeight) * 0.26;
              final cover = math.sqrt(c.maxWidth * c.maxWidth + c.maxHeight * c.maxHeight) / base * 1.2;
              final scale = grow * (1 + out * cover);
              final shape = M3Shape.lerp(M3Shape.circle, M3Shape.cookie9, morph);
              return Opacity(
                opacity: 1 - _seg(t, 0.75, 1, Curves.linear),
                child: ColoredBox(
                  color: cs.surface,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: scale,
                        child: Transform.rotate(
                          angle: (1 - morph) * -math.pi / 3 + out * math.pi / 6,
                          child: SizedBox.square(
                            dimension: base,
                            child: ClipPath(
                              clipper: M3ShapeClipper(shape),
                              child: ColoredBox(color: cs.primaryContainer),
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: (grow * (1 - out * 3)).clamp(0.0, 1.0),
                        child: HxIcon(
                          Symbols.directions_car_rounded,
                          size: base * 0.38,
                          fill: true,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: c.maxHeight / 2 + base * 0.62 + 12,
                        child: Opacity(
                          opacity: (text * (1 - out * 3)).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - text)),
                            child: Text(
                              'Pixel Car Player',
                              textAlign: TextAlign.center,
                              style: hxWeight(tt.headlineMedium, 500).copyWith(color: cs.onSurface, letterSpacing: -0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
