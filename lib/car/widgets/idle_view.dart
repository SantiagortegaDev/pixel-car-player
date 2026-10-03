import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Pantalla de espera con el estado vacío de Harmonix v2 (`EmptyState.svelte`): ícono
/// dentro de una forma MD3 en primaryContainer que gira despacio, título y texto; a la
/// derecha, los pasos en una tarjeta de Ajustes y las IP de la tableta.
class CarIdleView extends StatelessWidget {
  const CarIdleView({
    super.key,
    required this.status,
    required this.ips,
    required this.onSettings,
    required this.onDemo,
  });

  final LinkStatus status;
  final List<String> ips;
  final VoidCallback onSettings;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    final connected = status.isConnected;
    final empty = _Empty(
      icon: connected ? Symbols.phonelink_ring_rounded : Symbols.smartphone_rounded,
      title: connected ? 'Conectado a ${status.device ?? 'tu celular'}' : 'Esperando al celular…',
      text: connected
          ? 'Pon música en el celular y aparecerá aquí al instante.'
          : 'La música, la portada y la letra aparecerán aquí en cuanto tu celular se conecte.',
      actions: [
        HxButton(label: 'Ajustes de conexión', icon: Symbols.settings_rounded, onTap: onSettings, height: 48),
        HxButton(
          label: 'Ver demo',
          icon: Symbols.play_circle_rounded,
          kind: HxButtonKind.tonal,
          onTap: onDemo,
          height: 48,
        ),
      ],
    );
    final card = _Steps(connected: connected, ips: ips);
    return LayoutBuilder(
      builder: (context, c) {
        final pad = (c.maxWidth * 0.04).clamp(20.0, 64.0);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
              child: Row(
                children: [
                  Expanded(child: Center(child: empty)),
                  SizedBox(width: math.min(48, pad)),
                  SizedBox(
                    width: (c.maxWidth * 0.42).clamp(380.0, 560.0),
                    child: Center(child: SingleChildScrollView(child: card)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatefulWidget {
  const _Empty({required this.icon, required this.title, required this.text, required this.actions});
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  State<_Empty> createState() => _EmptyState();
}

class _EmptyState extends State<_Empty> with TickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 24))
    ..repeat();
  late final AnimationController _in = AnimationController(vsync: this, duration: HxMotion.dSpring)..forward();

  @override
  void dispose() {
    _turn.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final a = CurvedAnimation(parent: _in, curve: HxMotion.spring);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.0).animate(a),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _turn,
              child: SizedBox.square(
                dimension: 136,
                child: ClipPath(
                  clipper: M3ShapeClipper(M3Shape.cookie9),
                  child: ColoredBox(
                    color: cs.primaryContainer,
                    child: Center(
                      child: RotationTransition(
                        turns: ReverseAnimation(_turn),
                        child: HxIcon(widget.icon, size: 56, fill: true, color: cs.onPrimaryContainer),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.title, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontSize: 28)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontSize: 17),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: widget.actions),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta tipo SettingsView: título de sección en primary + ítems separados.
class _Steps extends StatelessWidget {
  const _Steps({required this.connected, required this.ips});
  final bool connected;
  final List<String> ips;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    Widget item(IconData icon, String lbl, String desc) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: HxRadius.m),
            child: HxIcon(icon, size: 22, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lbl, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                Text(desc, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    final divider = Divider(height: 1, thickness: 1, color: cs.outlineVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Row(
            children: [
              HxIcon(Symbols.link_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Text('Cómo conectar', style: tt.titleMedium?.copyWith(color: cs.primary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: HxRadius.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected) ...[
                item(
                  Symbols.smartphone_rounded,
                  'Abre Pixel Car Player en el celular',
                  'Activa “Transmitir” y deja la música sonando.',
                ),
                divider,
                item(
                  Symbols.wifi_rounded,
                  'Conecta la tableta al hotspot del celular',
                  'O a la misma red Wi-Fi. También puedes usar Bluetooth en Ajustes.',
                ),
                divider,
                item(Symbols.check_rounded, 'Listo', 'Se conectará sola; no hace falta tocar nada más.'),
                divider,
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('IP de esta tableta', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    Flexible(
                      flex: 2,
                      child: Text(
                        ips.isEmpty ? 'sin red' : ips.join('  ·  '),
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.numStyle(context, size: 16).copyWith(color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
