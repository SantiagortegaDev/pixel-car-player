import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/app_mode.dart';

/// Selección de rol al primer arranque (Material Design 3 / Material You).
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key, required this.onSelected});
  final ValueChanged<AppMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final compactHeight = c.maxHeight < 680;
            final tile = compactHeight ? 72.0 : 96.0;

            final cards = [
              _ModeCard(
                wide: wide,
                icon: Icons.tablet_android_rounded,
                title: 'Pantalla del carro (tableta)',
                description: 'Muestra portada, letras y controles en grande.',
                background: cs.primaryContainer,
                foreground: cs.onPrimaryContainer,
                accent: cs.primary,
                onAccent: cs.onPrimary,
                onTap: () => onSelected(AppMode.car),
              ),
              _ModeCard(
                wide: wide,
                icon: Icons.phone_android_rounded,
                title: 'Transmisor (celular con Spotify)',
                description: 'Lee Spotify y envía todo a la tableta del carro.',
                background: cs.tertiaryContainer,
                foreground: cs.onTertiaryContainer,
                accent: cs.tertiary,
                onAccent: cs.onTertiary,
                onTap: () => onSelected(AppMode.phone),
              ),
            ];

            final header = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: cs.onPrimaryContainer,
                    size: tile * 0.5,
                  ),
                ),
                SizedBox(height: compactHeight ? 16 : 24),
                Text(
                  'Pixel Car Player',
                  style: (wide && !compactHeight)
                      ? t.displaySmall
                      : t.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '¿Qué será este dispositivo? Puedes cambiarlo después '
                  'desde el menú.',
                  style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            );

            final body = wide
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 16),
                        Expanded(child: cards[1]),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cards[0], const SizedBox(height: 12), cards[1]],
                  );

            const pad = EdgeInsets.symmetric(horizontal: 24, vertical: 24);
            return SingleChildScrollView(
              padding: pad,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (c.maxHeight - pad.vertical).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        SizedBox(height: compactHeight ? 24 : 40),
                        body,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.wide,
    required this.icon,
    required this.title,
    required this.description,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.onAccent,
    required this.onTap,
  });
  final bool wide;
  final IconData icon;
  final String title;
  final String description;
  final Color background;
  final Color foreground;
  final Color accent;
  final Color onAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: onAccent, size: 28),
              ),
              const SizedBox(height: 20),
              Text(title, style: t.titleLarge?.copyWith(color: foreground)),
              const SizedBox(height: 6),
              Text(
                description,
                style: t.bodyMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.8),
                ),
              ),
              if (wide) const Spacer() else const SizedBox(height: 20),
              if (wide) const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Elegir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
