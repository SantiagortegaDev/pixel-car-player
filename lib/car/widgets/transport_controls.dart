import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/widgets/wavy_slider.dart';

/// Controles multimedia M3 Expressive: anterior / play-pausa (forma que se
/// transforma) / siguiente. Todos los objetivos táctiles ≥ 64 px.
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.playing,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    this.compact = false,
  });

  final bool playing;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool compact;

  /// Alto que ocupa la fila (para cálculos de layout).
  static double heightFor(double s, {bool compact = false}) =>
      compact ? 72 * s.clamp(1.0, 1.8) : 104 * s.clamp(0.9, 1.8);

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(compact ? 1.0 : 0.9, 1.8);
    final play = (compact ? 72 : 104) * s;
    final side = (compact ? 64 : 76) * s;
    final gap = (compact ? 12 : 20) * s;
    return SizedBox(
      height: heightFor(context.s, compact: compact),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TonalButton(
            size: side,
            icon: Icons.skip_previous_rounded,
            tooltip: 'Anterior',
            onTap: onPrevious,
          ),
          SizedBox(width: gap),
          PlayPauseButton(size: play, playing: playing, onTap: onToggle),
          SizedBox(width: gap),
          _TonalButton(
            size: side,
            icon: Icons.skip_next_rounded,
            tooltip: 'Siguiente',
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

/// `IconButton.filledTonal` grande (secondaryContainer).
class _TonalButton extends StatelessWidget {
  const _TonalButton({
    required this.size,
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final double size;
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: size * 0.5,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size / 2)),
      ),
      icon: Icon(icon),
    );
  }
}

/// Play/pausa estilo Android 14: botón `primary` que se transforma de
/// círculo (en pausa) a cuadrado redondeado (reproduciendo), con el ícono
/// animado de Material.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.size,
    required this.playing,
    required this.onTap,
  });
  final double size;
  final bool playing;
  final VoidCallback onTap;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.playing ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInOutCubic,
  );

  @override
  void didUpdateWidget(PlayPauseButton old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = widget.size;
    return Semantics(
      button: true,
      label: widget.playing ? 'Pausar' : 'Reproducir',
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final t = _curve.value;
          // Círculo (0.5) → cuadrado redondeado (0.3).
          final radius = size * (0.5 - 0.2 * t.clamp(0.0, 1.1));
          return Material(
            color: cs.primary,
            elevation: 3,
            shadowColor: cs.shadow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              splashColor: cs.onPrimary.withValues(alpha: 0.12),
              highlightColor: cs.onPrimary.withValues(alpha: 0.10),
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _c,
                    color: cs.onPrimary,
                    size: size * 0.46,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// WavySlider (estilo Android 13) con tiempos a los lados. La onda se
/// aplana suavemente al pausar.
class CarProgressBar extends StatelessWidget {
  const CarProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onSeek,
  });

  final ValueListenable<Duration> position;
  final Duration duration;
  final bool playing;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final k = s.clamp(0.95, 1.6);
    final cs = context.cs;
    final timeStyle = context.tt.labelLarge
        .scaled(1.25 * k, color: cs.onSurfaceVariant, weight: FontWeight.w500)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final total = duration.inMilliseconds;
    final touch = kCarMinTouch * s.clamp(1.0, 1.6);
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, pos, _) {
        final v = total > 0 ? pos.inMilliseconds.clamp(0, total).toDouble() : 0.0;
        return Row(
          children: [
            SizedBox(
              width: 62 * k,
              child: Text(formatDuration(pos), style: timeStyle),
            ),
            SizedBox(width: 8 * s),
            Expanded(
              child: SizedBox(
                // Zona táctil alta (≥64) para arrastrar manejando.
                height: touch,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: playing ? 5.5 * k : 0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCubic,
                  builder: (context, amp, _) => RepaintBoundary(
                    child: WavySlider(
                      value: v,
                      min: 0,
                      max: total > 0 ? total.toDouble() : 1,
                      onChanged: (x) => onSeek(Duration(milliseconds: x.round())),
                      height: touch,
                      waveAmplitude: amp,
                      waveLength: 30 * k,
                      waveSpeed: 1.4,
                      animateOnPlay: playing || amp > 0.05,
                      activeColor: cs.primary,
                      inactiveColor: cs.surfaceContainerHighest,
                      thumbColor: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8 * s),
            SizedBox(
              width: 62 * k,
              child: Text(formatDuration(duration), style: timeStyle, textAlign: TextAlign.right),
            ),
          ],
        );
      },
    );
  }
}
