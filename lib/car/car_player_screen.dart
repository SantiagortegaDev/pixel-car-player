import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/color/artwork_palette.dart';
import 'package:pixel_car_player/car/widgets/car_background.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/car/widgets/cover_art.dart';
import 'package:pixel_car_player/car/widgets/idle_view.dart';
import 'package:pixel_car_player/car/widgets/lyrics_view.dart';
import 'package:pixel_car_player/car/widgets/top_bar.dart';
import 'package:pixel_car_player/car/widgets/transport_controls.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:provider/provider.dart';

/// Pantalla principal de la tableta (horizontal), basada en el reproductor a
/// pantalla completa de Harmonix.
class CarPlayerScreen extends StatefulWidget {
  const CarPlayerScreen({
    super.key,
    required this.onSettings,
    this.initialLyricsFullscreen = false,
  });

  final VoidCallback onSettings;
  final bool initialLyricsFullscreen;

  @override
  State<CarPlayerScreen> createState() => _CarPlayerScreenState();
}

class _CarPlayerScreenState extends State<CarPlayerScreen> {
  late bool _lyricsFullscreen = widget.initialLyricsFullscreen;

  void _toggleLyrics() => setState(() => _lyricsFullscreen = !_lyricsFullscreen);

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CarController>();
    final np = ctrl.nowPlaying;
    final hasTrack = np.track != null;
    final size = MediaQuery.sizeOf(context);
    final s = carScaleFor(size);
    final artKey = '${np.track?.id}-${np.artwork?.length}';
    final fullscreen = _lyricsFullscreen && hasTrack;

    return TweenAnimationBuilder<ArtworkPalette>(
      tween: ArtworkPaletteTween(end: ctrl.palette),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeInOut,
      builder: (context, palette, _) => CarScope(
        scale: s,
        palette: palette,
        child: Scaffold(
          backgroundColor: HarmonixColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              CarBackground(artwork: np.artwork, artKey: artKey),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32 * s, 12 * s, 32 * s, 16 * s),
                  child: Column(
                    children: [
                      CarTopBar(
                        status: ctrl.displayStatus,
                        source: ctrl.source,
                        onSettings: widget.onSettings,
                        onLyrics: hasTrack ? _toggleLyrics : null,
                        lyricsActive: fullscreen,
                      ),
                      SizedBox(height: 12 * s),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
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
                              ? CarIdleView(
                                  key: const ValueKey('idle'),
                                  status: ctrl.displayStatus,
                                  ips: ctrl.tabletIps,
                                  onSettings: widget.onSettings,
                                  onDemo: () => ctrl.setDemo(true),
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

/// Portada + controles (izquierda) | info + letras + slider (derecha).
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
    final track = np.track!;
    return LayoutBuilder(
      builder: (context, c) {
        final controlsH = TransportControls.heightFor(s);
        final gap = 18 * s;
        final cover = math.max(120.0, math.min(c.maxHeight - controlsH - gap, c.maxWidth * 0.37));
        final colGap = 44 * s;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Columna izquierda ----
            SizedBox(
              width: math.max(cover, 300 * s.clamp(0.9, 1.6)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: CoverArt(
                        artwork: np.artwork,
                        artKey: artKey,
                        size: cover,
                        playing: np.playing,
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
            SizedBox(width: colGap),
            // ---- Columna derecha ----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TrackHeader(track: track, sourceApp: sourceAppName(ctrl.sourcePackage)),
                  SizedBox(height: 8 * s),
                  Expanded(
                    child: LyricsPanel(
                      np: np,
                      lyricIndex: ctrl.lyricIndex,
                      livePosition: () => ctrl.nowPlaying.livePosition(),
                      onTap: onLyricsTap,
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
    final p = context.palette;
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
          Text(
            sourceApp == null ? 'REPRODUCIENDO' : 'REPRODUCIENDO EN ${sourceApp!.toUpperCase()}',
            style: TextStyle(
              color: HarmonixColors.textSecondary,
              fontSize: 14 * s.clamp(0.95, 1.6),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          SizedBox(height: 6 * s),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: HarmonixColors.textPrimary,
              fontSize: 40 * s,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          SizedBox(height: 4 * s),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: track.artist,
                  style: TextStyle(color: p.accentBright, fontWeight: FontWeight.w700),
                ),
                if (track.album.isNotEmpty)
                  TextSpan(
                    text: '  ·  ${track.album}',
                    style: const TextStyle(
                      color: HarmonixColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24 * s, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Modo "solo letras": karaoke grande centrado + mini controles.
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
    final p = context.palette;
    final track = np.track!;
    final thumb = 64 * s.clamp(1.0, 1.6);
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
        Row(
          children: [
            CoverArt(artwork: np.artwork, artKey: artKey, size: thumb, radius: 14, glow: false),
            SizedBox(width: 16 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HarmonixColors.textPrimary,
                      fontSize: 22 * s.clamp(0.95, 1.6),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.accentBright,
                      fontSize: 18 * s.clamp(0.95, 1.6),
                      fontWeight: FontWeight.w600,
                    ),
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
              child: CarProgressBar(
                position: ctrl.position,
                duration: track.duration,
                playing: np.playing,
                onSeek: ctrl.seek,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
