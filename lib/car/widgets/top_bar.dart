import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
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

/// Barra superior M3: reloj + fecha, chip de conexión, letras y ajustes.
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

  static double heightFor(double s) => kCarMinTouch * s.clamp(1.0, 1.6);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final gap = 12 * s.clamp(0.9, 1.6);
    return SizedBox(
      height: heightFor(s),
      child: Row(
        children: [
          const CarClock(),
          SizedBox(width: gap),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (source == CarSource.local) ...[const _LocalChip(), SizedBox(width: gap)],
                Flexible(child: ConnectionChip(status: status)),
              ],
            ),
          ),
          SizedBox(width: gap),
          if (onLyrics != null) ...[
            CarIconButton(
              icon: Icons.lyrics_outlined,
              selectedIcon: Icons.lyrics_rounded,
              tooltip: lyricsActive ? 'Salir de letras' : 'Letras a pantalla completa',
              onTap: onLyrics!,
              selected: lyricsActive,
            ),
            SizedBox(width: gap),
          ],
          CarIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Ajustes',
            onTap: onSettings,
          ),
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
    final k = context.s.clamp(0.9, 1.6);
    final cs = context.cs;
    final tt = context.tt;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final date = '${_weekdays[_now.weekday - 1]}, ${_now.day} ${_months[_now.month - 1]}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$hh:$mm',
          style: tt.displaySmall
              .scaled(k, color: cs.onSurface, weight: FontWeight.w400, height: 1)
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        SizedBox(width: 16 * k),
        Container(
          width: 1,
          height: 28 * k,
          color: cs.outlineVariant,
        ),
        SizedBox(width: 16 * k),
        Text(date, style: tt.titleLarge.scaled(k, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

/// Chip de conexión M3: nombre del celular + ícono Wi-Fi/BT, o "Buscando…".
/// `secondaryContainer` conectado, `surfaceContainerHigh` buscando y
/// `errorContainer` sin conexión.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.status});
  final LinkStatus status;

  @override
  Widget build(BuildContext context) {
    final k = context.s.clamp(0.9, 1.6);
    final cs = context.cs;
    final (Widget leading, String label, Color bg, Color fg) = switch (status.phase) {
      LinkPhase.connected => (
        Icon(status.transport == 'bt' ? Icons.bluetooth_connected_rounded : Icons.wifi_rounded),
        status.device ?? 'Celular',
        cs.secondaryContainer,
        cs.onSecondaryContainer,
      ),
      LinkPhase.searching => (
        SizedBox.square(
          dimension: 20 * k,
          child: CircularProgressIndicator(strokeWidth: 2.6 * k, color: cs.primary),
        ),
        'Buscando…',
        cs.surfaceContainerHigh,
        cs.onSurface,
      ),
      LinkPhase.disconnected => (
        const Icon(Icons.wifi_off_rounded),
        'Sin conexión',
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 52 * k,
      constraints: BoxConstraints(maxWidth: 320 * k),
      padding: EdgeInsets.only(left: 16 * k, right: 20 * k),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: IconTheme.merge(
        data: IconThemeData(color: fg, size: 24 * k),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            SizedBox(width: 10 * k),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelLarge.scaled(1.3 * k, color: fg, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalChip extends StatelessWidget {
  const _LocalChip();

  @override
  Widget build(BuildContext context) {
    final k = context.s.clamp(0.9, 1.6);
    final cs = context.cs;
    return Container(
      height: 52 * k,
      padding: EdgeInsets.only(left: 16 * k, right: 20 * k),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tablet_android_rounded, color: cs.primary, size: 22 * k),
          SizedBox(width: 8 * k),
          Text(
            'Reproductor local',
            style: context.tt.labelLarge.scaled(1.3 * k, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// `IconButton.filledTonal` grande (≥ 64 px). Seleccionado → `filled`.
class CarIconButton extends StatelessWidget {
  const CarIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.selectedIcon,
    this.selected = false,
  });
  final IconData icon;
  final IconData? selectedIcon;
  final VoidCallback onTap;
  final String tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = kCarMinTouch * context.s.clamp(1.0, 1.6);
    final style = IconButton.styleFrom(
      fixedSize: Size.square(size),
      minimumSize: Size.square(size),
    );
    final child = Icon(selected ? (selectedIcon ?? icon) : icon);
    return selected
        ? IconButton.filled(
            onPressed: onTap,
            tooltip: tooltip,
            iconSize: size * 0.45,
            style: style,
            icon: child,
          )
        : IconButton.filledTonal(
            onPressed: onTap,
            tooltip: tooltip,
            iconSize: size * 0.45,
            style: style,
            icon: child,
          );
  }
}
