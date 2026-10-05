import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/audio/car_audio_levels.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// CoverVisualiser de Caelestia / Harmonix v2 (`Disc.svelte`): la portada recortada con
/// una forma MD3 (Cookie9Sided por defecto), que gira (solo la máscara; 23,5 s por vuelta)
/// mientras suena, y 44 barras tipo píldora que nacen del borde de la forma + 12 px.
///
/// Las barras salen del audio real de la tableta ([audio], Visualizer de Android) cuando
/// [realAudio] (solo el FFT, sin mezclar nada procedural); si no, de un pseudo-espectro
/// procedural. Siempre graves arriba, agudos abajo, reflejado izquierda/derecha (barra `i` y
/// `n-1-i` = misma banda, como Harmonix), con el suavizado de Harmonix (ataque 0,35 · caída
/// 0,12) o el de "Respuesta del visualizador". Sin actividad bajan hasta quedar como puntos.
///
/// [playing] = "animar" (suena, se detectó audio o "Animar siempre"). Con [reduced] no
/// gira ni se mueven las barras (como el modo reducido de Harmonix).
///
/// Todo es configurable desde Configuración → Portada y visualizador ([cover], [viz]).
class Disc extends StatefulWidget {
  const Disc({
    super.key,
    required this.artwork,
    required this.size,
    required this.playing,
    this.seed,
    this.cover = const CarCoverOpts(),
    this.viz = const CarVisualizerOpts(),
    this.showBars = true,
    this.reduced,
    this.audio,
    this.realAudio = false,
    this.coverChange = CarCoverChange.crossfade,
  });

  final Uint8List? artwork;

  /// Animación al cambiar la portada (Configuración → Animaciones).
  final CarCoverChange coverChange;
  final double size;
  final bool playing;
  final int? seed;
  final CarCoverOpts cover;
  final CarVisualizerOpts viz;
  final bool showBars;

  /// Animaciones reducidas (`null` = la preferencia del sistema).
  final bool? reduced;

  /// Niveles del audio real (eventos `fft`).
  final CarAudioLevels? audio;

  /// Usar [audio] en vez del espectro simulado.
  final bool realAudio;

  static const bars = 44;
  static const spacing = 12.0;
  static const turnMs = 23500;

  @override
  State<Disc> createState() => _DiscState();
}

/// Geometría del disco para un tamaño y unas opciones: radio de la portada, grosor y
/// largo máximo de las barras. Si las barras amplificadas no caben, la portada se achica
/// (hasta un mínimo) y las barras pueden salir un poco del cuadro.
@visibleForTesting
class DiscGeometry {
  DiscGeometry._(this.coverR, this.stroke, this.magnitude, this.spacing);
  final double coverR, stroke, magnitude, spacing;

  factory DiscGeometry.of(double s, CarVisualizerOpts v, {bool bars = true}) {
    final spacing = v.spacing;
    if (!bars) return DiscGeometry._((s * 0.84 / 2).roundToDouble(), 0, 0, spacing);
    double strokeFor(double r) =>
        math.min(10.0, math.max(4.0, 2 * math.pi * (r + spacing) / v.bars * 0.36)) * v.thickness;
    final baseR = (s * 0.62).roundToDouble() / 2;
    final baseStroke = strokeFor(baseR);
    // Largo de Harmonix con los valores de fábrica.
    final baseMag = math.max(0.0, math.min((s - baseR * 2) / 2 - Disc.spacing - baseStroke, s * 0.11));
    final want = baseMag * v.amplification;
    final outer = s / 2 + (v.amplification > 1 ? s * 0.06 : 0);
    var r = math.min(baseR, outer - spacing - baseStroke - want);
    r = math.max(r, s * 0.2);
    final stroke = strokeFor(r);
    final mag = math.max(0.0, math.min(want, outer - r - spacing - stroke));
    return DiscGeometry._(r == baseR ? baseR : r.roundToDouble(), stroke, mag, spacing);
  }
}

class _DiscState extends State<Disc> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  late Float32List _levels = Float32List(widget.viz.bars);
  double _rotation = 0; // grados
  Duration _last = Duration.zero;
  late final math.Random _rnd = math.Random(widget.seed);
  late _Spectrum _spectrum = _Spectrum(widget.viz.bars ~/ 2, _rnd);

  bool get _reduced =>
      widget.reduced ?? WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  bool get _real => widget.realAudio && widget.audio != null;
  bool get _animating => widget.playing && !_reduced && (widget.cover.rotate || widget.showBars);

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void didUpdateWidget(Disc old) {
    super.didUpdateWidget(old);
    if (old.viz.bars != widget.viz.bars) {
      final next = Float32List(widget.viz.bars);
      for (var i = 0; i < next.length; i++) {
        next[i] = _levels.isEmpty ? 0 : _levels[(i * _levels.length / next.length).floor()];
      }
      _levels = next;
      _spectrum = _Spectrum(widget.viz.bars ~/ 2, _rnd);
    }
    if (old.playing != widget.playing ||
        old.cover.rotate != widget.cover.rotate ||
        old.showBars != widget.showBars ||
        old.reduced != widget.reduced ||
        old.realAudio != widget.realAudio) {
      _wake();
    }
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
    if (playing && widget.cover.rotate) {
      _rotation = (_rotation - dt * 360 / widget.cover.turnSeconds) % 360;
    }
    final speed = widget.viz.speed;
    final real = _real;
    if (playing && !real) _spectrum.advance(dt * speed);

    var active = false;
    final bars = _levels.length;
    final half = bars ~/ 2;
    // El suavizado de Harmonix es por cuadro (≈60 fps); se corrige por dt y velocidad.
    // Con el audio real, "Respuesta del visualizador" elige cuánto se suaviza (Precisa casi
    // no suaviza: las barras siguen cada cuadro del FFT, sin nada simulado mezclado).
    final f = dt * 60 * math.sqrt(speed);
    final (attack, release) = real ? widget.viz.response.smoothing : CarVizResponse.normal.smoothing;
    for (var i = 0; i < bars; i++) {
      final k = i < half ? i : bars - 1 - i;
      final target = !playing || !widget.showBars
          ? 0.0
          : real
          ? widget.audio!.level(k, half, sensitivity: widget.viz.sensitivity)
          : _spectrum.target(k);
      final a = target > _levels[i] ? attack : release;
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

  Color _barColor(ColorScheme cs) => switch (widget.viz.color) {
    CarVizColor.primary => cs.primary,
    CarVizColor.secondary => cs.secondary,
    CarVizColor.tertiary => cs.tertiary,
    CarVizColor.onSurface => cs.onSurface,
  };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final size = widget.size;
    final shape = M3Shape.all[widget.cover.shape] ?? M3Shape.cookie9;
    final geo = DiscGeometry.of(size, widget.viz, bars: widget.showBars);
    final coverSize = geo.coverR * 2;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BarsPainter(
                  levels: () => _levels,
                  geo: geo,
                  shape: shape,
                  rotation: () => _rotation,
                  color: _barColor(cs),
                  outline: widget.cover.outline ? cs.outline.withValues(alpha: 0.45) : null,
                  glow: widget.cover.glow ? cs.primary.withValues(alpha: 0.55) : null,
                  bars: widget.showBars,
                  roundCaps: widget.viz.roundCaps,
                  pausedDots: widget.viz.pausedDots,
                  repaint: _frame,
                ),
              ),
            ),
            SizedBox.square(
              dimension: coverSize,
              child: ClipPath(
                clipper: _RotatingClip(shape, () => _rotation, _frame),
                child: CoverSwap(
                  artwork: widget.artwork,
                  mode: widget.coverChange,
                  reduced: _reduced,
                  iconSize: coverSize * 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La carátula con la animación de cambio elegida: fundido, deslizar, escala o una forma
/// que crece desde el centro (MD3 shape morph).
class CoverSwap extends StatelessWidget {
  const CoverSwap({
    super.key,
    required this.artwork,
    this.mode = CarCoverChange.crossfade,
    this.reduced = false,
    this.iconSize = 48,
  });
  final Uint8List? artwork;
  final CarCoverChange mode;
  final bool reduced;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(artwork == null ? 0 : identityHashCode(artwork));
    final child = KeyedSubtree(
      key: key,
      child: HxCover(bytes: artwork, iconSize: iconSize),
    );
    if (reduced) return child;
    return AnimatedSwitcher(
      duration: mode == CarCoverChange.crossfade ? HxMotion.dLarge : const Duration(milliseconds: 650),
      switchInCurve: HxMotion.emphasizedDecel,
      switchOutCurve: HxMotion.emphasizedAccel,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (c, a) {
        final incoming = c.key == key;
        switch (mode) {
          case CarCoverChange.crossfade:
            return FadeTransition(opacity: a, child: c);
          case CarCoverChange.slide:
            return SlideTransition(
              position: Tween(begin: Offset(incoming ? 1 : -1, 0), end: Offset.zero).animate(a),
              child: c,
            );
          case CarCoverChange.scalePop:
            return FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: incoming ? 0.78 : 1.12, end: 1.0).animate(a), child: c),
            );
          case CarCoverChange.morph:
            if (!incoming) return c;
            return AnimatedBuilder(
              animation: a,
              builder: (_, child) => ClipPath(clipper: _MorphReveal(a.value), child: child),
              child: c,
            );
        }
      },
      child: child,
    );
  }
}

/// Revela la portada nueva con una galleta de 4 lados que gira y se vuelve círculo al crecer.
class _MorphReveal extends CustomClipper<Path> {
  _MorphReveal(this.t);
  final double t;

  @override
  Path getClip(Size size) {
    final r = size.shortestSide * 0.75 * t;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: math.max(0.5, r));
    return M3Shape.lerp(M3Shape.cookie4, M3Shape.circle, t).toPath(rect, rotation: (1 - t) * math.pi / 2);
  }

  @override
  bool shouldReclip(_MorphReveal old) => old.t != t;
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
    required this.geo,
    required this.shape,
    required this.rotation,
    required this.color,
    required this.outline,
    required this.glow,
    required this.bars,
    required this.roundCaps,
    required this.pausedDots,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Float32List Function() levels;
  final DiscGeometry geo;
  final M3Shape shape;
  final double Function() rotation;
  final Color color;
  final Color? outline;
  final Color? glow;
  final bool bars;
  final bool roundCaps;
  final bool pausedDots;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = s / 2;
    final coverR = geo.coverR;
    final rotRad = rotation() * math.pi / 180;
    final shapePath = shape.toPath(
      Rect.fromCircle(center: Offset(c, c), radius: coverR),
      rotation: rotRad,
    );

    if (glow != null) {
      canvas.drawPath(
        shapePath,
        Paint()
          ..color = glow!
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06),
      );
    }
    // Un leve brillo en el color outline separa la forma del fondo (drop-shadow 1px).
    if (outline != null) {
      canvas.drawPath(
        shapePath,
        Paint()
          ..color = outline!
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 1.2),
      );
    }
    if (!bars) return;

    final lv = levels();
    final n = lv.length;
    final stroke = geo.stroke;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = roundCaps ? StrokeCap.round : StrokeCap.butt
      ..style = PaintingStyle.stroke;
    // Con extremos rectos, el "punto" de pausa se dibuja como un cuadrado chico.
    final minLen = roundCaps ? 0.0 : stroke * 0.6;
    for (var i = 0; i < n; i++) {
      final raw = lv[i];
      if (!pausedDots && raw < 0.02) continue;
      final value = raw.clamp(0.01, 1.0);
      // Ángulo desde arriba, en sentido horario (convención de shapes.js).
      final fromTop = i / n * math.pi * 2;
      final edge = coverR * shape.radiusAt(fromTop - rotRad) + geo.spacing + stroke / 2;
      final dist = edge + math.max(minLen, value * geo.magnitude);
      final sn = math.sin(fromTop), cs = -math.cos(fromTop);
      canvas.drawLine(Offset(c + sn * edge, c + cs * edge), Offset(c + sn * dist, c + cs * dist), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.color != color ||
      old.outline != outline ||
      old.glow != glow ||
      old.shape != shape ||
      old.bars != bars ||
      old.roundCaps != roundCaps ||
      old.pausedDots != pausedDots ||
      old.geo.coverR != geo.coverR ||
      old.geo.stroke != geo.stroke ||
      old.geo.magnitude != geo.magnitude ||
      old.geo.spacing != geo.spacing;
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
    final x = bands <= 1 ? 0.0 : k / (bands - 1); // 0 = graves (arriba), 1 = agudos (abajo)
    final env = 0.98 - 0.82 * math.pow(x, 0.7);
    const beatHz = 118 / 60;
    final ph = (_t * beatHz) % 1.0;
    final kick = math.exp(-ph * 6) * math.max(0, 1 - x * 2.2);
    final section = 0.9 + 0.1 * math.sin(_t * 0.37 + k * 0.2);
    final raw = env * (0.5 + 0.5 * _noise[k]) * section + kick * 0.32;
    return math.pow(raw.clamp(0.0, 1.0), 1.8) * 0.9;
  }
}
