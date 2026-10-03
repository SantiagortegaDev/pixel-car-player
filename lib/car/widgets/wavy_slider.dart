import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// StyledSlider "wavy" de Caelestia / Harmonix v2 (`WavySlider.svelte`):
///  [onda gruesa (0,7·alto) ── 4px ── cursor 4×(3·alto) ── 4px ── pista restante (alto) · punto]
/// La onda (amplitud = ½ grosor, 5 ondas a lo largo) avanza un ciclo cada 2 s mientras
/// suena y se aplana en pausa. La posición sigue al valor con un acercamiento exponencial
/// (90 ms); al arrastrar se pega al dedo y aparece la burbuja con el tiempo.
class HxWavySlider extends StatefulWidget {
  const HxWavySlider({
    super.key,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onSeek,
    this.height = 12,
    this.waveAmplitude = 1,
  });

  /// Posición "en vivo" (se lee en cada cuadro mientras suena).
  final Duration Function() position;
  final Duration duration;
  final bool playing;
  final ValueChanged<Duration> onSeek;
  final double height;

  /// Multiplicador de la amplitud de la onda (0 = recta).
  final double waveAmplitude;

  static const frequency = 5.0;
  static const waveMs = 2000.0;
  static const gap = 4.0;
  static const handle = 4.0;
  static const easeMs = 90.0;

  @override
  State<HxWavySlider> createState() => _HxWavySliderState();
}

class _HxWavySliderState extends State<HxWavySlider> with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _drag = AnimationController(vsync: this, duration: HxMotion.dSpringFast);
  final _frame = ValueNotifier<int>(0);
  double _phase = 0;
  double _amp = 0; // 0 = plano, 1 = onda completa
  late double _eased = _target();
  bool _dragging = false;
  double _dragFrac = 0;
  Duration _last = Duration.zero;
  double _width = 300;

  bool get _reduced => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  double get _max => widget.duration.inMilliseconds.toDouble();

  double _target() {
    if (_dragging) return _dragFrac;
    final m = _max;
    if (m <= 0) return 0;
    return (widget.position().inMilliseconds / m).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _amp = widget.playing && !_reduced ? 1 : 0;
    _wake();
  }

  @override
  void didUpdateWidget(HxWavySlider old) {
    super.didUpdateWidget(old);
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dtMs = _last == Duration.zero ? 16.0 : (now - _last).inMicroseconds / 1000;
    _last = now;
    final playing = widget.playing && !_reduced;
    if (playing) _phase = (_phase + dtMs / HxWavySlider.waveMs * math.pi * 2) % (math.pi * 2);
    // Aplanado al pausar / onda al reanudar.
    final ampGoal = playing ? 1.0 : 0.0;
    _amp += (ampGoal - _amp) * (1 - math.exp(-dtMs / 120));
    if ((ampGoal - _amp).abs() < 1e-3) _amp = ampGoal;
    final target = _target();
    if (_dragging || _reduced) {
      _eased = target;
    } else {
      _eased += (target - _eased) * (1 - math.exp(-dtMs / HxWavySlider.easeMs));
      if ((target - _eased).abs() < 1e-4) _eased = target;
    }
    _frame.value++;
    final settled = _eased == target && _amp == ampGoal;
    if (!playing && !_dragging && settled) _ticker.stop();
  }

  double _fracAt(double x) {
    final full = _width - HxWavySlider.handle - HxWavySlider.gap * 2;
    return ((x - HxWavySlider.gap) / (full <= 0 ? 1 : full)).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e) {
    if (_max <= 0) return;
    setState(() {
      _dragging = true;
      _dragFrac = _fracAt(e.localPosition.dx);
    });
    _drag.forward();
    _wake();
  }

  void _move(PointerMoveEvent e) {
    if (_dragging) setState(() => _dragFrac = _fracAt(e.localPosition.dx));
  }

  void _up() {
    if (!_dragging) return;
    final to = Duration(milliseconds: (_dragFrac * _max).round());
    setState(() => _dragging = false);
    _drag.reverse();
    _eased = _dragFrac;
    widget.onSeek(to);
    _wake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _drag.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = widget.height;
    final line = h * 0.7;
    final amp = line * 0.5;
    final boxH = math.max(h * 3.5, line + amp * 2 * widget.waveAmplitude + 4);
    return Semantics(
      slider: true,
      label: 'Posición',
      value: formatDuration(widget.position()),
      child: LayoutBuilder(
        builder: (context, c) {
          _width = c.maxWidth;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (_) => _up(),
            onPointerCancel: (_) => _up(),
            child: SizedBox(
              height: boxH,
              width: c.maxWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _WavyPainter(
                        frame: _frame,
                        state: this,
                        h: h,
                        primary: cs.primary,
                        track: cs.secondaryContainer,
                        drag: _drag,
                        waveAmp: widget.waveAmplitude,
                      ),
                    ),
                  ),
                  if (_dragging) _bubble(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final cs = context.cs;
    final full = math.max(0.0, _width - HxWavySlider.handle - HxWavySlider.gap * 2);
    final x = _dragFrac * full + HxWavySlider.gap + HxWavySlider.handle / 2;
    return Positioned(
      left: x - 40,
      width: 80,
      bottom: widget.height * 3.5 + 4,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(999)),
          child: Text(
            formatDuration(Duration(milliseconds: (_dragFrac * _max).round())),
            style: AppTheme.numStyle(context, size: 14).copyWith(color: cs.onInverseSurface),
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter({
    required Listenable frame,
    required this.state,
    required this.h,
    required this.primary,
    required this.track,
    required this.drag,
    required this.waveAmp,
  }) : super(repaint: Listenable.merge([frame, drag]));

  final double waveAmp;

  final _HxWavySliderState state;
  final double h;
  final Color primary;
  final Color track;
  final Animation<double> drag;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final line = h * 0.7;
    final amp = line * 0.5 * state._amp * waveAmp;
    const gap = HxWavySlider.gap, handle = HxWavySlider.handle;
    // Largo útil (sin el cursor), como `fullLength` en Caelestia.
    final full = math.max(0.0, w - handle - gap * 2);
    final filled = state._eased * full;
    final handleX = filled + gap;
    final restX = handleX + handle + gap;
    final restW = math.max(0.0, w - restX);

    // Onda (parte reproducida).
    final end = filled - line / 2;
    if (end > line / 2) {
      double y(double x) =>
          cy + amp * math.sin(HxWavySlider.frequency * math.pi * 2 * x / (full == 0 ? 1 : full) - state._phase);
      final p = Path()..moveTo(line / 2, y(line / 2));
      for (var x = line / 2 + 2; x < end; x += 2) {
        p.lineTo(x, y(x));
      }
      p.lineTo(end, y(end));
      canvas.drawPath(
        p,
        Paint()
          ..color = primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = line
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Pista restante: se desvanece cuando le queda poco ancho.
    if (restW > 0) {
      final o = math.min(restW, 12) / 12;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(restX, cy - h / 2, restW, h),
        Radius.circular(math.min(HxRadius.mV, h / 2)),
      );
      canvas.drawRRect(r, Paint()..color = track.withValues(alpha: track.a * o));
      final stopX = restX + restW - (h - 4) / 2 - 2;
      if (stopX - 2 >= restX) {
        canvas.drawCircle(Offset(stopX, cy), 2, Paint()..color = primary.withValues(alpha: primary.a * o));
      }
    }

    // Cursor: barra vertical de 4 px (3× alto; 3,5× al arrastrar).
    final hh = h * (3 + 0.5 * HxMotion.springFast.transform(drag.value));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(handleX, cy - hh / 2, handle, hh), const Radius.circular(2)),
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(_WavyPainter old) =>
      old.primary != primary || old.track != track || old.h != h || old.waveAmp != waveAmp;
}
