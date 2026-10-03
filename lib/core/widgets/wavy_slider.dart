import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Slider tipo "wavy" inspirado en github.com/mahozad/wavy-slider.
///
/// Se dibuja una onda sinusoidal animada; la porción a la izquierda del
/// thumb está activa (color de acento) y la de la derecha inactiva. El
/// thumb se mueve a lo largo del eje X según [value]. Al reproducir,
/// la onda se desplaza horizontalmente generando efecto de "flujo".
class WavySlider extends StatefulWidget {
  const WavySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.height = 40,
    this.waveAmplitude = 7,
    this.waveLength = 22,
    this.waveSpeed = 1.6,
    this.animateOnPlay = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  /// Por defecto: `primary` / `surfaceContainerHighest` / `primary` del tema (M3).
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final double height;
  final double waveAmplitude;
  final double waveLength;
  final double waveSpeed;
  final bool animateOnPlay;

  @override
  State<WavySlider> createState() => _WavySliderState();
}

class _WavySliderState extends State<WavySlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _normalized {
    final raw = _dragValue ??
        ((widget.value - widget.min) / (widget.max - widget.min));
    return raw.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      slider: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox;
          final w = box.size.width;
          final newV = (_dragValue ?? _normalized) + details.delta.dx / w;
          setState(() => _dragValue = newV.clamp(0.0, 1.0));
        },
        onHorizontalDragEnd: (_) {
          widget.onChanged(
              widget.min + _normalized * (widget.max - widget.min));
          setState(() {
            _dragValue = null;
          });
        },
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox;
          final w = box.size.width;
          final t = (details.localPosition.dx / w).clamp(0.0, 1.0);
          widget.onChanged(widget.min + t * (widget.max - widget.min));
          setState(() => _dragValue = t);
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _WavySliderPainter(
                progress: _controller.value,
                activeRatio: _normalized,
                activeColor: widget.activeColor ?? scheme.primary,
                inactiveColor:
                    widget.inactiveColor ?? scheme.surfaceContainerHighest,
                thumbColor: widget.thumbColor ?? scheme.primary,
                amplitude: widget.waveAmplitude,
                wavelength: widget.waveLength,
                phase: widget.animateOnPlay
                    ? _controller.value * 2 * math.pi * widget.waveSpeed
                    : 0,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WavySliderPainter extends CustomPainter {
  _WavySliderPainter({
    required this.progress,
    required this.activeRatio,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.amplitude,
    required this.wavelength,
    required this.phase,
  });

  final double progress;
  final double activeRatio;
  /// Por defecto: `primary` / `surfaceContainerHighest` / `primary` del tema (M3).
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double amplitude;
  final double wavelength;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;
    final activeX = w * activeRatio;

    // Track inactivo (toda la onda, gris)
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    _drawWave(canvas, size, inactivePaint, 0, w, cy, phase);

    // Track activo (recortado al ratio)
    canvas.save();
    final clip = Path()..addRect(Rect.fromLTWH(0, 0, activeX, h));
    canvas.clipPath(clip);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5);
    _drawWave(canvas, size, activePaint, 0, w, cy, phase);
    canvas.restore();

    // Glow en el thumb
    final glowPaint = Paint()
      ..color = thumbColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(Offset(activeX, cy), 12, glowPaint);

    // Thumb
    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(activeX, cy), 7, thumbPaint);
    final innerPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(activeX - 1.5, cy - 1.5), 2, innerPaint);
  }

  void _drawWave(Canvas canvas, Size size, Paint paint, double x0, double x1,
      double cy, double phase) {
    final path = Path();
    final step = 1.5;
    bool first = true;
    for (double x = x0; x <= x1; x += step) {
      final y = cy +
          amplitude * math.sin((x / wavelength) * 2 * math.pi + phase);
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavySliderPainter old) =>
      old.progress != progress ||
      old.activeRatio != activeRatio ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.amplitude != amplitude ||
      old.wavelength != wavelength ||
      old.phase != phase;
}
