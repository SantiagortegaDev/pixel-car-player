import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Forma de MD3 Expressive rellena con un ícono (`EmptyState .shape`). Con [spin] la
/// forma gira despacio (24 s por vuelta) y el ícono queda derecho.
class HxShapeTile extends StatefulWidget {
  const HxShapeTile({
    super.key,
    required this.shape,
    required this.size,
    required this.color,
    this.icon,
    this.iconColor,
    this.iconSize,
    this.filled = true,
    this.spin = false,
    this.child,
  });
  final M3Shape shape;
  final double size;
  final Color color;
  final IconData? icon;
  final Color? iconColor;
  final double? iconSize;
  final bool filled;
  final bool spin;
  final Widget? child;

  @override
  State<HxShapeTile> createState() => _HxShapeTileState();
}

class _HxShapeTileState extends State<HxShapeTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  void _sync() {
    final run = widget.spin && !_reduceMotion(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HxShapeTile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content =
        widget.child ??
        (widget.icon == null
            ? const SizedBox.shrink()
            : HxIcon(
                widget.icon!,
                size: widget.iconSize ?? widget.size * 0.43,
                color: widget.iconColor,
                filled: widget.filled,
              ));
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => ClipPath(
          clipper: M3ShapeClipper(
            widget.shape,
            rotation: _c.value * math.pi * 2,
          ),
          child: ColoredBox(color: widget.color, child: child),
        ),
        child: Center(child: content),
      ),
    );
  }
}

/// Indicador de carga de MD3 Expressive (`LoadingIndicator.svelte`): una forma que se
/// transforma (softBurst → cookie9 → pentágono → píldora → sunny → cookie4 → óvalo)
/// mientras gira, 4,55 s por ciclo.
class HxLoadingIndicator extends StatefulWidget {
  const HxLoadingIndicator({
    super.key,
    this.size = 48,
    this.contained = false,
    this.color,
  });
  final double size;
  final bool contained;
  final Color? color;

  @override
  State<HxLoadingIndicator> createState() => _HxLoadingIndicatorState();
}

class _HxLoadingIndicatorState extends State<HxLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4550),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        widget.color ?? (widget.contained ? cs.onPrimaryContainer : cs.primary);
    final inner = widget.size * (widget.contained ? 0.58 : 0.76);
    return Semantics(
      label: 'Cargando',
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: widget.contained
            ? BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle)
            : null,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final seq = M3Shape.loadingSequence;
            final f = _c.value * seq.length;
            final i = f.floor() % seq.length;
            final k = HxMotion.spring.transform(f - f.floor());
            final shape = M3Shape.lerp(seq[i], seq[(i + 1) % seq.length], k);
            return CustomPaint(
              size: Size.square(inner),
              painter: _ShapePainter(shape, _c.value * math.pi * 2, color),
            );
          },
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape, this.rotation, this.color);
  final M3Shape shape;
  final double rotation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      shape.toPath(Offset.zero & size, rotation: rotation),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ShapePainter old) => true;
}

/// BackgroundShapes de Caelestia (`BackgroundShapes.svelte`): formas MD3 que flotan y
/// giran despacio, en colores de contenedor con opacidad baja.
class HxBackgroundShapes extends StatefulWidget {
  const HxBackgroundShapes({
    super.key,
    this.count = 14,
    this.minSize = 36,
    this.maxSize = 124,
    this.animate = true,
    this.seed = 7,
  });
  final int count;
  final double minSize;
  final double maxSize;
  final bool animate;
  final int seed;

  @override
  State<HxBackgroundShapes> createState() => _HxBackgroundShapesState();
}

class _Floating {
  _Floating({
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

class _HxBackgroundShapesState extends State<HxBackgroundShapes>
    with SingleTickerProviderStateMixin {
  static const _pool = [
    'circle',
    'cookie4',
    'cookie6',
    'cookie7',
    'cookie9',
    'cookie12',
    'sunny', //
    'verySunny', 'softBurst', 'pentagon', 'gem', 'pill', 'triangle', 'clover4',
    'oval',
  ];
  static const _darkOpacity = [0.16, 0.16, 0.04, 0.16];
  static const _lightOpacity = [0.34, 0.34, 0.08, 0.2];

  late final List<_Floating> _shapes;
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  Size _box = Size.zero;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(widget.seed);
    double rand(double a, double b) => a + rnd.nextDouble() * (b - a);
    double signed(double a, double b) => rand(a, b) * (rnd.nextBool() ? 1 : -1);
    _shapes = List.generate(widget.count, (i) {
      return _Floating(
        size:
            widget.minSize +
            (i / widget.count) * (widget.maxSize - widget.minSize),
        shape: M3Shape.all[_pool[rnd.nextInt(_pool.length)]] ?? M3Shape.cookie9,
        colour: rnd.nextInt(4),
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        vx: signed(4, 18),
        vy: signed(4, 18),
        vr: rand(-12, 12),
        r: rand(0, 360),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HxBackgroundShapes old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && !_reduceMotion(context);
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : math.min(0.1, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final w = _box.width, h = _box.height;
    for (final s in _shapes) {
      final ww = math.max(1.0, w - s.size), hh = math.max(1.0, h - s.size);
      s.x += s.vx * dt / ww;
      s.y += s.vy * dt / hh;
      s.r += s.vr * dt;
      final mx = s.size / ww, my = s.size / hh;
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
    final light = cs.brightness == Brightness.light;
    final colors = [
      cs.primaryContainer,
      cs.secondaryContainer,
      cs.tertiaryContainer,
      cs.outlineVariant,
    ];
    final op = light ? _lightOpacity : _darkOpacity;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          _box = c.biggest;
          return ClipRect(
            child: CustomPaint(
              size: c.biggest,
              painter: _FloatPainter(_shapes, [
                for (var i = 0; i < 4; i++) colors[i].withValues(alpha: op[i]),
              ], _repaint),
            ),
          );
        },
      ),
    );
  }
}

class _FloatPainter extends CustomPainter {
  _FloatPainter(this.shapes, this.colors, Listenable repaint)
    : super(repaint: repaint);
  final List<_Floating> shapes;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in shapes) {
      final dx = s.x * math.max(1, size.width - s.size);
      final dy = s.y * math.max(1, size.height - s.size);
      final rect = Rect.fromLTWH(dx, dy, s.size, s.size);
      canvas.drawPath(
        s.shape.toPath(rect, rotation: s.r * math.pi / 180),
        Paint()..color = colors[s.colour],
      );
    }
  }

  @override
  bool shouldRepaint(_FloatPainter old) => old.colors != colors;
}

/// Estado vacío de Caelestia (`EmptyState.svelte`): ícono dentro de una forma MD3 en
/// primaryContainer que gira despacio, título headline-s y texto body-l.
class HxEmptyState extends StatelessWidget {
  const HxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.shape,
    this.padding = const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
  });
  final IconData icon;
  final String title;
  final String? text;
  final M3Shape? shape;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        children: [
          HxShapeTile(
            shape: shape ?? M3Shape.clover4,
            size: 112,
            color: cs.primaryContainer,
            icon: icon,
            iconColor: cs.onPrimaryContainer,
            iconSize: 48,
            spin: true,
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: HxType.headlineS(cs.onSurface),
            textAlign: TextAlign.center,
          ),
          if (text != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                text!,
                style: HxType.bodyL(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
