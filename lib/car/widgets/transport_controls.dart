import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:pixel_car_player/core/widgets/wavy_slider.dart';

/// Anterior / play-pausa (círculo con gradiente Harmonix) / siguiente.
/// Todos los objetivos táctiles ≥ 64 px.
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
      (compact ? 80 : 104) * s.clamp(0.85, 1.8);

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(0.85, 1.8);
    final play = (compact ? 76 : 96) * s;
    final side = (compact ? 64 : 76) * s;
    return SizedBox(
      height: heightFor(context.s, compact: compact),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundButton(
            size: side,
            icon: Icons.skip_previous_rounded,
            tooltip: 'Anterior',
            onTap: onPrevious,
          ),
          SizedBox(width: (compact ? 20 : 28) * s),
          PlayPauseButton(size: play, playing: playing, onTap: onToggle),
          SizedBox(width: (compact ? 20 : 28) * s),
          _RoundButton(
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({
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
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: p.accent.withValues(alpha: 0.25),
          highlightColor: p.accent.withValues(alpha: 0.12),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: HarmonixColors.textPrimary, size: size * 0.56),
          ),
        ),
      ),
    );
  }
}

/// Botón circular con gradiente del acento (como `_PlayPauseBig` de Harmonix).
class PlayPauseButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accentBright, p.accent, p.accentDim],
          stops: const [0, 0.45, 1],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.5),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                color: Colors.white,
                size: size * 0.52,
                shadows: const [Shadow(color: Color(0x40000000), blurRadius: 6)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// WavySlider de Harmonix con tiempos grandes a los lados.
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
    final p = context.palette;
    final timeStyle = TextStyle(
      color: HarmonixColors.textSecondary,
      fontSize: 18 * s.clamp(0.9, 1.6),
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final total = duration.inMilliseconds;
    return ValueListenableBuilder<Duration>(
      valueListenable: position,
      builder: (context, pos, _) {
        final v = total > 0 ? pos.inMilliseconds.clamp(0, total).toDouble() : 0.0;
        return Row(
          children: [
            SizedBox(
              width: 64 * s.clamp(0.9, 1.6),
              child: Text(formatDuration(pos), style: timeStyle),
            ),
            Expanded(
              child: SizedBox(
                // Zona táctil alta (≥64) para arrastrar manejando.
                height: kCarMinTouch * s.clamp(1.0, 1.6),
                child: Center(
                  child: RepaintBoundary(
                    child: WavySlider(
                      value: v,
                      min: 0,
                      max: total > 0 ? total.toDouble() : 1,
                      onChanged: (x) => onSeek(Duration(milliseconds: x.round())),
                      height: kCarMinTouch * s.clamp(1.0, 1.6),
                      waveAmplitude: playing ? 6 * s : 0.01,
                      waveLength: 26 * s,
                      waveSpeed: 1.8,
                      animateOnPlay: playing,
                      activeColor: p.accent,
                      inactiveColor: Colors.white.withValues(alpha: 0.16),
                      thumbColor: p.accentBright,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64 * s.clamp(0.9, 1.6),
              child: Text(formatDuration(duration), style: timeStyle, textAlign: TextAlign.right),
            ),
          ],
        );
      },
    );
  }
}
