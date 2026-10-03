import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/background_shapes.dart';
import 'package:pixel_car_player/car/widgets/controls.dart';
import 'package:pixel_car_player/car/widgets/disc.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/idle_view.dart';
import 'package:pixel_car_player/car/widgets/lyrics.dart';
import 'package:pixel_car_player/car/widgets/queue_list.dart';
import 'package:pixel_car_player/car/widgets/wavy_slider.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';
import 'package:provider/provider.dart';

/// Escala de toda la pantalla en tableras grandes: el diseño se calcula como Harmonix
/// en un viewport de `tamaño / k` y se agranda `k` veces (1 hasta ≈1400×800).
double carScaleFor(Size size) => math.min(size.width / 1400, size.height / 800).clamp(1.0, 1.6).toDouble();

/// Dibuja [builder] en un viewport virtual de `tamaño / k` (k = [carScaleFor] × [uiScale])
/// y lo agranda/achica `k` veces, para que todo crezca por igual.
class CarScaler extends StatelessWidget {
  const CarScaler({super.key, required this.builder, this.uiScale = 1});
  final Widget Function(BuildContext context, Size size) builder;

  /// "Escala de la interfaz" de Configuración → Diseño.
  final double uiScale;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final k = carScaleFor(c.biggest) * uiScale;
      final w = c.maxWidth / k, h = c.maxHeight / k;
      final mq = MediaQuery.of(context);
      Widget page = MediaQuery(
        data: mq.copyWith(
          size: Size(w, h),
          padding: mq.padding / k,
          viewPadding: mq.viewPadding / k,
          viewInsets: mq.viewInsets / k,
        ),
        child: SizedBox(
          width: w,
          height: h,
          child: Builder(builder: (context) => builder(context, Size(w, h))),
        ),
      );
      if (k != 1) {
        // El body del Scaffold llega con restricciones flojas: hay que forzar el
        // tamaño completo para que FittedBox escale en vez de encogerse al hijo.
        page = SizedBox(
          width: c.maxWidth,
          height: c.maxHeight,
          child: FittedBox(fit: BoxFit.fill, alignment: Alignment.topLeft, child: page),
        );
      }
      return page;
    },
  );
}

/// Pantalla de la tableta = vista "Reproduciendo" de Harmonix v2 (`NowPlaying.svelte`):
/// BackgroundShapes · Disc | detalles (títulos, slider ondulado, ButtonRow, chips) |
/// Letra / A continuación. El tema sale de la portada (o del color fijo) y se anima 900 ms.
///
/// Todo se personaliza en vivo desde Configuración (`controller.cfg`): cualquier elemento
/// se puede ocultar y la disposición se reacomoda. Mantener presionado el fondo abre
/// Configuración (por si se ocultó el botón).
class CarPlayerScreen extends StatefulWidget {
  const CarPlayerScreen({
    super.key,
    required this.onSettings,
    this.initialLyricsFullscreen = false,
    this.preview = false,
  });

  /// Abre los ajustes. Recibe un `context` que ya tiene el tema de la carátula.
  final void Function(BuildContext themedContext) onSettings;
  final bool initialLyricsFullscreen;

  /// Vista previa dentro de Configuración (sin gestos).
  final bool preview;

  @override
  State<CarPlayerScreen> createState() => _CarPlayerScreenState();
}

class _CarPlayerScreenState extends State<CarPlayerScreen> {
  late bool _lyricsFullscreen = widget.initialLyricsFullscreen;
  String _tab = 'lyrics';

  void _toggleLyrics() => setState(() => _lyricsFullscreen = !_lyricsFullscreen);

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CarController>();
    final cfg = ctrl.cfg;
    return CarCustomScope(
      value: cfg,
      child: HxAnimatedTheme(
        scheme: ctrl.schemeFor(MediaQuery.platformBrightnessOf(context)),
        child: Builder(
          builder: (themed) {
            final cs = themed.cs;
            final np = ctrl.nowPlaying;
            final hasTrack = np.track != null;
            final fullscreen = _lyricsFullscreen && hasTrack;
            final mode = !hasTrack ? 'idle' : (fullscreen ? 'lyrics' : 'player');
            void openSettings() => widget.onSettings(themed);
            final showHeader = cfg.show(CarElement.header) || mode == 'lyrics';
            return Scaffold(
              backgroundColor: cs.surface,
              body: CarScaler(
                uiScale: cfg.design.uiScale,
                builder: (context, size) {
                  final w = size.width;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cfg.show(CarElement.backgroundShapes) && cfg.design.shapesCount > 0)
                        BackgroundShapes(
                          playing: hasTrack && np.playing,
                          count: cfg.design.shapesCount,
                          opacity: cfg.design.shapesOpacity,
                          animate: cfg.design.shapesAnimate,
                          minSize: w < 700 ? 36 : 56,
                          maxSize: w < 700 ? 124 : 220,
                        ),
                      // Mantener presionado cualquier parte vacía del fondo = Configuración.
                      if (!widget.preview)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const ValueKey('car-background'),
                            behavior: HitTestBehavior.opaque,
                            onLongPress: openSettings,
                          ),
                        ),
                      SafeArea(
                        child: Column(
                          children: [
                            if (showHeader)
                              _Header(
                                mode: mode,
                                cfg: cfg,
                                status: ctrl.displayStatus,
                                demo: ctrl.demo,
                                onLeft: hasTrack ? _toggleLyrics : null,
                                onSettings: openSettings,
                              ),
                            Expanded(
                              child: HxTextIn(
                                key: ValueKey(mode),
                                offset: 0,
                                child: switch (mode) {
                                  'idle' => CarIdleView(
                                    status: ctrl.displayStatus,
                                    ips: ctrl.tabletIps,
                                    onSettings: openSettings,
                                    onDemo: () => ctrl.setDemo(true),
                                    onConnect: ctrl.linkRunning || ctrl.demo ? null : ctrl.connectNow,
                                  ),
                                  'lyrics' => _FullscreenLyrics(
                                    ctrl: ctrl,
                                    np: np,
                                    size: size,
                                    headerH: showHeader ? 60 : 0,
                                  ),
                                  _ => _Stage(
                                    ctrl: ctrl,
                                    np: np,
                                    size: size,
                                    headerH: showHeader ? 60 : 0,
                                    tab: _tab,
                                    onTab: (t) => setState(() => _tab = t),
                                    onFullscreen: _toggleLyrics,
                                  ),
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado

class _Header extends StatelessWidget {
  const _Header({
    required this.mode,
    required this.cfg,
    required this.status,
    required this.demo,
    required this.onLeft,
    required this.onSettings,
  });

  final String mode;
  final CarCustomization cfg;
  final LinkStatus status;
  final bool demo;
  final VoidCallback? onLeft;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (IconData icon, String tip, String title) = switch (mode) {
      'lyrics' => (Symbols.keyboard_arrow_down_rounded, 'Volver al reproductor', cfg.text(CarText.headerLyrics)),
      'player' => (Symbols.lyrics_rounded, 'Letra en pantalla completa', cfg.text(CarText.headerPlayer)),
      _ => (Symbols.directions_car_rounded, 'Pixel Car Player', cfg.text(CarText.headerIdle)),
    };
    final full = cfg.show(CarElement.header);
    // En la letra a pantalla completa el botón para volver se ve siempre.
    final showLeft = mode == 'lyrics' || (full && cfg.show(CarElement.headerLeft));
    final showTitle = full && cfg.show(CarElement.headerLabel) && title.isNotEmpty;
    final showClock = full && cfg.show(CarElement.clock);
    final showChip = full && cfg.show(CarElement.statusChip);
    final showSettings = full && cfg.show(CarElement.settingsButton);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (showLeft)
              if (onLeft != null)
                HxIconButton(icon: icon, tooltip: tip, onTap: onLeft)
              else
                SizedBox.square(
                  dimension: 48,
                  child: Center(child: HxIcon(icon, color: cs.onSurfaceVariant)),
                ),
            if (showLeft && showTitle) const SizedBox(width: 4),
            Expanded(
              child: showTitle
                  ? Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                    )
                  : const SizedBox.shrink(),
            ),
            if (showClock) ...[const _Clock(), const SizedBox(width: 12)],
            if (showChip) ...[_StatusChip(status: status, demo: demo, onTap: onSettings), const SizedBox(width: 8)],
            if (showSettings) HxIconButton(icon: Symbols.settings_rounded, tooltip: 'Ajustes', onTap: onSettings),
          ],
        ),
      ),
    );
  }
}

/// Reloj del encabezado (HH:MM, se actualiza al cambiar el minuto).
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _t = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond + 50), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Text(text, style: AppTheme.numStyle(context, size: 18).copyWith(color: context.cs.onSurface));
  }
}

/// Estado de la conexión con el celular, con el estilo de los chips de Harmonix.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.demo, required this.onTap});
  final LinkStatus status;
  final bool demo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfg = CarCustomScope.of(context);
    final (IconData icon, String label) = switch (status.phase) {
      LinkPhase.connected => (
        status.transport == 'bt' ? Symbols.bluetooth_rounded : Symbols.wifi_rounded,
        '${(status.device ?? 'Celular').replaceAll(' (demo)', '')} · '
            '${demo
                ? 'Demo'
                : status.transport == 'bt'
                ? 'Bluetooth'
                : 'Wi-Fi'}',
      ),
      LinkPhase.searching => (Symbols.wifi_tethering_rounded, cfg.text(CarText.statusSearching)),
      LinkPhase.disconnected => (Symbols.link_off_rounded, cfg.text(CarText.statusOff)),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return HxChip(icon: icon, label: label, on: status.isConnected, onTap: onTap, maxWidth: 280);
  }
}

// ---------------------------------------------------------------------------
// Reproductor (hasta 3 columnas)

/// Tamaños de las columnas del `.stage` de NowPlaying para un viewport [w]×[h].
/// Una columna oculta mide 0 y las demás se reparten / centran el espacio.
class StageLayout {
  StageLayout._(this.pad, this.gap, this.disc, this.details, this.side, this.stageH, this.sideH);
  final double pad, gap, disc, details, side, stageH;

  /// Alto del panel lateral (letra / cola).
  final double sideH;

  factory StageLayout.of(
    Size size, {
    bool cover = true,
    bool details = true,
    bool side = true,
    double coverScale = 1,
    double headerH = 60,
  }) {
    final w = size.width, h = size.height;
    final stageW = math.min(1600.0, w);
    final pad = (w * 0.04).clamp(20.0, 64.0);
    final avail = stageW - pad * 2;
    final stageH = math.max(0.0, h - headerH - 12 - 32);
    final wide = w >= 1100;
    final gap = wide ? 48.0 : 32.0;
    final sideH = math.min(560.0, stageH);

    if (cover && details && side) {
      if (wide) {
        // grid: auto | minmax(300px, 440px) | minmax(280px, 1fr), gap 48.
        var disc = math.min(460.0, h - 180) * coverScale;
        disc = math.min(disc, math.max(220.0, avail - gap * 2 - 300 - 280));
        disc = math.min(disc, stageH);
        final rest = avail - disc - gap * 2;
        final det = (rest - 280).clamp(300.0, 440.0);
        return StageLayout._(pad, gap, disc, det, rest - det, stageH, sideH);
      }
      // Más angosto (1024×600): las tres columnas siguen visibles, más compactas.
      var disc = math.max(200.0, math.min(math.min(360.0, h - 180) * coverScale, avail - gap * 2 - 280 - 280));
      disc = math.min(disc, stageH);
      final rest = avail - disc - gap * 2;
      final det = (rest - 280).clamp(280.0, 400.0);
      return StageLayout._(pad, gap, disc, det, rest - det, stageH, sideH);
    }

    // Menos columnas: lo visible se agranda y el conjunto se centra.
    final n = [cover, details, side].where((v) => v).length;
    final gaps = gap * math.max(0, n - 1);
    final minDetails = wide ? 300.0 : 280.0;
    const minSide = 280.0;
    double disc = 0, det = 0, sd = 0;
    if (cover) {
      final base = n == 1 ? stageH : math.min(wide ? 520.0 : 400.0, h - 160);
      final reserve = (details ? minDetails : 0) + (side ? minSide : 0) + gaps;
      disc = (base * coverScale).clamp(140.0, math.max(140.0, math.min(stageH, avail - reserve)));
    }
    final rest = math.max(0.0, avail - disc - gaps);
    if (details && side) {
      det = (rest * 0.48).clamp(minDetails, 520.0);
      sd = math.min(rest - det, 760.0);
    } else if (details) {
      det = math.min(rest, cover ? 560.0 : 640.0);
    } else if (side) {
      sd = math.min(rest, cover ? 720.0 : 900.0);
    }
    return StageLayout._(pad, gap, disc, det, sd, stageH, side && !details && !cover ? stageH : sideH);
  }
}

/// Elementos de la columna central.
const _detailElements = [
  CarElement.title,
  CarElement.artist,
  CarElement.album,
  CarElement.progress,
  CarElement.times,
  CarElement.shuffle,
  CarElement.previous,
  CarElement.playPause,
  CarElement.next,
  CarElement.repeat,
];

/// Pestañas visibles del panel lateral.
List<String> _tabsFor(CarCustomization cfg) => [
  if (cfg.show(CarElement.lyricsTab)) 'lyrics',
  if (cfg.show(CarElement.queueTab)) 'queue',
];

bool _chipsVisible(CarCustomization cfg, bool keepOn) =>
    cfg.show(CarElement.chips) &&
    ((cfg.show(CarElement.chipFullscreen) && cfg.text(CarText.chipFullscreen).isNotEmpty) ||
        (cfg.show(CarElement.chipKeepOn) && cfg.text(keepOn ? CarText.chipKeepOn : CarText.chipKeepOff).isNotEmpty));

class _Stage extends StatelessWidget {
  const _Stage({
    required this.ctrl,
    required this.np,
    required this.size,
    required this.headerH,
    required this.tab,
    required this.onTab,
    required this.onFullscreen,
  });

  final CarController ctrl;
  final NowPlaying np;
  final Size size;
  final double headerH;
  final String tab;
  final ValueChanged<String> onTab;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    final tabs = _tabsFor(cfg);
    final showCover = cfg.show(CarElement.cover);
    final showSide = cfg.show(CarElement.sidePanel) && tabs.isNotEmpty;
    final showDetails = cfg.visibility.any(_detailElements) || _chipsVisible(cfg, ctrl.prefs.keepScreenOn);
    final l = StageLayout.of(
      size,
      cover: showCover,
      details: showDetails,
      side: showSide,
      coverScale: cfg.cover.scale,
      headerH: headerH,
    );
    final titleSize = (size.width * 0.024).clamp(28.0, 36.0) * cfg.design.titleScale;
    final columns = <Widget>[
      if (showCover)
        SizedBox(
          width: l.disc,
          child: Center(
            child: _CoverGestures(ctrl: ctrl, child: _disc(cfg, l.disc)),
          ),
        ),
      if (showDetails)
        SizedBox(
          width: l.details,
          // Red de seguridad: con textos/controles muy grandes la columna se achica en vez
          // de desbordar (en el carro no hay scroll).
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: l.stageH),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: l.details,
                child: _Details(ctrl: ctrl, np: np, titleSize: titleSize, onFullscreen: onFullscreen),
              ),
            ),
          ),
        ),
      if (showSide)
        SizedBox(
          width: l.side,
          height: l.sideH,
          child: _Side(
            ctrl: ctrl,
            np: np,
            tabs: tabs,
            tab: tabs.contains(tab) ? tab : tabs.first,
            onTab: onTab,
            lyricSize: (size.width * 0.015).clamp(18.0, 22.0) * cfg.lyrics.scale,
          ),
        ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: EdgeInsets.fromLTRB(l.pad, 12, l.pad, 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < columns.length; i++) ...[if (i > 0) SizedBox(width: l.gap), columns[i]],
            ],
          ),
        ),
      ),
    );
  }

  Widget _disc(CarCustomization cfg, double size) => Disc(
    artwork: np.artwork,
    size: size,
    playing: np.playing,
    cover: cfg.cover,
    viz: cfg.visualizer,
    showBars: cfg.show(CarElement.visualizer),
  );
}

/// Gestos opcionales sobre la portada: tocar = reproducir/pausar, deslizar = siguiente/anterior.
class _CoverGestures extends StatelessWidget {
  const _CoverGestures({required this.ctrl, required this.child});
  final CarController ctrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = ctrl.cfg.gestures;
    if (!g.tapCover && !g.swipeCover) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: g.tapCover ? ctrl.toggle : null,
      onHorizontalDragEnd: g.swipeCover
          ? (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 250) return;
              v < 0 ? ctrl.next() : ctrl.previous();
            }
          : null,
      child: child,
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.track, required this.titleSize, this.compact = false});
  final TrackInfo track;
  final double titleSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final cfg = CarCustomScope.of(context);
    final k = cfg.design.titleScale;
    final sub = hxWeight(tt.titleLarge, 400).copyWith(fontSize: (compact ? 20 : 22) * k);
    final artist = track.artist.isEmpty ? cfg.text(CarText.unknownArtist) : track.artist;
    final album = track.album.isEmpty ? cfg.text(CarText.unknownAlbum) : track.album;
    final lines = <Widget>[
      if (cfg.show(CarElement.title))
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.headlineLarge?.copyWith(fontSize: titleSize, letterSpacing: -0.01 * titleSize, color: cs.onSurface),
        ),
      if (cfg.show(CarElement.artist) && artist.isNotEmpty)
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sub.copyWith(color: cs.onSurfaceVariant),
        ),
      if (cfg.show(CarElement.album) && album.isNotEmpty)
        Text(
          album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sub.copyWith(color: cs.secondary, fontSize: (compact ? 16 : 18) * k),
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    // `{#key t.video_id}` + `text-in`.
    return HxTextIn(
      key: ValueKey(track.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++) ...[if (i > 0) const SizedBox(height: 4), lines[i]],
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.ctrl, required this.np});
  final CarController ctrl;
  final NowPlaying np;

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    final num = AppTheme.numStyle(context);
    final dur = np.track?.duration ?? Duration.zero;
    final times = cfg.show(CarElement.times);
    return Row(
      children: [
        if (times) ...[
          SizedBox(
            width: 44,
            child: ValueListenableBuilder<Duration>(
              valueListenable: ctrl.position,
              builder: (_, p, _) => Text(formatDuration(p), textAlign: TextAlign.center, style: num),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: HxWavySlider(
            position: () => ctrl.nowPlaying.livePosition(),
            duration: dur,
            playing: np.playing,
            onSeek: ctrl.seek,
            waveAmplitude: cfg.design.wavy ? cfg.design.waveAmplitude : 0,
          ),
        ),
        if (times) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(formatDuration(dur), textAlign: TextAlign.center, style: num),
          ),
        ],
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.ctrl, required this.np});
  final CarController ctrl;
  final NowPlaying np;

  static bool anyVisible(CarCustomization cfg) => cfg.visibility.any(const [
    CarElement.shuffle,
    CarElement.previous,
    CarElement.playPause,
    CarElement.next,
    CarElement.repeat,
  ]);

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    void hint() {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Aleatorio y repetir se cambian desde el celular.'),
            duration: Duration(seconds: 3),
          ),
        );
    }

    final h = cfg.design.controlHeight;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: HxControls.maxWidthFor(h)),
      child: HxControls(
        playing: np.playing,
        onToggle: ctrl.toggle,
        onPrevious: ctrl.previous,
        onNext: ctrl.next,
        onShuffle: hint,
        onRepeat: hint,
        height: h,
        showShuffle: cfg.show(CarElement.shuffle),
        showPrevious: cfg.show(CarElement.previous),
        showPlay: cfg.show(CarElement.playPause),
        showNext: cfg.show(CarElement.next),
        showRepeat: cfg.show(CarElement.repeat),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.ctrl, required this.np, required this.titleSize, required this.onFullscreen});
  final CarController ctrl;
  final NowPlaying np;
  final double titleSize;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    final keepOn = ctrl.prefs.keepScreenOn;
    final hasTitles = cfg.visibility.any(const [CarElement.title, CarElement.artist, CarElement.album]);
    final fullLabel = cfg.text(CarText.chipFullscreen);
    final keepLabel = cfg.text(keepOn ? CarText.chipKeepOn : CarText.chipKeepOff);
    final chips = <Widget>[
      if (cfg.show(CarElement.chipFullscreen) && fullLabel.isNotEmpty)
        HxChip(icon: Symbols.fullscreen_rounded, label: fullLabel, onTap: onFullscreen),
      if (cfg.show(CarElement.chipKeepOn) && keepLabel.isNotEmpty)
        HxChip(
          icon: Symbols.light_mode_rounded,
          label: keepLabel,
          on: keepOn,
          onTap: () => ctrl.setKeepScreenOn(!keepOn),
        ),
    ];
    // Bloques con su separación de Harmonix (32 · 20 · 16) solo entre los visibles.
    final blocks = <(double, Widget)>[
      if (hasTitles) (0, _Titles(track: np.track!, titleSize: titleSize)),
      if (cfg.show(CarElement.progress)) (32, _Progress(ctrl: ctrl, np: np)),
      if (_Buttons.anyVisible(cfg)) (20, _Buttons(ctrl: ctrl, np: np)),
      if (cfg.show(CarElement.chips) && chips.isNotEmpty) (16, Wrap(spacing: 8, runSpacing: 8, children: chips)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[if (i > 0) SizedBox(height: blocks[i].$1), blocks[i].$2],
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.ctrl,
    required this.np,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.lyricSize,
  });
  final CarController ctrl;
  final NowPlaying np;
  final List<String> tabs;
  final String tab;
  final ValueChanged<String> onTab;
  final double lyricSize;

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    final lyricsLabel = cfg.text(CarText.tabLyrics);
    final queueLabel = cfg.text(CarText.tabQueue);
    final pills = <Widget>[
      if (tabs.contains('lyrics') && lyricsLabel.isNotEmpty)
        HxPill(
          icon: Symbols.lyrics_rounded,
          label: lyricsLabel,
          selected: tab == 'lyrics',
          onTap: () => onTab('lyrics'),
        ),
      if (tabs.contains('queue') && queueLabel.isNotEmpty)
        HxPill(
          icon: Symbols.queue_music_rounded,
          label: queueLabel,
          selected: tab == 'queue',
          onTap: () => onTab('queue'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cfg.show(CarElement.tabPills) && pills.isNotEmpty) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                for (var i = 0; i < pills.length; i++) ...[if (i > 0) const SizedBox(width: 8), pills[i]],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: tab == 'lyrics'
              ? HxLyrics(
                  np: np,
                  lyricIndex: ctrl.lyricIndex,
                  onSeek: ctrl.seek,
                  fontSize: lyricSize,
                  gap: 8 * cfg.lyrics.spacing,
                  align: cfg.lyrics.align,
                  glow: cfg.lyrics.glow,
                  seek: cfg.lyrics.seek,
                )
              : HxQueueList(items: ctrl.queue, coverFor: ctrl.demo || ctrl.idleDemo ? demoCoverFor : null),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Letra en pantalla completa

class _FullscreenLyrics extends StatelessWidget {
  const _FullscreenLyrics({required this.ctrl, required this.np, required this.size, required this.headerH});
  final CarController ctrl;
  final NowPlaying np;
  final Size size;
  final double headerH;

  @override
  Widget build(BuildContext context) {
    final cfg = ctrl.cfg;
    final w = size.width;
    final pad = (w * 0.04).clamp(20.0, 64.0);
    final stageH = math.max(0.0, size.height - headerH - 12 - 32);
    final left = (w * 0.3).clamp(300.0, 420.0);
    final disc = math.max(140.0, math.min(left - 40, stageH - 250) * cfg.cover.scale).clamp(0.0, left).toDouble();
    final hasTitles = cfg.visibility.any(const [CarElement.title, CarElement.artist, CarElement.album]);
    final blocks = <(double, Widget)>[
      if (cfg.show(CarElement.cover))
        (
          0,
          Center(
            child: _CoverGestures(
              ctrl: ctrl,
              child: Disc(
                artwork: np.artwork,
                size: disc,
                playing: np.playing,
                cover: cfg.cover,
                viz: cfg.visualizer,
                showBars: cfg.show(CarElement.visualizer),
              ),
            ),
          ),
        ),
      if (hasTitles) (16, _Titles(track: np.track!, titleSize: 26 * cfg.design.titleScale, compact: true)),
      if (cfg.show(CarElement.progress)) (16, _Progress(ctrl: ctrl, np: np)),
      if (_Buttons.anyVisible(cfg)) (12, _Buttons(ctrl: ctrl, np: np)),
    ];
    final lyrics = HxLyrics(
      np: np,
      lyricIndex: ctrl.lyricIndex,
      onSeek: ctrl.seek,
      fontSize: (w * 0.026).clamp(26.0, 36.0) * cfg.lyrics.scale,
      gap: 12 * cfg.lyrics.spacing,
      align: cfg.lyrics.align,
      glow: cfg.lyrics.glow,
      seek: cfg.lyrics.seek,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (blocks.isNotEmpty) ...[
                SizedBox(
                  width: left,
                  height: stageH,
                  // Red de seguridad: si la letra del sistema es más alta, se achica en vez
                  // de desbordar (en el carro no hay scroll).
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: left,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < blocks.length; i++) ...[
                            if (i > 0) SizedBox(height: blocks[i].$1),
                            blocks[i].$2,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: math.min(64, pad * 1.5)),
                Expanded(
                  child: SizedBox(height: stageH, child: lyrics),
                ),
              ] else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: SizedBox(height: stageH, child: lyrics),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
