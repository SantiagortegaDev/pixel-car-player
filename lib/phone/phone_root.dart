import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';
import 'package:pixel_car_player/phone/widgets/phone_widgets.dart';

/// Raíz del modo celular (transmisor), con el aspecto de Harmonix v2: barra de
/// navegación abajo (riel a la izquierda en pantallas anchas), inicio con píldora
/// superior y saludo grande, y Ajustes en tarjetas.
class PhoneRoot extends StatefulWidget {
  const PhoneRoot({super.key, required this.onChangeMode, this.now});
  final VoidCallback onChangeMode;

  /// Hora para el saludo (por defecto, la actual).
  final DateTime Function()? now;

  @override
  State<PhoneRoot> createState() => _PhoneRootState();
}

class _PhoneRootState extends State<PhoneRoot> {
  final _c = PhoneController();
  int _tab = 0;

  static const _items = [
    HxNavItem(Symbols.home_rounded, 'Inicio'),
    HxNavItem(Symbols.cast_rounded, 'Conexión'),
    HxNavItem(Symbols.settings_rounded, 'Ajustes'),
  ];

  @override
  void initState() {
    super.initState();
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeFromSeed(
      AppTheme.fallbackSeed,
      brightness: MediaQuery.platformBrightnessOf(context),
    );
    return HxAnimatedTheme(
      scheme: scheme,
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => _shell(context),
      ),
    );
  }

  Widget _shell(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playing = _c.status.session?.playing == true;
    final view = KeyedSubtree(
      key: ValueKey(_tab),
      child: switch (_tab) {
        0 => _HomeView(
          c: _c,
          greeting: greetingFor((widget.now ?? DateTime.now)()),
          onChangeMode: widget.onChangeMode,
          onReviewPermissions: () => setState(() => _tab = 2),
        ),
        1 => _ConnectionView(c: _c),
        _ => _SettingsView(c: _c, onChangeMode: widget.onChangeMode),
      },
    );
    return Scaffold(
      backgroundColor: cs.surface,
      body: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth <= 700) {
            return Column(
              children: [
                Expanded(child: view),
                HxNavBar(
                  items: _items,
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ],
            );
          }
          // Escritorio / tableta: riel + contenido en surfaceContainerLow redondeado.
          return SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HxNavRail(
                  items: _items,
                  index: _tab,
                  playing: playing,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: HxRadius.xl,
                    ),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: view,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Vista con scroll y el relleno de Harmonix (`.view`): 20 px arriba, 12–32 px a los
/// lados, ancho máximo centrado.
class _View extends StatelessWidget {
  const _View({required this.maxWidth, required this.children});
  final double maxWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, box) {
        final side = (box.maxWidth * 0.03).clamp(12.0, 32.0);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(side, top + 20, side, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.c,
    required this.greeting,
    required this.onChangeMode,
    required this.onReviewPermissions,
  });
  final PhoneController c;
  final String greeting;
  final VoidCallback onChangeMode;
  final VoidCallback onReviewPermissions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final s = c.status;
    final nowPlaying = NowPlayingCard(
      session: s.session,
      lyricsStatus: s.lyricsStatus,
      running: s.running,
      source: c.source,
    );
    final transmit = TransmitCard(
      running: s.running,
      busy: c.busy,
      enabled: c.permissionsOk,
      cars: s.clients.length,
      port: s.port,
      onTap: c.toggle,
    );

    return _View(
      maxWidth: 1100,
      children: [
        HxTopPill(
          leading: HxLogo(playing: s.session?.playing == true),
          title: 'Pixel Car Player',
          trailing: _ModeMenuButton(onChangeMode: onChangeMode),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 40, 4, 28),
          child: Text(
            greeting,
            style: HxType.greeting((w * 0.05).clamp(36.0, 57.0), cs.onSurface),
          ),
        ),
        if (!c.permissionsOk || !c.runtimeOk) ...[
          PermissionsBanner(onReview: onReviewPermissions),
          const SizedBox(height: 28),
        ],
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const HxHomeHeading('Sonando ahora'),
                  nowPlaying,
                  const SizedBox(height: 28),
                  const HxHomeHeading('Transmisión'),
                  transmit,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const HxHomeHeading('Sonando ahora'),
                      nowPlaying,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [const HxHomeHeading('Transmisión'), transmit],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        const HxHomeHeading('Pantallas conectadas'),
        CarsList(cars: s.clients, running: s.running),
      ],
    );
  }
}

/// Menú "más opciones" de la píldora (estilo `.menu` de `TrackRow`).
class _ModeMenuButton extends StatelessWidget {
  const _ModeMenuButton({required this.onChangeMode});
  final VoidCallback onChangeMode;

  Future<void> _open(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: cs.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      menuPadding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 240),
      shape: RoundedRectangleBorder(borderRadius: HxRadius.l),
      items: [
        PopupMenuItem(
          value: 'mode',
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              HxIcon(
                Symbols.swap_horiz_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text('Cambiar modo', style: hxText(15, color: cs.onSurface)),
            ],
          ),
        ),
      ],
    );
    if (v == 'mode') onChangeMode();
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => HxIconButton(
      icon: Symbols.more_vert_rounded,
      tooltip: 'Más opciones',
      iconSize: 24,
      onPressed: () => _open(context),
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 20),
    child: Text(
      title,
      style: HxType.pageTitle(Theme.of(context).colorScheme.onSurface),
    ),
  );
}

class _ConnectionView extends StatelessWidget {
  const _ConnectionView({required this.c});
  final PhoneController c;

  @override
  Widget build(BuildContext context) => _View(
    maxWidth: 760,
    children: [
      const _PageTitle('Conexión'),
      const HxSectionTitle(
        'Pantallas conectadas',
        icon: Symbols.cast_connected_rounded,
      ),
      CarsList(cars: c.status.clients, running: c.status.running),
      const SizedBox(height: 24),
      const HxSectionTitle('Cómo conectar', icon: Symbols.help_rounded),
      HelpItems(ips: c.localIps, port: c.status.port),
    ],
  );
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.c, required this.onChangeMode});
  final PhoneController c;
  final VoidCallback onChangeMode;

  static const _short = {
    SourceApp.spotify: 'Spotify',
    SourceApp.youtubeMusic: 'YT Music',
    SourceApp.any: 'Cualquiera',
  };

  @override
  Widget build(BuildContext context) => _View(
    maxWidth: 760,
    children: [
      const _PageTitle('Ajustes'),
      const HxSectionTitle('Transmisión', icon: Symbols.graphic_eq_rounded),
      HxSettingsCard(
        children: [
          HxSettingsItem(
            label: 'Leer música de',
            description:
                'La app de la que se toman el tema, el artista y si suena.',
            child: HxSegmented<SourceApp>(
              value: c.source,
              onChanged: c.setSource,
              options: [
                for (final s in SourceApp.values) HxSegment(s, _short[s]!),
              ],
            ),
          ),
          HxSwitchRow(
            label: 'Iniciar automáticamente',
            description: 'Al abrir la app, si están los permisos.',
            value: c.autoStart,
            onChanged: c.setAutoStart,
          ),
        ],
      ),
      const SizedBox(height: 24),
      const HxSectionTitle('Permisos', icon: Symbols.verified_user_rounded),
      HxSettingsCard(children: permissionItems(c)),
      const SizedBox(height: 24),
      const HxSectionTitle(
        'Este dispositivo',
        icon: Symbols.phone_android_rounded,
      ),
      HxSettingsCard(
        children: [
          HxSettingsItem(
            label: 'Celular transmisor',
            description: 'Lee la música de este celular y la envía a la tableta del carro.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: HxButton(
                label: 'Cambiar modo',
                kind: HxButtonKind.tonal,
                icon: Symbols.swap_horiz_rounded,
                onPressed: onChangeMode,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
