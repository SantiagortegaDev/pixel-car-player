import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';

/// CoverVisualiser de Caelestia / Harmonix v2 (`Disc.svelte`): la portada recortada con
/// la forma MD3 Cookie9Sided, que gira (solo la máscara; 23,5 s por vuelta) mientras
/// suena, y 44 barras tipo píldora que nacen del borde de la forma + 12 px.
///
/// La tableta no tiene el audio (sale por el Bluetooth del radio), así que las barras se
/// alimentan con un pseudo-espectro procedural: graves arriba, agudos abajo, reflejado
/// izquierda/derecha, con el mismo suavizado de Harmonix (ataque 0,35 · caída 0,12).
/// En pausa bajan hasta quedar como puntos.
class Disc extends StatefulWidget {
  const Disc({super.key, required this.artwork, required this.size, required this.playing, this.seed});

  final Uint8List? artwork;
  final double size;
  final bool playing;
  final int? seed;

  static const bars = 44;
  static const spacing = 12.0;
  static const turnMs = 23500;

  @override
  State<Disc> createState() => _DiscState();
}

class _DiscState extends State<Disc> with SingleTickerProviderStateMixin {
  static final M3Shape _shape = M3Shape.cookie9;

  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  final Float32List _levels = Float32List(Disc.bars);
  double _rotation = 0; // grados
  Duration _last = Duration.zero;
  late final _Spectrum _spectrum = _Spectrum(Disc.bars ~/ 2, math.Random(widget.seed));

  bool get _reduced => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  bool get _animating => widget.playing && !_reduced;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void didUpdateWidget(Disc old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : math.min(0.1, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final playing = _animating;
    if (playing) _rotation = (_rotation - dt * 360000 / Disc.turnMs) % 360;
    if (playing) _spectrum.advance(dt);

    var active = false;
    const half = Disc.bars ~/ 2;
    // El suavizado de Harmonix es por cuadro (≈60 fps); se corrige por dt.
    final f = dt * 60;
    for (var i = 0; i < Disc.bars; i++) {
      final k = i < half ? i : Disc.bars - 1 - i;
      final target = playing ? _spectrum.target(k) : 0.0;
      final a = target > _levels[i] ? 0.35 : 0.12;
      _levels[i] += (target - _levels[i]) * (1 - math.pow(1 - a, f));
      if (_levels[i] > 0.004) active = true;
    }
    _frame.value++;
    // Se dibuja mientras suena o mientras las barras terminan de bajar.
    if (!playing && !active) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final size = widget.size;
    final coverSize = (size * 0.62).roundToDouble();
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BarsPainter(
                  levels: _levels,
                  coverR: coverSize / 2,
                  rotation: () => _rotation,
                  color: cs.primary,
                  glow: cs.outline.withValues(alpha: 0.45),
                  repaint: _frame,
                ),
              ),
            ),
            SizedBox.square(
              dimension: coverSize,
              child: ClipPath(
                clipper: _RotatingClip(_shape, () => _rotation, _frame),
                child: HxCover(bytes: widget.artwork, iconSize: coverSize * 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RotatingClip extends CustomClipper<Path> {
  _RotatingClip(this.shape, this.rotation, Listenable reclip) : super(reclip: reclip);
  final M3Shape shape;
  final double Function() rotation;

  @override
  Path getClip(Size size) => shape.toPath(Offset.zero & size, rotation: rotation() * math.pi / 180);

  @override
  bool shouldReclip(_RotatingClip old) => true;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.levels,
    required this.coverR,
    required this.rotation,
    required this.color,
    required this.glow,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Float32List levels;
  final double coverR;
  final double Function() rotation;
  final Color color;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = s / 2;
    const bars = Disc.bars;
    const spacing = Disc.spacing;
    final coverSize = coverR * 2;
    // Grosor proporcional al perímetro: barras tipo píldora, como en Caelestia.
    final stroke = math.min(10.0, math.max(4.0, 2 * math.pi * (coverR + spacing) / bars * 0.36));
    final maxMagnitude = math.min((s - coverSize) / 2 - spacing - stroke, s * 0.11);
    final rotRad = rotation() * math.pi / 180;

    // Un leve brillo en el color outline separa la forma del fondo (drop-shadow 1px).
    final shapePath = M3Shape.cookie9.toPath(
      Rect.fromCircle(center: Offset(c, c), radius: coverR),
      rotation: rotRad,
    );
    canvas.drawPath(
      shapePath,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 1.2),
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < bars; i++) {
      final value = levels[i].clamp(0.01, 1.0);
      // Ángulo desde arriba, en sentido horario (convención de shapes.js).
      final fromTop = i / bars * math.pi * 2;
      final edge = coverR * M3Shape.cookie9.radiusAt(fromTop - rotRad) + spacing + stroke / 2;
      final dist = edge + value * maxMagnitude;
      final sn = math.sin(fromTop), cs = -math.cos(fromTop);
      canvas.drawLine(Offset(c + sn * edge, c + cs * edge), Offset(c + sn * dist, c + cs * dist), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.glow != glow || old.coverR != coverR;
}

/// Pseudo-espectro: una envolvente con más energía en los graves (arriba), ruido suave
/// por banda que cambia a intervalos irregulares y un "bombo" a ~118 BPM en las bandas
/// bajas. Devuelve niveles 0..1 ya con la curva de Harmonix (`pow(x, 1.8) * 0.9`).
class _Spectrum {
  _Spectrum(this.bands, this.rnd)
    : _noise = List.generate(bands, (_) => rnd.nextDouble()),
      _goal = List.generate(bands, (_) => rnd.nextDouble()),
      _wait = List.generate(bands, (_) => rnd.nextDouble() * 0.15);

  final int bands;
  final math.Random rnd;
  final List<double> _noise;
  final List<double> _goal;
  final List<double> _wait;
  double _t = 0;

  void advance(double dt) {
    _t += dt;
    for (var k = 0; k < bands; k++) {
      _wait[k] -= dt;
      if (_wait[k] <= 0) {
        _goal[k] = rnd.nextDouble();
        _wait[k] = 0.07 + rnd.nextDouble() * 0.16;
      }
      _noise[k] += (_goal[k] - _noise[k]) * math.min(1, dt * 14);
    }
  }

  double target(int k) {
    final x = k / (bands - 1); // 0 = graves (arriba), 1 = agudos (abajo)
    final env = 0.98 - 0.82 * math.pow(x, 0.7);
    const beatHz = 118 / 60;
    final ph = (_t * beatHz) % 1.0;
    final kick = math.exp(-ph * 6) * math.max(0, 1 - x * 2.2);
    final section = 0.9 + 0.1 * math.sin(_t * 0.37 + k * 0.2);
    final raw = env * (0.5 + 0.5 * _noise[k]) * section + kick * 0.32;
    return math.pow(raw.clamp(0.0, 1.0), 1.8) * 0.9;
  }
}
