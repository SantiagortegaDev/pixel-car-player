import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';

/// Widgets del modo celular — Material Design 3 / Material You estricto.
///
/// Todo el color sale de `Theme.of(context).colorScheme` (dinámico).

/// Encabezado de sección estilo M3 (labelLarge en primary).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: cs.primary),
      ),
    );
  }
}

/// Mosaico de icono tonal (círculo o cuadrado redondeado).
class TonalIcon extends StatelessWidget {
  const TonalIcon({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 40,
    this.iconSize,
    this.radius,
  });
  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final double? iconSize;

  /// `null` = círculo.
  final double? radius;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: radius == null ? null : BorderRadius.circular(radius!),
    ),
    child: Icon(icon, color: foreground, size: iconSize ?? size * 0.55),
  );
}

/// Tarjeta héroe del transmisor.
class TransmitCard extends StatelessWidget {
  const TransmitCard({
    super.key,
    required this.running,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.cars,
    this.port,
  });
  final bool running;
  final bool busy;
  final bool enabled;
  final int cars;
  final int? port;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = running ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = running ? cs.onPrimaryContainer : cs.onSurface;
    final fgVariant = running
        ? cs.onPrimaryContainer.withValues(alpha: 0.8)
        : cs.onSurfaceVariant;
    final subtitle = !running
        ? (enabled ? 'Toca para empezar a transmitir' : 'Falta dar permisos')
        : (cars > 0
              ? 'Transmitiendo a $cars pantalla${cars == 1 ? '' : 's'}'
              : 'Esperando a la tableta…');

    void tap() {
      HapticFeedback.mediumImpact();
      onTap();
    }

    final onPressed = enabled && !busy ? tap : null;
    final Widget icon = busy
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: cs.onPrimary,
            ),
          )
        : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded);
    final label = Text(
      running ? 'Detener transmisión' : 'Empezar a transmitir',
    );

    return Card(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TonalIcon(
                  icon: running
                      ? Icons.cast_connected_rounded
                      : Icons.cast_rounded,
                  background: running ? cs.primary : cs.secondaryContainer,
                  foreground: running ? cs.onPrimary : cs.onSecondaryContainer,
                  size: 64,
                  radius: 20,
                  iconSize: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running ? 'Transmisor activo' : 'Transmisor apagado',
                        style: t.headlineSmall?.copyWith(color: fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: t.bodyMedium?.copyWith(color: fgVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.tablet_android_rounded,
                    label: '$cars conectada${cars == 1 ? '' : 's'}',
                  ),
                  if (port != null)
                    _InfoPill(icon: Icons.lan_rounded, label: 'Puerto $port'),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                icon: icon,
                label: label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onPrimaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

/// "Iniciar automáticamente" como SwitchListTile dentro de una Card.
class AutoStartCard extends StatelessWidget {
  const AutoStartCard({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded)
              : null,
        ),
        secondary: TonalIcon(
          icon: Icons.bolt_rounded,
          background: cs.secondaryContainer,
          foreground: cs.onSecondaryContainer,
        ),
        title: const Text('Iniciar automáticamente'),
        subtitle: const Text('Al abrir la app, si están los permisos'),
      ),
    );
  }
}

/// Selector de app de origen: SegmentedButton M3.
class SourceSelector extends StatelessWidget {
  const SourceSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final SourceApp value;
  final ValueChanged<SourceApp> onChanged;

  static const _meta = {
    SourceApp.spotify: ('Spotify', Icons.graphic_eq_rounded),
    SourceApp.youtubeMusic: ('YT Music', Icons.smart_display_rounded),
    SourceApp.any: ('Cualquiera', Icons.apps_rounded),
  };

  @override
  Widget build(BuildContext context) => SegmentedButton<SourceApp>(
    expandedInsets: EdgeInsets.zero,
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    segments: [
      for (final s in SourceApp.values)
        ButtonSegment(
          value: s,
          icon: Icon(_meta[s]!.$2),
          label: Text(_meta[s]!.$1, maxLines: 1, softWrap: false),
          tooltip: s.label,
        ),
    ],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

/// Sonando ahora.
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
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final has = session?.title != null && session!.title!.isNotEmpty;
    final playing = session?.playing == true;
    final (lyricsLabel, lyricsIcon, lyricsOk) = switch (lyricsStatus) {
      'ok' => ('Letras sincronizadas', Icons.lyrics_rounded, true),
      'loading' => ('Buscando letras…', Icons.hourglass_top_rounded, false),
      'not_found' => ('Sin letras', Icons.lyrics_outlined, false),
      _ => ('Letras: en espera', Icons.lyrics_outlined, false),
    };

    Widget chip({
      required IconData icon,
      required String label,
      required Color bg,
      required Color fg,
    }) => Chip(
      avatar: Icon(icon, color: fg, size: 18),
      label: Text(label),
      labelStyle: t.labelLarge?.copyWith(color: fg),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TonalIcon(
                  icon: playing
                      ? Icons.equalizer_rounded
                      : Icons.music_note_rounded,
                  background: cs.primaryContainer,
                  foreground: cs.onPrimaryContainer,
                  size: 80,
                  radius: 20,
                  iconSize: 36,
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
                        style: t.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        has
                            ? (session!.artist ?? '')
                            : 'Reproduce algo en tu app de música',
                        style: t.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(
                  icon: playing
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: playing ? 'Reproduciendo' : 'En pausa',
                  bg: playing ? cs.secondaryContainer : cs.surfaceContainerHigh,
                  fg: playing ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                ),
                chip(
                  icon: lyricsIcon,
                  label: lyricsLabel,
                  bg: lyricsOk ? cs.tertiaryContainer : cs.surfaceContainerHigh,
                  fg: lyricsOk ? cs.onTertiaryContainer : cs.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionTile extends StatelessWidget {
  const PermissionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    this.onFix,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: TonalIcon(
        icon: icon,
        background: granted ? cs.primaryContainer : cs.errorContainer,
        foreground: granted ? cs.onPrimaryContainer : cs.onErrorContainer,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? Icon(Icons.check_circle_rounded, color: cs.primary)
          : FilledButton.tonal(
              onPressed: onFix,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              child: const Text('Conceder'),
            ),
    );
  }
}

class PermissionsCard extends StatelessWidget {
  const PermissionsCard({super.key, required this.c});
  final PhoneController c;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          PermissionTile(
            icon: Icons.notifications_active_rounded,
            title: 'Acceso a notificaciones',
            subtitle: 'Obligatorio: así se lee lo que suena',
            granted: c.notificationAccess,
            onFix: c.openNotificationSettings,
          ),
          PermissionTile(
            icon: Icons.bluetooth_rounded,
            title: 'Dispositivos cercanos',
            subtitle: 'Bluetooth para el enlace sin Wi-Fi',
            granted: c.bluetoothPermission,
            onFix: c.requestPermissions,
          ),
          PermissionTile(
            icon: Icons.notifications_rounded,
            title: 'Notificaciones',
            subtitle: 'Aviso del servicio en segundo plano',
            granted: c.notificationsPermission,
            onFix: c.requestPermissions,
          ),
        ],
      ),
    ),
  );
}

class CarsCard extends StatelessWidget {
  const CarsCard({super.key, required this.cars, required this.running});
  final List<ConnectedCar> cars;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (cars.isEmpty) {
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: TonalIcon(
            icon: Icons.tablet_android_rounded,
            background: cs.surfaceContainerHighest,
            foreground: cs.onSurfaceVariant,
          ),
          title: const Text('Ninguna pantalla conectada'),
          subtitle: Text(
            running
                ? 'Abre Pixel Car Player en la tableta del carro.'
                : 'Enciende el transmisor y abre la app en la tableta.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (var i = 0; i < cars.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              ListTile(
                tileColor: cs.secondaryContainer,
                textColor: cs.onSecondaryContainer,
                iconColor: cs.onSecondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: TonalIcon(
                  icon: Icons.tablet_android_rounded,
                  background: cs.secondary,
                  foreground: cs.onSecondary,
                ),
                title: Text(cars[i].device),
                subtitle: Text(
                  '${cars[i].isBluetooth ? 'Bluetooth' : 'Wi-Fi'} · '
                  '${cars[i].address}',
                ),
                trailing: Icon(
                  cars[i].isBluetooth
                      ? Icons.bluetooth_connected_rounded
                      : Icons.wifi_rounded,
                ),
              ),
            ],
          ],
        ),
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
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    Widget tip(IconData i, String s) => ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 6,
      leading: TonalIcon(
        icon: i,
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        size: 36,
      ),
      title: Text(s, style: t.bodyMedium),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Si la tableta no encuentra este celular sola, escribe esta '
              'dirección en ella:',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (ips.isEmpty)
              Text(
                'Sin red detectada (activa el hotspot o el Wi-Fi)',
                style: t.bodySmall?.copyWith(color: cs.error),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ip in ips)
                    ActionChip(
                      avatar: Icon(Icons.copy_rounded, color: cs.primary),
                      label: Text(port != null ? '$ip:$port' : ip),
                      labelStyle: t.labelLarge?.copyWith(
                        color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      tooltip: 'Copiar',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ip));
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Copiado: $ip')));
                      },
                    ),
                ],
              ),
            const SizedBox(height: 8),
            tip(
              Icons.wifi_tethering_rounded,
              'Enciende el hotspot del celular y conecta la tableta a él '
              '(o usen la misma red Wi-Fi).',
            ),
            tip(
              Icons.bluetooth_audio_rounded,
              'El audio sigue por Bluetooth como siempre; los datos van por '
              'Wi-Fi.',
            ),
            tip(
              Icons.bluetooth_connected_rounded,
              'Enlace por Bluetooth: empareja ambos equipos y elige este '
              'celular en los ajustes de la tableta.',
            ),
          ],
        ),
      ),
    );
  }
}
