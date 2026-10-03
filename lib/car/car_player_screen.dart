import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/widgets/car_background.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/car/widgets/cover_art.dart';
import 'package:pixel_car_player/car/widgets/idle_view.dart';
import 'package:pixel_car_player/car/widgets/lyrics_view.dart';
import 'package:pixel_car_player/car/widgets/top_bar.dart';
import 'package:pixel_car_player/car/widgets/transport_controls.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Pantalla principal de la tableta (horizontal): "Now Playing" Material You.
///
/// Todo el tema se genera desde la carátula ([CarController.scheme]) y se
/// anima con [AnimatedTheme] al cambiar de canción.
class CarPlayerScreen extends StatefulWidget {
  const CarPlayerScreen({
    super.key,
    required this.onSettings,
    this.initialLyricsFullscreen = false,
  });

  /// Abre los ajustes. Recibe un `context` que ya tiene el tema de la carátula
  /// (para que la hoja modal herede los mismos colores).
  final void Function(BuildContext themedContext) onSettings;
  final bool initialLyricsFullscreen;

  @override
  State<CarPlayerScreen> createState() => _CarPlayerScreenState();
}

class _CarPlayerScreenState extends State<CarPlayerScreen> {
  late bool _lyricsFullscreen = widget.initialLyricsFullscreen;
  ColorScheme? _themeFor;
  late ThemeData _theme;

  void _toggleLyrics() => setState(() => _lyricsFullscreen = !_lyricsFullscreen);

  ThemeData _themeOf(ColorScheme scheme) {
    if (!identical(scheme, _themeFor)) {
      _themeFor = scheme;
      _theme = AppTheme.build(scheme);
    }
    return _theme;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CarController>();
    final np = ctrl.nowPlaying;
    final hasTrack = np.track != null;
    final s = carScaleFor(MediaQuery.sizeOf(context));
    final artKey = '${np.track?.id}-${np.artwork?.length}';
    final fullscreen = _lyricsFullscreen && hasTrack;

    return AnimatedTheme(
      data: _themeOf(ctrl.scheme),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      child: CarScope(
        scale: s,
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              CarBackground(artwork: np.artwork, artKey: artKey),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32 * s, 16 * s, 32 * s, 20 * s),
                  child: Column(
                    children: [
                      Builder(
                        builder: (themed) => CarTopBar(
                          status: ctrl.displayStatus,
                          source: ctrl.source,
                          onSettings: () => widget.onSettings(themed),
                          onLyrics: hasTrack ? _toggleLyrics : null,
                          lyricsActive: fullscreen,
                        ),
                      ),
                      SizedBox(height: 16 * s),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween(begin: 0.98, end: 1.0).animate(anim),
                              child: child,
                            ),
                          ),
                          child: !hasTrack
                              ? Builder(
                                  key: const ValueKey('idle'),
                                  builder: (themed) => CarIdleView(
                                    status: ctrl.displayStatus,
                                    ips: ctrl.tabletIps,
                                    onSettings: () => widget.onSettings(themed),
                                    onDemo: () => ctrl.setDemo(true),
                                  ),
                                )
                              : fullscreen
                              ? _FullscreenLyrics(
                                  key: const ValueKey('lyrics'),
                                  ctrl: ctrl,
                                  np: np,
                                  artKey: artKey,
                                  onExit: _toggleLyrics,
                                )
                              : _PlayerBody(
                                  key: const ValueKey('player'),
                                  ctrl: ctrl,
                                  np: np,
                                  artKey: artKey,
                                  onLyricsTap: _toggleLyrics,
                                ),
                        ),
                      ),
                    ],
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

/// Portada + controles (izquierda) | info + letras + progreso (derecha).
class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    super.key,
    required this.ctrl,
    required this.np,
    required this.artKey,
    required this.onLyricsTap,
  });

  final CarController ctrl;
  final NowPlaying np;
  final String artKey;
  final VoidCallback onLyricsTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cs = context.cs;
    final track = np.track!;
    return LayoutBuilder(
      builder: (context, c) {
        final controlsH = TransportControls.heightFor(s);
        final gap = 20 * s;
        final cover = math.max(120.0, math.min(c.maxHeight - controlsH - gap, c.maxWidth * 0.37));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Columna izquierda ----
            SizedBox(
              width: math.max(cover, 300 * s.clamp(0.9, 1.6)),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: CoverArt(
                        artwork: np.artwork,
                        artKey: artKey,
                        size: cover,
                        playing: np.playing,
                        heroTag: 'car-cover',
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  TransportControls(
                    playing: np.playing,
                    onToggle: ctrl.toggle,
                    onPrevious: ctrl.previous,
                    onNext: ctrl.next,
                  ),
                ],
              ),
            ),
            SizedBox(width: 40 * s),
            // ---- Columna derecha ----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackHeader(track: track, sourceApp: sourceAppName(ctrl.sourcePackage)),
                  SizedBox(height: 16 * s),
                  Expanded(
                    child: Card(
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      child: InkWell(
                        onTap: onLyricsTap,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 28 * s, vertical: 8 * s),
                          child: LyricsPanel(
                            np: np,
                            lyricIndex: ctrl.lyricIndex,
                            livePosition: () => ctrl.nowPlaying.livePosition(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  SizedBox(
                    height: controlsH,
                    child: Center(
                      child: CarProgressBar(
                        position: ctrl.position,
                        duration: track.duration,
                        playing: np.playing,
                        onSeek: ctrl.seek,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.track, this.sourceApp});
  final TrackInfo track;
  final String? sourceApp;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cs = context.cs;
    final tt = context.tt;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      child: Column(
        key: ValueKey(track.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 20 * s, color: cs.primary),
              SizedBox(width: 8 * s),
              Flexible(
                child: Text(
                  sourceApp == null ? 'Reproduciendo' : 'Reproduciendo en $sourceApp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall.scaled(1.1 * s.clamp(0.95, 1.6), color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * s),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.headlineLarge.scaled(
              1.2 * s,
              color: cs.onSurface,
              weight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          SizedBox(height: 2 * s),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: track.artist,
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500),
                ),
                if (track.album.isNotEmpty)
                  TextSpan(
                    text: '  •  ${track.album}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleLarge.scaled(1.1 * s, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Modo "solo letras": karaoke grande centrado + mini reproductor M3.
class _FullscreenLyrics extends StatelessWidget {
  const _FullscreenLyrics({
    super.key,
    required this.ctrl,
    required this.np,
    required this.artKey,
    required this.onExit,
  });

  final CarController ctrl;
  final NowPlaying np;
  final String artKey;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final cs = context.cs;
    final tt = context.tt;
    final track = np.track!;
    final k = s.clamp(1.0, 1.6);
    final thumb = 72 * k;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 48 * s),
            child: LyricsPanel(
              np: np,
              lyricIndex: ctrl.lyricIndex,
              livePosition: () => ctrl.nowPlaying.livePosition(),
              fullscreen: true,
              onTap: onExit,
            ),
          ),
        ),
        SizedBox(height: 12 * s),
        Card(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12 * k, 12 * k, 24 * k, 12 * k),
            child: Row(
              children: [
                CoverArt(
                  artwork: np.artwork,
                  artKey: artKey,
                  size: thumb,
                  radius: 16,
                  elevation: 0,
                ),
                SizedBox(width: 16 * s),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge.scaled(
                          1.05 * s.clamp(0.95, 1.6),
                          color: cs.onSurface,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium.scaled(1.05 * s.clamp(0.95, 1.6), color: cs.primary),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16 * s),
                TransportControls(
                  compact: true,
                  playing: np.playing,
                  onToggle: ctrl.toggle,
                  onPrevious: ctrl.previous,
                  onNext: ctrl.next,
                ),
                SizedBox(width: 24 * s),
                Expanded(
                  flex: 3,
                  child: CarProgressBar(
                    position: ctrl.position,
                    duration: track.duration,
                    playing: np.playing,
                    onSeek: ctrl.seek,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
