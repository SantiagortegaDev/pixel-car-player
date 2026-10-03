import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Barra superior: reloj + fecha, chip de conexión, letras y ajustes.
class CarTopBar extends StatelessWidget {
  const CarTopBar({
    super.key,
    required this.status,
    required this.source,
    required this.onSettings,
    this.onLyrics,
    this.lyricsActive = false,
  });

  final LinkStatus status;
  final CarSource source;
  final VoidCallback onSettings;
  final VoidCallback? onLyrics;
  final bool lyricsActive;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SizedBox(
      height: 72 * s.clamp(0.9, 1.6),
      child: Row(
        children: [
          const CarClock(),
          const Spacer(),
          if (source == CarSource.local) ...[const _LocalChip(), SizedBox(width: 12 * s)],
          ConnectionChip(status: status, demo: source == CarSource.demo),
          SizedBox(width: 12 * s),
          if (onLyrics != null) ...[
            CarIconButton(
              icon: lyricsActive ? Icons.close_fullscreen_rounded : Icons.lyrics_rounded,
              tooltip: lyricsActive ? 'Salir de letras' : 'Letras a pantalla completa',
              onTap: onLyrics!,
              highlighted: lyricsActive,
            ),
            SizedBox(width: 12 * s),
          ],
          CarIconButton(icon: Icons.settings_rounded, tooltip: 'Ajustes', onTap: onSettings),
        ],
      ),
    );
  }
}

class CarClock extends StatefulWidget {
  const CarClock({super.key});

  @override
  State<CarClock> createState() => _CarClockState();
}

class _CarClockState extends State<CarClock> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(0.9, 1.6);
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final date = '${_weekdays[_now.weekday - 1]}, ${_now.day} ${_months[_now.month - 1]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$hh:$mm',
          style: TextStyle(
            color: HarmonixColors.textPrimary,
            fontSize: 34 * s,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(width: 14 * s),
        Container(width: 2, height: 26 * s, color: Colors.white.withValues(alpha: 0.18)),
        SizedBox(width: 14 * s),
        Text(
          date,
          style: TextStyle(
            color: HarmonixColors.textSecondary,
            fontSize: 19 * s,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Chip de conexión: nombre del celular + ícono Wi-Fi/BT, o "Buscando…".
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.status, this.demo = false});
  final LinkStatus status;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(0.9, 1.6);
    final (IconData icon, String label, Color dot) = switch (status.phase) {
      LinkPhase.connected => (
        status.transport == 'bt' ? Icons.bluetooth_connected_rounded : Icons.wifi_rounded,
        status.device ?? 'Celular',
        HarmonixColors.success,
      ),
      LinkPhase.searching => (Icons.wifi_find_rounded, 'Buscando…', HarmonixColors.warning),
      LinkPhase.disconnected => (
        Icons.wifi_off_rounded,
        'Sin conexión',
        HarmonixColors.textDisabled,
      ),
    };
    return Container(
      height: 52 * s,
      constraints: BoxConstraints(maxWidth: 300 * s),
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: dot, pulse: status.phase == LinkPhase.searching, size: 10 * s),
          SizedBox(width: 12 * s),
          Icon(icon, color: HarmonixColors.textPrimary, size: 24 * s),
          SizedBox(width: 10 * s),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HarmonixColors.textPrimary,
                fontSize: 18 * s,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalChip extends StatelessWidget {
  const _LocalChip();

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(0.9, 1.6);
    return Container(
      height: 52 * s,
      padding: EdgeInsets.symmetric(horizontal: 18 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tablet_android_rounded, color: HarmonixColors.textSecondary, size: 22 * s),
          SizedBox(width: 8 * s),
          Text(
            'Reproductor local',
            style: TextStyle(
              color: HarmonixColors.textSecondary,
              fontSize: 17 * s,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulse, required this.size});
  final Color color;
  final bool pulse;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = widget.pulse ? 0.35 + 0.65 * _c.value : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.6 * t),
                blurRadius: widget.size,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Botón de ícono grande (≥ 64 px) para la barra superior.
class CarIconButton extends StatelessWidget {
  const CarIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.highlighted = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(1.0, 1.6);
    final p = context.palette;
    final size = kCarMinTouch * s;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted
            ? p.accent.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.08),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: HarmonixColors.textPrimary, size: 30 * s),
          ),
        ),
      ),
    );
  }
}
