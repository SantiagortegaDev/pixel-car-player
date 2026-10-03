import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
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

/// Pantalla de la tableta = vista "Reproduciendo" de Harmonix v2 (`NowPlaying.svelte`):
/// BackgroundShapes · Disc | detalles (títulos, slider ondulado, ButtonRow, chips) |
/// Letra / A continuación. El tema sale de la portada (Tonal Spot) y se anima 900 ms.
class CarPlayerScreen extends StatefulWidget {
  const CarPlayerScreen({super.key, required this.onSettings, this.initialLyricsFullscreen = false});

  /// Abre los ajustes. Recibe un `context` que ya tiene el tema de la carátula.
  final void Function(BuildContext themedContext) onSettings;
  final bool initialLyricsFullscreen;

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
    return HxAnimatedTheme(
      scheme: ctrl.scheme,
      child: Builder(
        builder: (themed) {
          final cs = themed.cs;
          final np = ctrl.nowPlaying;
          final hasTrack = np.track != null;
          final fullscreen = _lyricsFullscreen && hasTrack;
          final mode = !hasTrack ? 'idle' : (fullscreen ? 'lyrics' : 'player');
          return Scaffold(
            backgroundColor: cs.surface,
            body: LayoutBuilder(
              builder: (context, c) {
                final k = carScaleFor(c.biggest);
                final w = c.maxWidth / k, h = c.maxHeight / k;
                final mq = MediaQuery.of(context);
                Widget page = MediaQuery(
                  data: mq.copyWith(size: Size(w, h)),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BackgroundShapes(
                          playing: hasTrack && np.playing,
                          minSize: w < 700 ? 36 : 56,
                          maxSize: w < 700 ? 124 : 220,
                        ),
                        SafeArea(
                          child: Column(
                            children: [
                              _Header(
                                mode: mode,
                                status: ctrl.displayStatus,
                                demo: ctrl.demo,
                                onLeft: hasTrack ? _toggleLyrics : null,
                                onSettings: () => widget.onSettings(themed),
                              ),
                              Expanded(
                                child: HxTextIn(
                                  key: ValueKey(mode),
                                  offset: 0,
                                  child: switch (mode) {
                                    'idle' => CarIdleView(
                                      status: ctrl.displayStatus,
                                      ips: ctrl.tabletIps,
                                      onSettings: () => widget.onSettings(themed),
                                      onDemo: () => ctrl.setDemo(true),
                                    ),
                                    'lyrics' => _FullscreenLyrics(ctrl: ctrl, np: np, size: Size(w, h)),
                                    _ => _Stage(
                                      ctrl: ctrl,
                                      np: np,
                                      size: Size(w, h),
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
                    ),
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
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado

class _Header extends StatelessWidget {
  const _Header({
    required this.mode,
    required this.status,
    required this.demo,
    required this.onLeft,
    required this.onSettings,
  });

  final String mode;
  final LinkStatus status;
  final bool demo;
  final VoidCallback? onLeft;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (IconData icon, String tip, String title) = switch (mode) {
      'lyrics' => (Symbols.keyboard_arrow_down_rounded, 'Volver al reproductor', 'Letra'),
      'player' => (Symbols.lyrics_rounded, 'Letra en pantalla completa', 'Reproduciendo'),
      _ => (Symbols.directions_car_rounded, 'Pixel Car Player', 'Pixel Car Player'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (onLeft != null)
              HxIconButton(icon: icon, tooltip: tip, onTap: onLeft)
            else
              SizedBox.square(
                dimension: 48,
                child: Center(child: HxIcon(icon, color: cs.onSurfaceVariant)),
              ),
            const SizedBox(width: 4),
            Text(title, style: context.tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            _StatusChip(status: status, demo: demo, onTap: onSettings),
            const SizedBox(width: 8),
            HxIconButton(icon: Symbols.settings_rounded, tooltip: 'Ajustes', onTap: onSettings),
          ],
        ),
      ),
    );
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
      LinkPhase.searching => (Symbols.wifi_tethering_rounded, 'Buscando al celular…'),
      LinkPhase.disconnected => (Symbols.link_off_rounded, 'Sin conexión'),
    };
    return HxChip(icon: icon, label: label, on: status.isConnected, onTap: onTap, maxWidth: 280);
  }
}

// ---------------------------------------------------------------------------
// Reproductor (3 columnas)

/// Tamaños de las columnas del `.stage` de NowPlaying para un viewport [w]×[h].
class StageLayout {
  StageLayout._(this.pad, this.gap, this.disc, this.details, this.side, this.stageH);
  final double pad, gap, disc, details, side, stageH;

  factory StageLayout.of(Size size) {
    final w = size.width, h = size.height;
    final stageW = math.min(1600.0, w);
    final pad = (w * 0.04).clamp(20.0, 64.0);
    final avail = stageW - pad * 2;
    final stageH = math.max(0.0, h - 60 - 12 - 32);
    if (w >= 1100) {
      // grid: auto | minmax(300px, 440px) | minmax(280px, 1fr), gap 48.
      const gap = 48.0;
      var disc = math.min(460.0, h - 180);
      disc = math.min(disc, math.max(220.0, avail - gap * 2 - 300 - 280));
      final rest = avail - disc - gap * 2;
      final details = (rest - 280).clamp(300.0, 440.0);
      return StageLayout._(pad, gap, disc, details, rest - details, stageH);
    }
    // Más angosto (1024×600): las tres columnas siguen visibles, más compactas.
    const gap = 32.0;
    final disc = math.max(200.0, math.min(math.min(360.0, h - 180), avail - gap * 2 - 280 - 280));
    final rest = avail - disc - gap * 2;
    final details = (rest - 280).clamp(280.0, 400.0);
    return StageLayout._(pad, gap, disc, details, rest - details, stageH);
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.ctrl,
    required this.np,
    required this.size,
    required this.tab,
    required this.onTab,
    required this.onFullscreen,
  });

  final CarController ctrl;
  final NowPlaying np;
  final Size size;
  final String tab;
  final ValueChanged<String> onTab;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final l = StageLayout.of(size);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: EdgeInsets.fromLTRB(l.pad, 12, l.pad, 32),
          child: Row(
            children: [
              SizedBox(
                width: l.disc,
                child: Center(
                  child: Disc(artwork: np.artwork, size: l.disc, playing: np.playing),
                ),
              ),
              SizedBox(width: l.gap),
              SizedBox(
                width: l.details,
                child: _Details(
                  ctrl: ctrl,
                  np: np,
                  titleSize: (size.width * 0.024).clamp(28.0, 36.0),
                  onFullscreen: onFullscreen,
                ),
              ),
              SizedBox(width: l.gap),
              SizedBox(
                width: l.side,
                height: math.min(560, l.stageH),
                child: _Side(
                  ctrl: ctrl,
                  np: np,
                  tab: tab,
                  onTab: onTab,
                  lyricSize: (size.width * 0.015).clamp(18.0, 22.0),
                ),
              ),
            ],
          ),
        ),
      ),
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
    final sub = hxWeight(tt.titleLarge, 400).copyWith(fontSize: compact ? 20 : 22);
    // `{#key t.video_id}` + `text-in`.
    return HxTextIn(
      key: ValueKey(track.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.headlineLarge?.copyWith(
              fontSize: titleSize,
              letterSpacing: -0.01 * titleSize,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track.artist.isEmpty ? 'Artista desconocido' : track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sub.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            track.album.isEmpty ? 'Álbum desconocido' : track.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sub.copyWith(color: cs.secondary, fontSize: compact ? 16 : 18),
          ),
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
    final num = AppTheme.numStyle(context);
    final dur = np.track?.duration ?? Duration.zero;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: ValueListenableBuilder<Duration>(
            valueListenable: ctrl.position,
            builder: (_, p, _) => Text(formatDuration(p), textAlign: TextAlign.center, style: num),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: HxWavySlider(
            position: () => ctrl.nowPlaying.livePosition(),
            duration: dur,
            playing: np.playing,
            onSeek: ctrl.seek,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(formatDuration(dur), textAlign: TextAlign.center, style: num),
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.ctrl, required this.np});
  final CarController ctrl;
  final NowPlaying np;

  @override
  Widget build(BuildContext context) {
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: HxControls(
        playing: np.playing,
        onToggle: ctrl.toggle,
        onPrevious: ctrl.previous,
        onNext: ctrl.next,
        onShuffle: hint,
        onRepeat: hint,
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
    final keepOn = ctrl.prefs.keepScreenOn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Titles(track: np.track!, titleSize: titleSize),
        const SizedBox(height: 32),
        _Progress(ctrl: ctrl, np: np),
        const SizedBox(height: 20),
        _Buttons(ctrl: ctrl, np: np),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            HxChip(icon: Symbols.fullscreen_rounded, label: 'Letra en pantalla completa', onTap: onFullscreen),
            HxChip(
              icon: Symbols.light_mode_rounded,
              label: keepOn ? 'Pantalla siempre encendida' : 'Mantener encendida',
              on: keepOn,
              onTap: () => ctrl.setKeepScreenOn(!keepOn),
            ),
          ],
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.ctrl, required this.np, required this.tab, required this.onTab, required this.lyricSize});
  final CarController ctrl;
  final NowPlaying np;
  final String tab;
  final ValueChanged<String> onTab;
  final double lyricSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              HxPill(
                icon: Symbols.lyrics_rounded,
                label: 'Letra',
                selected: tab == 'lyrics',
                onTap: () => onTab('lyrics'),
              ),
              const SizedBox(width: 8),
              HxPill(
                icon: Symbols.queue_music_rounded,
                label: 'A continuación',
                selected: tab == 'queue',
                onTap: () => onTab('queue'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: tab == 'lyrics'
              ? HxLyrics(np: np, lyricIndex: ctrl.lyricIndex, onSeek: ctrl.seek, fontSize: lyricSize)
              : HxQueueList(items: ctrl.queue, coverFor: ctrl.demo ? demoCoverFor : null),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Letra en pantalla completa

class _FullscreenLyrics extends StatelessWidget {
  const _FullscreenLyrics({required this.ctrl, required this.np, required this.size});
  final CarController ctrl;
  final NowPlaying np;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final pad = (w * 0.04).clamp(20.0, 64.0);
    final stageH = math.max(0.0, size.height - 60 - 12 - 32);
    final left = (w * 0.3).clamp(300.0, 420.0);
    final disc = math.max(140.0, math.min(left - 40, stageH - 250));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
          child: Row(
            children: [
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
                        Center(
                          child: Disc(artwork: np.artwork, size: disc, playing: np.playing),
                        ),
                        const SizedBox(height: 16),
                        _Titles(track: np.track!, titleSize: 26, compact: true),
                        const SizedBox(height: 16),
                        _Progress(ctrl: ctrl, np: np),
                        const SizedBox(height: 12),
                        _Buttons(ctrl: ctrl, np: np),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: math.min(64, pad * 1.5)),
              Expanded(
                child: SizedBox(
                  height: stageH,
                  child: HxLyrics(
                    np: np,
                    lyricIndex: ctrl.lyricIndex,
                    onSeek: ctrl.seek,
                    fontSize: (w * 0.026).clamp(26.0, 36.0),
                    gap: 12,
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
