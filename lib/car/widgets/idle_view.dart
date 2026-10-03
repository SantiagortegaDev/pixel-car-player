import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Pantalla de espera: "Esperando al celular…" con instrucciones e IPs.
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
        final art = SizedBox(
          width: math.min(c.maxHeight * 0.78, c.maxWidth * 0.36),
          height: math.min(c.maxHeight * 0.78, c.maxWidth * 0.36),
          child: _RadarIllustration(connected: connected),
        );
        final info = _IdleInfo(status: status, ips: ips, onSettings: onSettings, onDemo: onDemo);
        if (!wide) {
          return SingleChildScrollView(child: Column(children: [art, info]));
        }
        return Row(
          children: [
            Expanded(flex: 4, child: Center(child: art)),
            SizedBox(width: 24 * s),
            Expanded(
              flex: 6,
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 720 * s),
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
    final p = context.palette;
    final connected = status.isConnected;
    final title = connected
        ? 'Conectado a ${status.device ?? 'tu celular'}'
        : 'Esperando al celular…';
    final subtitle = connected
        ? 'Reproduce música en Spotify y aparecerá aquí al instante.'
        : 'La música, la portada y las letras aparecerán aquí en cuanto tu celular se conecte.';

    Widget step(int n, String head, String body) => Padding(
      padding: EdgeInsets.only(bottom: 16 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40 * s,
            height: 40 * s,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [p.accent, p.accentDim]),
            ),
            child: Text(
              '$n',
              style: TextStyle(color: Colors.white, fontSize: 19 * s, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(width: 16 * s),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$head\n',
                    style: TextStyle(
                      color: HarmonixColors.textPrimary,
                      fontSize: 21 * s,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  TextSpan(
                    text: body,
                    style: TextStyle(
                      color: HarmonixColors.textSecondary,
                      fontSize: 17 * s,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
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
          connected ? 'LISTO' : 'PIXEL CAR PLAYER',
          style: TextStyle(
            color: p.accentBright,
            fontSize: 15 * s,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        SizedBox(height: 10 * s),
        Text(
          title,
          style: TextStyle(
            color: HarmonixColors.textPrimary,
            fontSize: 46 * s,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.1,
          ),
        ),
        SizedBox(height: 12 * s),
        Text(
          subtitle,
          style: TextStyle(color: HarmonixColors.textSecondary, fontSize: 20 * s, height: 1.4),
        ),
        SizedBox(height: 28 * s),
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
          SizedBox(height: 8 * s),
        ],
        _IpCard(ips: ips),
        SizedBox(height: 24 * s),
        Wrap(
          spacing: 14 * s,
          runSpacing: 12 * s,
          children: [
            _BigButton(
              icon: Icons.settings_rounded,
              label: 'Ajustes de conexión',
              filled: true,
              onTap: onSettings,
            ),
            _BigButton(icon: Icons.play_circle_outline_rounded, label: 'Ver demo', onTap: onDemo),
          ],
        ),
      ],
    );
  }
}

class _IpCard extends StatelessWidget {
  const _IpCard({required this.ips});
  final List<String> ips;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.palette;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 14 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18 * s),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_rounded, color: p.accentBright, size: 26 * s),
          SizedBox(width: 14 * s),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'IP de esta tableta   ',
                    style: TextStyle(color: HarmonixColors.textSecondary, fontSize: 17 * s),
                  ),
                  TextSpan(
                    text: ips.isEmpty ? 'sin red' : ips.join('  ·  '),
                    style: TextStyle(
                      color: HarmonixColors.textPrimary,
                      fontSize: 20 * s,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final s = context.s.clamp(1.0, 1.6);
    final p = context.palette;
    return Material(
      color: filled ? p.accent : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: kCarMinTouch * s,
          padding: EdgeInsets.symmetric(horizontal: 26 * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 26 * s),
              SizedBox(width: 12 * s),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19 * s,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ilustración: celular en el centro con ondas que se expanden.
class _RadarIllustration extends StatefulWidget {
  const _RadarIllustration({required this.connected});
  final bool connected;

  @override
  State<_RadarIllustration> createState() => _RadarIllustrationState();
}

class _RadarIllustrationState extends State<_RadarIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, c) {
          final d = c.biggest.shortestSide;
          return Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(
                  size: Size.square(d),
                  painter: _RingsPainter(t: _c.value, color: p.accent),
                ),
              ),
              Container(
                width: d * 0.36,
                height: d * 0.36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [p.accentBright, p.accent, p.accentDim],
                  ),
                  boxShadow: [
                    BoxShadow(color: p.accent.withValues(alpha: 0.55), blurRadius: d * 0.12),
                  ],
                ),
                child: Icon(
                  widget.connected ? Icons.phonelink_ring_rounded : Icons.smartphone_rounded,
                  color: Colors.white,
                  size: d * 0.17,
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
  _RingsPainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    final minR = maxR * 0.2;
    // Anillos estáticos tenues.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(c, minR + (maxR - minR) * i / 3.2, guide);
    }
    // Ondas en expansión.
    for (var k = 0; k < 3; k++) {
      final f = (t + k / 3) % 1.0;
      final r = minR + (maxR - minR) * f;
      final a = (1 - f) * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 4 * (1 - f)
          ..color = color.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}
