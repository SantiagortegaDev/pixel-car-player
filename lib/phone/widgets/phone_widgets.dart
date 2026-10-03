import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';

/// Tarjeta base Harmonix.
class PCard extends StatelessWidget {
  const PCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
  });
  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? HarmonixColors.surface : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: HarmonixColors.accentBright),
          const SizedBox(width: 8),
        ],
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

/// Botón grande de transmitir.
class TransmitToggle extends StatelessWidget {
  const TransmitToggle({
    super.key,
    required this.running,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.cars,
  });
  final bool running;
  final bool busy;
  final bool enabled;
  final int cars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final subtitle = !running
        ? (enabled ? 'Toca para empezar a transmitir' : 'Falta dar permisos')
        : (cars > 0
              ? 'Transmitiendo a $cars pantalla${cars == 1 ? '' : 's'}'
              : 'Esperando a la tableta…');
    return PCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: running
            ? const [Color(0xFF1F5FBF), Color(0xFF13316B)]
            : const [HarmonixColors.surfaceVariant, HarmonixColors.surface],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: enabled && !busy
                ? () {
                    HapticFeedback.mediumImpact();
                    onTap();
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: running
                      ? const [
                          HarmonixColors.accentBright,
                          HarmonixColors.accentDim,
                        ]
                      : [
                          HarmonixColors.surfaceContainerHigh,
                          HarmonixColors.surfaceContainer,
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: HarmonixColors.accent.withValues(
                      alpha: running ? 0.5 : 0.1,
                    ),
                    blurRadius: running ? 36 : 12,
                    spreadRadius: running ? 4 : 0,
                  ),
                ],
              ),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Icon(
                      running
                          ? Icons.cast_connected_rounded
                          : Icons.power_settings_new_rounded,
                      size: 62,
                      color: enabled
                          ? Colors.white
                          : HarmonixColors.textDisabled,
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            running ? 'Transmisor activo' : 'Transmisor apagado',
            style: t.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: t.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    this.onFix,
    this.fixLabel = 'Permitir',
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback? onFix;
  final String fixLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = granted ? HarmonixColors.success : HarmonixColors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              granted ? Icons.check_rounded : icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall),
                Text(subtitle, style: t.bodySmall),
              ],
            ),
          ),
          if (!granted && onFix != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onFix,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(fixLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class PermissionsCard extends StatelessWidget {
  const PermissionsCard({super.key, required this.c});
  final PhoneController c;
  @override
  Widget build(BuildContext context) => PCard(
    child: Column(
      children: [
        PermissionRow(
          icon: Icons.notifications_active_outlined,
          title: 'Acceso a notificaciones',
          subtitle: 'Obligatorio: así se lee lo que suena en Spotify',
          granted: c.notificationAccess,
          fixLabel: 'Abrir',
          onFix: c.openNotificationSettings,
        ),
        const Divider(height: 8),
        PermissionRow(
          icon: Icons.bluetooth_rounded,
          title: 'Dispositivos cercanos',
          subtitle: 'Bluetooth para el enlace sin Wi-Fi',
          granted: c.bluetoothPermission,
          onFix: c.requestPermissions,
        ),
        const Divider(height: 8),
        PermissionRow(
          icon: Icons.notifications_none_rounded,
          title: 'Notificaciones',
          subtitle: 'Muestra el aviso del servicio en segundo plano',
          granted: c.notificationsPermission,
          onFix: c.requestPermissions,
        ),
      ],
    ),
  );
}

class SourceSelector extends StatelessWidget {
  const SourceSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SourceApp value;
  final ValueChanged<SourceApp> onChanged;

  static const _icons = {
    SourceApp.spotify: Icons.graphic_eq_rounded,
    SourceApp.youtubeMusic: Icons.smart_display_rounded,
    SourceApp.any: Icons.apps_rounded,
  };

  @override
  Widget build(BuildContext context) => PCard(
    padding: const EdgeInsets.all(14),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in SourceApp.values)
          ChoiceChip(
            selected: s == value,
            showCheckmark: false,
            avatar: Icon(
              _icons[s],
              size: 18,
              color: s == value ? Colors.white : HarmonixColors.textSecondary,
            ),
            label: Text(s.label),
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: s == value ? Colors.white : HarmonixColors.textSecondary,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            onSelected: (_) => onChanged(s),
          ),
      ],
    ),
  );
}

class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.session,
    required this.lyricsStatus,
    required this.running,
  });
  final PhoneSession? session;
  final String? lyricsStatus;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final has = session?.title != null && session!.title!.isNotEmpty;
    final (lyricsLabel, lyricsColor, lyricsIcon) = switch (lyricsStatus) {
      'ok' => (
        'Letras sincronizadas',
        HarmonixColors.success,
        Icons.lyrics_rounded,
      ),
      'loading' => (
        'Buscando letras…',
        HarmonixColors.accentBright,
        Icons.hourglass_top_rounded,
      ),
      'not_found' => (
        'Sin letras',
        HarmonixColors.textSecondary,
        Icons.lyrics_outlined,
      ),
      _ => (
        'Letras: en espera',
        HarmonixColors.textSecondary,
        Icons.lyrics_outlined,
      ),
    };
    return PCard(
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C3AED), HarmonixColors.accent],
              ),
            ),
            child: Icon(
              session?.playing == true
                  ? Icons.equalizer_rounded
                  : Icons.music_note_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  has
                      ? session!.title!
                      : (running ? 'Nada sonando' : 'Transmisor apagado'),
                  style: t.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  has
                      ? (session!.artist ?? '')
                      : 'Reproduce algo en tu app de música',
                  style: t.bodyMedium?.copyWith(
                    color: has ? HarmonixColors.accentBright : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Chip(
                      icon: session?.playing == true
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: session?.playing == true
                          ? 'Reproduciendo'
                          : 'En pausa',
                      color: session?.playing == true
                          ? HarmonixColors.accent
                          : HarmonixColors.textSecondary,
                    ),
                    _Chip(
                      icon: lyricsIcon,
                      label: lyricsLabel,
                      color: lyricsColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class CarsCard extends StatelessWidget {
  const CarsCard({super.key, required this.cars, required this.running});
  final List<ConnectedCar> cars;
  final bool running;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (cars.isEmpty) {
      return PCard(
        child: Row(
          children: [
            const Icon(
              Icons.directions_car_filled_outlined,
              size: 34,
              color: HarmonixColors.textDisabled,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ninguna pantalla conectada', style: t.titleSmall),
                  Text(
                    running
                        ? 'Abre Pixel Car Player en la tableta del carro.'
                        : 'Enciende el transmisor y abre la app en la tableta.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return PCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < cars.length; i++) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: HarmonixColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.tablet_android_rounded,
                      color: HarmonixColors.success,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cars[i].device, style: t.titleSmall),
                        Text(cars[i].address, style: t.bodySmall),
                      ],
                    ),
                  ),
                  Icon(
                    cars[i].isBluetooth
                        ? Icons.bluetooth_connected_rounded
                        : Icons.wifi_rounded,
                    color: HarmonixColors.accentBright,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HelpCard extends StatelessWidget {
  const HelpCard({super.key, required this.ips, required this.port});
  final List<String> ips;
  final int? port;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget tip(IconData i, String s) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, size: 18, color: HarmonixColors.accentBright),
          const SizedBox(width: 10),
          Expanded(child: Text(s, style: t.bodyMedium)),
        ],
      ),
    );
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Si la tableta no me encuentra sola, escribe esta IP en ella:',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 10),
          if (ips.isEmpty)
            Text(
              'Sin red detectada (activa el hotspot o el Wi-Fi)',
              style: t.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ip in ips)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: ip));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Copiado: $ip')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: HarmonixColors.backgroundDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: HarmonixColors.accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            port != null ? '$ip:$port' : ip,
                            style: t.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: HarmonixColors.accentBright,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: HarmonixColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          tip(
            Icons.wifi_tethering_rounded,
            'Enciende el hotspot del celular y conecta la tableta a él (o usen la misma red Wi-Fi).',
          ),
          tip(
            Icons.bluetooth_audio_rounded,
            'Mantén el audio Bluetooth emparejado como siempre: el sonido va por BT, los datos por Wi-Fi.',
          ),
          tip(
            Icons.bluetooth_connected_rounded,
            'Enlace por Bluetooth: empareja ambos equipos y elige este celular en los ajustes de la tableta.',
          ),
        ],
      ),
    );
  }
}
