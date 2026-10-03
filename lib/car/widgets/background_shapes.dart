import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';

/// BackgroundShapes de Caelestia / Harmonix v2: 14 formas MD3 que flotan y giran
/// despacio detrás del reproductor (solo mientras suena), en colores de contenedor con
/// opacidad baja. Al salir por un borde entran por el otro.
class BackgroundShapes extends StatefulWidget {
  const BackgroundShapes({
    super.key,
    required this.playing,
    this.count = 14,
    this.minSize = 56,
    this.maxSize = 220,
    this.seed,
    this.opacity = 1,
    this.animate = true,
  });

  final bool playing;
  final int count;
  final double minSize;
  final double maxSize;
  final int? seed;

  /// Multiplicador de la opacidad de Harmonix (1 = de fábrica).
  final double opacity;

  /// `false` = quietas aunque suene la música.
  final bool animate;

  static const pool = [
    'circle',
    'cookie4',
    'cookie6',
    'cookie7',
    'cookie9',
    'cookie12',
    'sunny',
    'verySunny',
    'softBurst',
    'pentagon',
    'gem',
    'pill',
    'triangle',
    'clover4',
    'oval',
  ];
  static const darkOpacity = [0.16, 0.16, 0.04, 0.16];
  static const lightOpacity = [0.34, 0.34, 0.08, 0.2];

  @override
  State<BackgroundShapes> createState() => _BackgroundShapesState();
}

class _Shape {
  _Shape({
    required this.size,
    required this.shape,
    required this.colour,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.vr,
    required this.r,
  });
  final double size;
  final M3Shape shape;
  final int colour;
  double x, y, r;
  final double vx, vy, vr;
}

class _BackgroundShapesState extends State<BackgroundShapes> with SingleTickerProviderStateMixin {
  late final math.Random _rnd = math.Random(widget.seed);
  late List<_Shape> _shapes = _make();
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  Size _box = Size.zero;

  double _rand(double a, double b) => a + _rnd.nextDouble() * (b - a);
  double _signed(double a, double b) => _rand(a, b) * (_rnd.nextBool() ? -1 : 1);

  List<_Shape> _make() => List.generate(widget.count, (i) {
    // Tamaños repartidos entre min y max como en Harmonix (con 14 formas).
    final colour = _rnd.nextInt(4);
    return _Shape(
      size: widget.minSize + i / widget.count * (widget.maxSize - widget.minSize),
      shape: M3Shape.all[BackgroundShapes.pool[_rnd.nextInt(BackgroundShapes.pool.length)]]!,
      colour: colour,
      x: _rnd.nextDouble(),
      y: _rnd.nextDouble(),
      vx: _signed(4, 18),
      vy: _signed(4, 18),
      vr: _rand(-12, 12),
      r: _rand(0, 360),
    );
  });

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BackgroundShapes old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count || old.minSize != widget.minSize || old.maxSize != widget.maxSize) {
      _shapes = _make();
      _repaint.value++;
    }
    _sync();
  }

  void _sync() {
    final run = widget.playing && widget.animate && widget.count > 0 && !_reducedMotion;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  bool get _reducedMotion => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.1, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final w = _box.width, h = _box.height;
    for (final s in _shapes) {
      // Velocidad en px/s convertida a fracción; al salir por un borde entra por el otro.
      final sw = math.max(1.0, w - s.size), sh = math.max(1.0, h - s.size);
      s.x += s.vx * dt / sw;
      s.y += s.vy * dt / sh;
      s.r += s.vr * dt;
      final mx = s.size / sw, my = s.size / sh;
      if (s.x < -mx) {
        s.x = 1 + mx;
      } else if (s.x > 1 + mx) {
        s.x = -mx;
      }
      if (s.y < -my) {
        s.y = 1 + my;
      } else if (s.y > 1 + my) {
        s.y = -my;
      }
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final colors = [cs.primaryContainer, cs.secondaryContainer, cs.tertiaryContainer, cs.outlineVariant];
    final op = dark ? BackgroundShapes.darkOpacity : BackgroundShapes.lightOpacity;
    final k = widget.opacity;
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            _box = c.biggest;
            return CustomPaint(
              size: c.biggest,
              painter: _ShapesPainter(
                shapes: _shapes,
                colors: [
                  for (var i = 0; i < 4; i++) colors[i].withValues(alpha: (colors[i].a * op[i] * k).clamp(0.0, 1.0)),
                ],
                repaint: _repaint,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShapesPainter extends CustomPainter {
  _ShapesPainter({required this.shapes, required this.colors, required Listenable repaint}) : super(repaint: repaint);
  final List<_Shape> shapes;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..isAntiAlias = true;
    for (final s in shapes) {
      final x = s.x * math.max(1, size.width - s.size);
      final y = s.y * math.max(1, size.height - s.size);
      paint.color = colors[s.colour];
      // `rotate()` de CSS gira el elemento alrededor de su centro.
      canvas.drawPath(s.shape.toPath(Rect.fromLTWH(x, y, s.size, s.size), rotation: s.r * math.pi / 180), paint);
    }
  }

  @override
  bool shouldRepaint(_ShapesPainter old) => !listEquals(old.colors, colors) || !identical(old.shapes, shapes);
}
