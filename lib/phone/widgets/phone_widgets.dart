import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Saludo de Harmonix según la hora.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 6) return 'Buenas noches';
  if (h < 13) return 'Buenos días';
  if (h < 20) return 'Buenas tardes';
  return 'Buenas noches';
}

/// Tarjeta de Harmonix (`.card` de "Escuchado hace poco"): surfaceContainer, radio 28.
class HxCard extends StatelessWidget {
  const HxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: HxMotion.dFxSlow,
    curve: HxMotion.standard,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: HxRadius.xl,
    ),
    child: child,
  );
}

/// Ecualizador de `TrackRow .bars` (tres barras que suben y bajan).
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    required this.color,
    this.height = 28,
    this.barWidth = 5,
  });
  final bool playing;
  final Color color;
  final double height;
  final double barWidth;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6300),
  );

  void _sync() {
    final run =
        widget.playing &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final secs = _c.value * 6.3;
      // Duraciones/desfases de TrackRow: 0.9 s, 0.7 s (-0.3), 0.9 s (-0.6), alternadas.
      double v(double dur, double delay) {
        var t = ((secs + delay) / dur) % 2;
        if (t > 1) t = 2 - t;
        return 0.25 + 0.75 * Curves.easeInOut.transform(t);
      }

      final scales = [v(0.9, 0), v(0.7, 0.3), v(0.9, 0.6)];
      return SizedBox(
        height: widget.height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.barWidth * 0.75),
              Container(
                width: widget.barWidth,
                height: widget.height * scales[i],
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(widget.barWidth / 2),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// "Sonando ahora": tarjeta con la portada recortada en cookie9 (como el tema que suena
/// en Harmonix), título, artista y chips de estado.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.session,
    required this.lyricsStatus,
    required this.running,
    required this.source,
  });
  final PhoneSession? session;
  final String? lyricsStatus;
  final bool running;
  final SourceApp source;

  static String appName(String? pkg) => switch (pkg) {
    'com.spotify.music' => 'Spotify',
    'com.google.android.apps.youtube.music' => 'YouTube Music',
    null => '',
    _ => pkg.split('.').last,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = session?.title != null && session!.title!.isNotEmpty;
    final playing = has && session!.playing;
    final (lyricsLabel, lyricsIcon, lyricsOk) = switch (lyricsStatus) {
      'ok' => ('Letras sincronizadas', Symbols.lyrics_rounded, true),
      'loading' => ('Buscando letras…', Symbols.hourglass_top_rounded, false),
      'not_found' => ('Sin letras', Symbols.lyrics_rounded, false),
      _ => ('Letras: en espera', Symbols.lyrics_rounded, false),
    };
    final app = has ? appName(session!.package) : '';

    return HxCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HxShapeTile(
                shape: has ? M3Shape.cookie9 : M3Shape.square,
                size: 96,
                color: has ? cs.primaryContainer : cs.surfaceContainerHighest,
                spin: playing,
                child: playing
                    ? EqualizerBars(
                        playing: true,
                        color: cs.onPrimaryContainer,
                        height: 34,
                        barWidth: 6,
                      )
                    : HxIcon(
                        Symbols.music_note_rounded,
                        size: 40,
                        filled: true,
                        color: has
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
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
                      style: HxType.titleL(cs.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      has
                          ? ((session!.artist ?? '').isEmpty
                                ? 'Artista desconocido'
                                : session!.artist!)
                          : 'Reproduce algo en ${source == SourceApp.any ? 'tu app de música' : source.label}',
                      style: HxType.bodyL(cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (app.isNotEmpty)
                      Text(
                        app,
                        style: HxType.bodyM(cs.onSurfaceVariant),
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HxChip(
                icon: playing
                    ? Symbols.play_arrow_rounded
                    : Symbols.pause_rounded,
                label: playing ? 'Reproduciendo' : 'En pausa',
                on: playing,
              ),
              HxChip(icon: lyricsIcon, label: lyricsLabel, on: lyricsOk),
            ],
          ),
        ],
      ),
    );
  }
}

/// Transmisor: tarjeta con estado y el botón grande estilo "play" de `Controls`.
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
    final subtitle = !running
        ? (enabled ? 'Toca para empezar a transmitir' : 'Faltan permisos')
        : (cars > 0
              ? 'Transmitiendo a $cars pantalla${cars == 1 ? '' : 's'}'
              : 'Esperando a la tableta…');
    final fg = running ? cs.onPrimary : cs.onSurfaceVariant;

    return HxCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
            child: Row(
              children: [
                HxShapeTile(
                  shape: running ? M3Shape.softBurst : M3Shape.circle,
                  size: 56,
                  color: running ? cs.primary : cs.surfaceContainerHighest,
                  spin: running,
                  icon: running
                      ? Symbols.cast_connected_rounded
                      : Symbols.cast_rounded,
                  iconColor: running ? cs.onPrimary : cs.onSurfaceVariant,
                  iconSize: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cambio de estado animado: el texto viejo sale hacia arriba y
                      // el nuevo entra desde abajo (la forma se transforma sola).
                      _StatusText(
                        running ? 'Transmisor activo' : 'Transmisor apagado',
                        style: HxType.titleL(cs.onSurface),
                      ),
                      _StatusText(
                        subtitle,
                        style: HxType.bodyM(cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: HxMotion.dSpring,
            curve: HxMotion.emphasizedDecel,
            alignment: Alignment.topCenter,
            child: !running
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        HxChip(
                          icon: Symbols.tablet_android_rounded,
                          label: '$cars conectada${cars == 1 ? '' : 's'}',
                          on: cars > 0,
                        ),
                        if (port != null)
                          HxChip(
                            icon: Symbols.lan_rounded,
                            label: 'Puerto $port',
                            mono: true,
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: enabled || running ? 1 : 0.38,
            child: HxBigButton(
              checked: running,
              onPressed: (enabled || running) && !busy ? onTap : null,
              child: busy
                  ? HxLoadingIndicator(size: 32, color: fg)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HxIcon(
                          running
                              ? Symbols.stop_rounded
                              : Symbols.play_arrow_rounded,
                          size: 30,
                          filled: true,
                          color: fg,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            running ? 'Detener' : 'Transmitir a la pantalla',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hxText(
                              16,
                              weight: FontWeight.w500,
                              height: 1.3,
                              color: fg,
                            ),
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

/// Texto de estado que cambia con un deslizamiento vertical + fundido.
class _StatusText extends StatelessWidget {
  const _StatusText(this.text, {required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: hxReduceMotion(context) ? Duration.zero : HxMotion.dSpringFast,
    switchInCurve: HxMotion.emphasizedDecel,
    switchOutCurve: HxMotion.emphasizedAccel,
    layoutBuilder: (cur, prev) =>
        Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
    transitionBuilder: (child, a) {
      final incoming = child.key == ValueKey(text);
      return FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0, incoming ? 0.5 : -0.5),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      );
    },
    child: Text(text, key: ValueKey(text), style: style),
  );
}

/// Aviso en el inicio cuando faltan permisos.
class PermissionsBanner extends StatelessWidget {
  const PermissionsBanner({super.key, required this.onReview});
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HxCard(
      color: cs.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          HxIcon(
            Symbols.warning_rounded,
            filled: true,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Faltan permisos para leer la música.',
              style: HxType.bodyM(cs.onErrorContainer),
            ),
          ),
          const SizedBox(width: 8),
          HxButton(label: 'Revisar', onPressed: onReview),
        ],
      ),
    );
  }
}

/// Lista de pantallas conectadas con filas al estilo `TrackRow`.
class CarsList extends StatelessWidget {
  const CarsList({super.key, required this.cars, required this.running});
  final List<ConnectedCar> cars;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (cars.isEmpty) {
      return HxEmptyState(
        icon: Symbols.tablet_android_rounded,
        shape: M3Shape.cookie9,
        title: 'Ninguna pantalla conectada',
        text: running
            ? 'Abre Pixel Car Player en la tableta del carro.'
            : 'Enciende el transmisor y abre la app en la tableta.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cars.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          HxEntrance(
            key: ValueKey('${cars[i].address}/${cars[i].device}'),
            index: i,
            child: HxListRow(
              icon: Symbols.tablet_android_rounded,
              title: cars[i].device,
              subtitle:
                  '${cars[i].isBluetooth ? 'Bluetooth' : 'Wi-Fi'} · ${cars[i].address}'
                  '${cars[i].pairing ? ' · Esperando código' : (cars[i].authenticated == false ? ' · Sin verificar' : '')}',
              current: true,
              trailing: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: HxIcon(
                    cars[i].isBluetooth
                        ? Symbols.bluetooth_connected_rounded
                        : Symbols.wifi_rounded,
                    size: 22,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Fila de permiso (elemento de Ajustes con estado o botón tonal "Conceder").
class PermissionItem extends StatelessWidget {
  const PermissionItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.granted,
    this.onFix,
  });
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) => HxSettingsItem(
    label: title,
    description: subtitle,
    trailing: granted
        ? const HxStatus(
            label: 'Listo',
            icon: Symbols.check_circle_rounded,
            ok: true,
          )
        : HxButton(
            label: 'Conceder',
            kind: HxButtonKind.tonal,
            onPressed: onFix,
          ),
  );
}

List<Widget> permissionItems(PhoneController c) => [
  PermissionItem(
    title: 'Acceso a notificaciones',
    subtitle: 'Obligatorio: así se lee lo que suena.',
    granted: c.notificationAccess,
    onFix: c.openNotificationSettings,
  ),
  PermissionItem(
    title: 'Dispositivos cercanos',
    subtitle: 'Bluetooth para el enlace sin Wi-Fi.',
    granted: c.bluetoothPermission,
    onFix: c.requestPermissions,
  ),
  PermissionItem(
    title: 'Notificaciones',
    subtitle: 'Aviso del servicio en segundo plano.',
    granted: c.notificationsPermission,
    onFix: c.requestPermissions,
  ),
];

/// "Cómo conectar": direcciones como chips (tocar = copiar) y consejos.
class HelpItems extends StatelessWidget {
  const HelpItems({super.key, required this.ips, required this.port});
  final List<String> ips;
  final int? port;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget tip(IconData i, String s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HxIcon(i, size: 22, color: cs.primary),
          const SizedBox(width: 16),
          Expanded(child: Text(s, style: HxType.bodyM(cs.onSurfaceVariant))),
        ],
      ),
    );

    return HxSettingsCard(
      children: [
        HxSettingsItem(
          label: 'Dirección de este celular',
          description: 'Si la tableta no lo encuentra sola, escribe esta dirección en ella.',
          child: ips.isEmpty
              ? Text(
                  'Sin red detectada (activa el hotspot o el Wi-Fi).',
                  style: HxType.bodyM(cs.error),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ip in ips)
                      HxChip(
                        icon: Symbols.content_copy_rounded,
                        label: port != null ? '$ip:$port' : ip,
                        mono: true,
                        tooltip: 'Copiar',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: ip));
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(content: Text('Dirección copiada: $ip')),
                            );
                        },
                      ),
                  ],
                ),
        ),
        tip(
          Symbols.wifi_tethering_rounded,
          'Enciende el hotspot del celular y conecta la tableta a él (o usen la '
          'misma red Wi-Fi).',
        ),
        tip(
          Symbols.bluetooth_audio_rounded,
          'El audio sigue por Bluetooth como siempre; los datos van por Wi-Fi.',
        ),
        tip(
          Symbols.bluetooth_connected_rounded,
          'Enlace por Bluetooth: empareja ambos equipos y elige este celular en '
          'los ajustes de la tableta.',
        ),
      ],
    );
  }
}
