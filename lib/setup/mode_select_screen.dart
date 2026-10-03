import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/colors.dart';

/// Selección de rol al primer arranque.
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key, required this.onSelected});
  final ValueChanged<AppMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.9),
            radius: 1.3,
            colors: [
              Color(0xFF14336F),
              HarmonixColors.background,
              HarmonixColors.backgroundDark,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > c.maxHeight && c.maxWidth > 700;
              final cards = [
                _ModeCard(
                  icon: Icons.tablet_android_rounded,
                  title: 'Pantalla del carro (tableta)',
                  description: 'Muestra portada, letras y controles en grande.',
                  colors: const [Color(0xFF4A9EFF), Color(0xFF1B3D85)],
                  onTap: () => onSelected(AppMode.car),
                ),
                _ModeCard(
                  icon: Icons.phone_android_rounded,
                  title: 'Transmisor (celular con Spotify)',
                  description:
                      'Lee Spotify y envía todo a la tableta del carro.',
                  colors: const [Color(0xFF4ADE80), Color(0xFF1E7A45)],
                  onTap: () => onSelected(AppMode.phone),
                ),
              ];
              final header = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HarmonixColors.accentBright,
                          HarmonixColors.accentDim,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: HarmonixColors.accent.withValues(alpha: 0.4),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.directions_car_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Pixel Car Player',
                    style: t.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '¿Qué será este dispositivo?',
                    style: t.bodyLarge?.copyWith(
                      color: HarmonixColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Puedes cambiarlo después desde el menú.',
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              );

              final body = wide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final card in cards)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: card,
                              ),
                            ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (final card in cards)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: card,
                          ),
                      ],
                    );

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight - 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [header, const SizedBox(height: 28), body],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.colors,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: HarmonixColors.surface,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.first.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.first.withValues(alpha: 0.22),
                HarmonixColors.surface,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: colors),
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              Text(title, style: t.titleLarge),
              const SizedBox(height: 6),
              Text(description, style: t.bodyMedium),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Elegir',
                    style: t.labelLarge?.copyWith(color: colors.first),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: colors.first,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
