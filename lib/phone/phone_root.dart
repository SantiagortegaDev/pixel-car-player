import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/appearance_section.dart';
import 'package:pixel_car_player/phone/widgets/auto_start_section.dart';
import 'package:pixel_car_player/phone/widgets/hotspot_card.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';
import 'package:pixel_car_player/phone/widgets/link_diagnostics_card.dart';
import 'package:pixel_car_player/phone/widgets/pairing_dialog.dart';
import 'package:pixel_car_player/phone/widgets/pairing_section.dart';
import 'package:pixel_car_player/phone/widgets/phone_widgets.dart';
import 'package:pixel_car_player/phone/widgets/updates_section.dart';

/// Raíz del modo celular (transmisor), con el aspecto de Harmonix v2: barra de
/// navegación abajo (riel a la izquierda en pantallas anchas), inicio con píldora
/// superior y saludo grande, y Ajustes en tarjetas.
class PhoneRoot extends StatefulWidget {
  const PhoneRoot({
    super.key,
    required this.onChangeMode,
    this.now,
    this.controller,
    this.splash = true,
  });
  final VoidCallback onChangeMode;

  /// Hora para el saludo (por defecto, la actual).
  final DateTime Function()? now;

  /// Controlador a usar (pruebas: para inyectar eventos nativos). Si se pasa, quien lo
  /// creó lo libera.
  final PhoneController? controller;

  /// Pantalla de arranque con la cookie que se transforma.
  final bool splash;

  @override
  State<PhoneRoot> createState() => _PhoneRootState();
}

class _PhoneRootState extends State<PhoneRoot> with WidgetsBindingObserver {
  late final PhoneController _c = widget.controller ?? PhoneController();
  late final bool _owns = widget.controller == null;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tab = 0;
  bool _pairOpen = false;
  bool _themeSettled = false;

  static const _items = [
    HxNavItem(Symbols.home_rounded, 'Inicio'),
    HxNavItem(Symbols.cast_rounded, 'Conexión'),
    HxNavItem(Symbols.settings_rounded, 'Ajustes'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.pairing.addListener(_onPairing);
    _c.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.pairing.removeListener(_onPairing);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si el pedido llegó con la app en segundo plano (el nativo avisó con una
    // notificación), se muestra al volver mientras siga vigente.
    if (state == AppLifecycleState.resumed) _onPairing();
  }

  void _onPairing() {
    if (_pairOpen || !_c.pairing.hasPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPairing());
  }

  Future<void> _showPairing() async {
    if (!mounted || _pairOpen || !_c.pairing.hasPending) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    // Aún en la pantalla de arranque: se reintenta al construir el contenido.
    final ctx = _scaffoldKey.currentContext;
    if (ctx == null) return;
    _pairOpen = true;
    final name = _c.pairing.pending?.carName ?? 'el carro';
    final ok = await showPairingDialog(ctx, _c.pairing);
    _pairOpen = false;
    if (!mounted) return;
    final sctx = _scaffoldKey.currentContext;
    if (ok && sctx != null && sctx.mounted) {
      showHxSnack(
        sctx,
        'Emparejado con «${_c.pairing.lastPairedName ?? name}»',
      );
    }
    // Pudo llegar otro pedido mientras se cerraba.
    _onPairing();
  }

  void _setTab(int i) {
    if (i != _tab) setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c.settings,
    builder: (context, _) {
      final s = _c.settings;
      final mq = MediaQuery.of(context);
      final reduce = s.reduceMotion(mq.disableAnimations);
      final scheme = s.scheme(mq.platformBrightness);
      // Al cargar las preferencias el tema se aplica sin transición (lo tapa la
      // pantalla de arranque); después, los cambios se animan como en Harmonix.
      final instant = reduce || !_themeSettled;
      if (s.loaded && !_themeSettled) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _themeSettled = true,
        );
      }
      final textScaler = s.textScale == 1
          ? mq.textScaler
          : TextScaler.linear(mq.textScaler.scale(16) / 16 * s.textScale);
      final dark = scheme.brightness == Brightness.dark;
      return MediaQuery(
        data: mq.copyWith(disableAnimations: reduce, textScaler: textScaler),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
          child: HxAnimatedTheme(
            scheme: scheme,
            duration: instant ? Duration.zero : HxMotion.dTheme,
            child: HxSplash(
              enabled: widget.splash,
              child: ListenableBuilder(
                listenable: Listenable.merge([_c, _c.pairing]),
                builder: (context, _) => _shell(context),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _shell(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playing = _c.status.session?.playing == true;
    if (_c.pairing.hasPending && !_pairOpen) _onPairing();
    final view = HxSharedAxisSwitcher(
      index: _tab,
      child: KeyedSubtree(
        key: ValueKey(_tab),
        child: switch (_tab) {
          0 => _HomeView(
            c: _c,
            greeting: greetingFor((widget.now ?? DateTime.now)()),
            onChangeMode: widget.onChangeMode,
            onReviewPermissions: () => _setTab(2),
            onOpenUpdates: () => _setTab(2),
          ),
          1 => _ConnectionView(c: _c),
          _ => _SettingsView(c: _c, onChangeMode: widget.onChangeMode),
        },
      ),
    );
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      body: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth <= 700) {
            return Column(
              children: [
                Expanded(child: view),
                HxNavBar(items: _items, index: _tab, onChanged: _setTab),
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
                  onChanged: _setTab,
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
                children: [
                  // Entrada escalonada de títulos y tarjetas al abrir cada pestaña.
                  for (var i = 0; i < children.length; i++)
                    HxEntrance(index: i, child: children[i]),
                ],
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
    required this.onOpenUpdates,
  });
  final PhoneController c;
  final String greeting;
  final VoidCallback onChangeMode;
  final VoidCallback onReviewPermissions;
  final VoidCallback onOpenUpdates;

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
        UpdateBanner(c: c.updates, onOpen: onOpenUpdates),
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
      const SizedBox(height: 24),
      const HxSectionTitle(
        'Hotspot del carro',
        icon: Symbols.wifi_tethering_rounded,
      ),
      HotspotCard(c: c),
      const SizedBox(height: 24),
      const HxSectionTitle(
        'Diagnóstico de conexión',
        icon: Symbols.troubleshoot_rounded,
      ),
      LinkDiagnosticsCard(c: c),
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
      const HxSectionTitle(
        'Encendido automático',
        icon: Symbols.battery_charging_full_rounded,
      ),
      AutoStartSection(c: c),
      const SizedBox(height: 24),
      const HxSectionTitle('Seguridad', icon: Symbols.lock_rounded),
      PairingSection(c: c.pairing),
      const SizedBox(height: 24),
      const HxSectionTitle('Apariencia', icon: Symbols.palette_rounded),
      AppearanceSection(s: c.settings),
      const SizedBox(height: 24),
      const HxSectionTitle(
        'Actualizaciones',
        icon: Symbols.system_update_rounded,
      ),
      UpdatesSection(c: c.updates),
      const SizedBox(height: 24),
      const HxSectionTitle(
        'Copia de seguridad',
        icon: Symbols.settings_backup_restore_rounded,
      ),
      BackupSection(c: c),
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
