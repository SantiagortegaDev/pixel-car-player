import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/lyrics.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Vista previa de la animación de la letra: unas líneas que avanzan solas cada
/// [LyricAnimPreview.step], con las opciones actuales (estilo, duración, curva, opacidad…).
class LyricAnimPreview extends StatefulWidget {
  const LyricAnimPreview({super.key, required this.opts, required this.reduced, this.height = 232});
  final CarLyricsOpts opts;
  final bool reduced;
  final double height;

  static const step = Duration(milliseconds: 2200);

  static const lines = [
    'Se enciende la ciudad cuando cae el sol',
    'y el asfalto brilla como un corazón',
    'tengo el tanque lleno y nada que perder',
    'solo esta carretera y el amanecer',
    'Luces de neón sobre el retrovisor',
    'cada semáforo late a nuestro favor',
  ];

  @override
  State<LyricAnimPreview> createState() => _LyricAnimPreviewState();
}

class _LyricAnimPreviewState extends State<LyricAnimPreview> {
  final _index = ValueNotifier<int>(0);
  late DateTime _start = DateTime.now();
  late NowPlaying _np = _build();
  Timer? _timer;
  bool _paused = false;

  static final _lyrics = [
    for (var i = 0; i < LyricAnimPreview.lines.length; i++)
      LyricLine(LyricAnimPreview.step * i, LyricAnimPreview.lines[i]),
  ];

  NowPlaying _build() => NowPlaying(
    track: TrackInfo(
      id: 'preview',
      title: 'Vista previa',
      artist: '',
      album: '',
      duration: LyricAnimPreview.step * _lyrics.length,
    ),
    playing: !_paused,
    position: DateTime.now().difference(_start),
    positionAt: DateTime.now(),
    lyrics: _lyrics,
    lyricsSynced: true,
    lyricsStatus: LyricsStatus.ok,
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    if (_paused) return;
    final pos = DateTime.now().difference(_start);
    var i = pos.inMilliseconds ~/ LyricAnimPreview.step.inMilliseconds;
    if (i >= _lyrics.length) {
      _start = DateTime.now();
      i = 0;
      setState(() => _np = _build());
    }
    _index.value = i;
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        // Retoma donde quedó.
        _start = DateTime.now().subtract(_np.position);
      }
      _paused = !_paused;
      _np = _paused ? _np.copyWith(playing: false, position: DateTime.now().difference(_start)) : _build();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final o = widget.opts.copyWith(offsetMs: 0);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: HxRadius.l),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: HxLyrics(
              key: const ValueKey('lyric-anim-preview'),
              np: _np,
              lyricIndex: _index,
              onSeek: (_) {},
              fontSize: 22 * o.scale.clamp(0.8, 1.2),
              gap: 8 * o.spacing.clamp(0.5, 1.5),
              align: o.align,
              glow: o.glow,
              seek: CarSeekMode.off,
              opts: o,
              reduced: widget.reduced,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: HxIconButton(
              icon: _paused ? Symbols.play_arrow_rounded : Symbols.pause_rounded,
              tooltip: _paused ? 'Reanudar la vista previa' : 'Pausar la vista previa',
              onTap: _togglePause,
            ),
          ),
        ],
      ),
    );
  }
}
