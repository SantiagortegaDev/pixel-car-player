import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Pantalla de espera M3: "Esperando al celular…" con pasos e IPs.
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
    final s = context.s;
    final connected = status.isConnected;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.25;
        final d = math.min(c.maxHeight * 0.8, c.maxWidth * 0.34);
        final art = SizedBox.square(dimension: d, child: _HeroIllustration(connected: connected));
        final info = _IdleInfo(status: status, ips: ips, onSettings: onSettings, onDemo: onDemo);
        if (!wide) {
          return SingleChildScrollView(child: Column(children: [art, info]));
        }
        return Row(
          children: [
            Expanded(flex: 4, child: Center(child: art)),
            SizedBox(width: 32 * s),
            Expanded(
              flex: 6,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 760 * s),
                    child: info,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IdleInfo extends StatelessWidget {
  const _IdleInfo({
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
    final s = context.s;
    final k = s.clamp(1.0, 1.6);
    final cs = context.cs;
    final tt = context.tt;
    final connected = status.isConnected;
    final title = connected
        ? 'Conectado a ${status.device ?? 'tu celular'}'
        : 'Esperando al celular…';
    final subtitle = connected
        ? 'Reproduce música en Spotify y aparecerá aquí al instante.'
        : 'La música, la portada y las letras aparecerán aquí en cuanto tu celular se conecte.';

    Widget step(int n, String head, String body) => Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40 * s,
            height: 40 * s,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.secondaryContainer),
            child: Text(
              '$n',
              style: tt.titleMedium.scaled(1.1 * s, color: cs.onSecondaryContainer),
            ),
          ),
          SizedBox(width: 16 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(head, style: tt.titleMedium.scaled(1.2 * s, color: cs.onSurface)),
                SizedBox(height: 2 * s),
                Text(body, style: tt.bodyMedium.scaled(1.15 * s, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          connected ? 'Listo' : 'Pixel Car Player',
          style: tt.titleMedium.scaled(1.15 * s, color: cs.primary),
        ),
        SizedBox(height: 6 * s),
        Text(
          title,
          style: tt.displaySmall.scaled(1.1 * s, color: cs.onSurface, height: 1.15),
        ),
        SizedBox(height: 10 * s),
        Text(subtitle, style: tt.bodyLarge.scaled(1.2 * s, color: cs.onSurfaceVariant)),
        SizedBox(height: 20 * s),
        Card(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 20 * s, 12 * s),
            child: Column(
              children: [
                if (!connected) ...[
                  step(
                    1,
                    'Abre Pixel Car Player en tu celular',
                    'Activa “Transmitir” y deja Spotify sonando.',
                  ),
                  step(
                    2,
                    'Conecta esta tableta al hotspot del celular',
                    'O a la misma red Wi-Fi. También puedes usar Bluetooth en Ajustes.',
                  ),
                  step(3, 'Listo', 'Se conectará sola. No hace falta tocar nada más.'),
                  Divider(height: 20 * s, color: cs.outlineVariant),
                ],
                _IpRow(ips: ips),
              ],
            ),
          ),
        ),
        SizedBox(height: 24 * s),
        Wrap(
          spacing: 12 * s,
          runSpacing: 12 * s,
          children: [
            FilledButton.icon(
              onPressed: onSettings,
              style: _bigButton(context, k),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Ajustes de conexión'),
            ),
            FilledButton.tonalIcon(
              onPressed: onDemo,
              style: _bigButton(context, k),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Ver demo'),
            ),
          ],
        ),
      ],
    );
  }

  ButtonStyle _bigButton(BuildContext context, double k) => FilledButton.styleFrom(
    minimumSize: Size(0, kCarMinTouch * k),
    padding: EdgeInsets.symmetric(horizontal: 28 * k),
    iconSize: 26 * k,
    shape: const StadiumBorder(),
    textStyle: context.tt.labelLarge.scaled(1.35 * k),
  );
}

class _IpRow extends StatelessWidget {
  const _IpRow({required this.ips});
  final List<String> ips;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cs = context.cs;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6 * s),
      child: Row(
        children: [
          SizedBox(
            width: 40 * s,
            child: Icon(Icons.lan_outlined, color: cs.primary, size: 26 * s),
          ),
          SizedBox(width: 16 * s),
          Text('IP de esta tableta', style: tt.bodyMedium.scaled(1.15 * s, color: cs.onSurfaceVariant)),
          SizedBox(width: 16 * s),
          Expanded(
            child: Text(
              ips.isEmpty ? 'sin red' : ips.join('  ·  '),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium
                  .scaled(1.2 * s, color: cs.onSurface)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ilustración: contenedor tonal grande (primaryContainer, esquinas 3xl)
/// con ondas suaves que se expanden mientras busca.
class _HeroIllustration extends StatefulWidget {
  const _HeroIllustration({required this.connected});
  final bool connected;

  @override
  State<_HeroIllustration> createState() => _HeroIllustrationState();
}

class _HeroIllustrationState extends State<_HeroIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, c) {
          final d = c.biggest.shortestSide;
          final box = d * 0.46;
          return Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(
                  size: Size.square(d),
                  painter: _RingsPainter(
                    t: _c.value,
                    wave: cs.primary,
                    guide: cs.outlineVariant,
                    minR: box * 0.62,
                  ),
                ),
              ),
              Material(
                color: cs.primaryContainer,
                elevation: 1,
                shadowColor: cs.shadow,
                borderRadius: BorderRadius.circular(box * 0.3),
                child: SizedBox.square(
                  dimension: box,
                  child: Icon(
                    widget.connected ? Icons.phonelink_ring_rounded : Icons.smartphone_rounded,
                    color: cs.onPrimaryContainer,
                    size: box * 0.46,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.t, required this.wave, required this.guide, required this.minR});
  final double t;
  final Color wave;
  final Color guide;
  final double minR;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = guide.withValues(alpha: 0.5);
    for (var i = 1; i <= 2; i++) {
      canvas.drawCircle(c, minR + (maxR - minR) * i / 2.4, guidePaint);
    }
    for (var k = 0; k < 2; k++) {
      final f = (t + k / 2) % 1.0;
      final r = minR + (maxR - minR) * f;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 4 * (1 - f)
          ..color = wave.withValues(alpha: (1 - f) * 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t || old.wave != wave || old.guide != guide || old.minR != minR;
}
