import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/widgets/background_shapes.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// `14:05`, `2:05` (12 h) y opcionalmente los segundos.
String formatClock(DateTime t, {bool use24h = true, bool seconds = false}) {
  final h = use24h ? t.hour : (t.hour % 12 == 0 ? 12 : t.hour % 12);
  final hh = use24h ? h.toString().padLeft(2, '0') : '$h';
  final mm = t.minute.toString().padLeft(2, '0');
  return seconds ? '$hh:$mm:${t.second.toString().padLeft(2, '0')}' : '$hh:$mm';
}

/// `a. m.` / `p. m.` (es).
String meridiem(DateTime t) => t.hour < 12 ? 'a. m.' : 'p. m.';

/// `sábado, 4 de octubre`.
String formatDate(DateTime t) => '${_days[t.weekday - 1]}, ${t.day} de ${_months[t.month - 1]}';

/// Desplazamiento anti marcas (burn-in): recorre 9 posiciones de ±[px] px, una por minuto.
Offset burnInOffset(DateTime t, {double px = 6}) {
  const path = [(0, 0), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
  final (x, y) = path[(t.hour * 60 + t.minute) % path.length];
  return Offset(x * px, y * px);
}

/// Reloj de espera de Harmonix: hora enorme (Google Sans Flex, peso fino), fecha, formas
/// que flotan despacio y la portada de lo último que sonó. Tocar en cualquier parte vuelve.
class CarStandbyView extends StatefulWidget {
  const CarStandbyView({
    super.key,
    required this.onWake,
    this.last,
    this.reduced = false,
    this.lowPerf = false,
    this.now,
  });

  final VoidCallback onWake;

  /// Lo último que sonó (título + carátula).
  final NowPlaying? last;
  final bool reduced;

  /// Modo rendimiento: menos formas.
  final bool lowPerf;

  /// Hora fija (pruebas / capturas).
  final DateTime Function()? now;

  @override
  State<CarStandbyView> createState() => _CarStandbyViewState();
}

class _CarStandbyViewState extends State<CarStandbyView> {
  Timer? _t;
  late DateTime _now = _clock();

  DateTime _clock() => (widget.now ?? DateTime.now)();

  bool _seconds = false;

  void _schedule() {
    final s = _seconds;
    final n = DateTime.now();
    final wait = s
        ? Duration(milliseconds: 1000 - n.millisecond + 20)
        : Duration(seconds: 60 - n.second, milliseconds: -n.millisecond + 50);
    _t = Timer(wait, () {
      if (!mounted) return;
      setState(() => _now = _clock());
      _schedule();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _seconds = CarCustomScope.of(context).standby.seconds;
    _t?.cancel();
    _schedule();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = CarCustomScope.of(context);
    final s = cfg.standby;
    final cs = context.cs;
    final tt = context.tt;
    final now = _now;
    final last = widget.last;
    return Semantics(
      button: true,
      label: 'Reloj de espera. Toca para volver al reproductor.',
      child: GestureDetector(
        key: const ValueKey('car-standby'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onWake,
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight, w = c.maxWidth;
            final clockSize = math.min(h * 0.34, w * (s.seconds ? 0.15 : 0.2)) * s.clockScale;
            final offset = s.burnIn ? burnInOffset(now) : Offset.zero;
            final clock = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatClock(now, use24h: s.use24h, seconds: s.seconds),
                      key: const ValueKey('standby-clock'),
                      style: hxWeight(tt.displayLarge, 300).copyWith(
                        fontSize: clockSize,
                        height: 1,
                        letterSpacing: -clockSize * 0.02,
                        color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (!s.use24h) ...[
                      SizedBox(width: clockSize * 0.08),
                      Text(
                        meridiem(now),
                        style: hxWeight(tt.headlineMedium, 400).copyWith(
                          fontSize: clockSize * 0.2,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                if (s.date) ...[
                  SizedBox(height: clockSize * 0.12),
                  Text(
                    formatDate(now),
                    style: hxWeight(tt.headlineSmall, 400).copyWith(
                      fontSize: math.max(18, clockSize * 0.16),
                      color: cs.primary,
                    ),
                  ),
                ],
                if (s.cover && last?.track != null) ...[
                  SizedBox(height: clockSize * 0.28),
                  _LastPlayed(np: last!, size: math.max(48, clockSize * 0.36)),
                ],
              ],
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (s.shapes)
                  BackgroundShapes(
                    playing: !widget.reduced,
                    reduced: widget.reduced,
                    count: widget.lowPerf ? 6 : 10,
                    opacity: 0.8,
                    minSize: 60,
                    maxSize: math.min(260, h * 0.45),
                    seed: 7,
                  ),
                Center(
                  child: AnimatedSlide(
                    offset: Offset(offset.dx / math.max(1, w), offset.dy / math.max(1, h)),
                    duration: widget.reduced ? Duration.zero : const Duration(seconds: 2),
                    curve: HxMotion.standard,
                    child: FittedBox(fit: BoxFit.scaleDown, child: clock),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LastPlayed extends StatelessWidget {
  const _LastPlayed({required this.np, required this.size});
  final NowPlaying np;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final t = np.track!;
    final Uint8List? art = np.artwork;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(size / 2 + 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: ClipPath(
              clipper: M3ShapeClipper(M3Shape.cookie9),
              child: HxCover(bytes: art, iconSize: size * 0.4),
            ),
          ),
          const SizedBox(width: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hxWeight(tt.titleMedium, 500).copyWith(color: cs.onSurface, fontSize: 17),
                ),
                if (t.artist.isNotEmpty)
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
