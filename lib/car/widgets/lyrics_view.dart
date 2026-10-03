import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/colors.dart';

/// Panel de letras: elige la vista según el estado (sincronizadas, texto
/// estático, buscando, no disponible).
class LyricsPanel extends StatelessWidget {
  const LyricsPanel({
    super.key,
    required this.np,
    required this.lyricIndex,
    required this.livePosition,
    this.fullscreen = false,
    this.onTap,
  });

  final NowPlaying np;
  final ValueListenable<int> lyricIndex;
  final Duration Function() livePosition;
  final bool fullscreen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (np.lyricsStatus == LyricsStatus.ok && np.lyrics.isNotEmpty) {
      child = np.lyricsSynced
          ? SyncedLyricsView(
              key: ValueKey('synced-${np.track?.id}-$fullscreen'),
              lines: np.lyrics,
              lyricIndex: lyricIndex,
              livePosition: livePosition,
              fullscreen: fullscreen,
            )
          : PlainLyricsView(
              key: ValueKey('plain-${np.track?.id}'),
              lines: np.lyrics,
              fullscreen: fullscreen,
            );
    } else if (np.lyricsStatus == LyricsStatus.loading) {
      child = const _LyricsLoading(key: ValueKey('loading'));
    } else {
      child = LyricsUnavailable(key: ValueKey('na-${np.track?.id}'), track: np.track);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: fullscreen ? Alignment.center : Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }
}

/// Máscara de desvanecido arriba/abajo.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child, this.fraction = 0.16});
  final Widget child;
  final double fraction;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (r) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      stops: [0, fraction, 1 - fraction, 1],
    ).createShader(r),
    child: child,
  );
}

/// Letras sincronizadas con auto-scroll que mantiene la línea activa centrada.
/// Estilo Harmonix: `AnimatedDefaultTextStyle`, línea activa grande y brillante.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lines,
    required this.lyricIndex,
    required this.livePosition,
    this.fullscreen = false,
  });

  final List<LyricLine> lines;
  final ValueListenable<int> lyricIndex;
  final Duration Function() livePosition;
  final bool fullscreen;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  DateTime _userScrollUntil = DateTime(0);
  Timer? _settle;
  bool _first = true;

  double get _alignment => widget.fullscreen ? 0.5 : 0.42;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lines.length, (_) => GlobalKey());
    widget.lyricIndex.addListener(_onIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive(animate: false));
  }

  @override
  void didUpdateWidget(SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyricIndex != widget.lyricIndex) {
      old.lyricIndex.removeListener(_onIndex);
      widget.lyricIndex.addListener(_onIndex);
    }
    if (old.lines.length != widget.lines.length) {
      _keys = List.generate(widget.lines.length, (_) => GlobalKey());
    }
  }

  @override
  void dispose() {
    widget.lyricIndex.removeListener(_onIndex);
    _settle?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onIndex() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  void _scrollToActive({bool animate = true}) {
    if (!mounted || DateTime.now().isBefore(_userScrollUntil)) return;
    final i = widget.lyricIndex.value;
    if (i < 0 || i >= _keys.length) {
      if (_scroll.hasClients && _scroll.offset != 0) {
        animate
            ? _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
              )
            : _scroll.jumpTo(0);
      }
      return;
    }
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    final instant = !animate || _first;
    _first = false;
    Scrollable.ensureVisible(
      ctx,
      alignment: _alignment,
      duration: instant ? Duration.zero : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
    // El tamaño de la línea activa se anima (~300 ms): corregir al terminar.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 340), () {
      final c = _keys.length > i ? _keys[i].currentContext : null;
      if (c != null && mounted && !DateTime.now().isBefore(_userScrollUntil)) {
        Scrollable.ensureVisible(
          c,
          alignment: _alignment,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.palette;
    final fs = widget.fullscreen;
    final active = widget.lyricIndex.value;
    final activeSize = (fs ? 54.0 : 32.0) * s;
    final idleSize = (fs ? 34.0 : 23.0) * s;
    final align = fs ? TextAlign.center : TextAlign.left;

    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxHeight * 0.45;
        return NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            if (n.dragDetails != null) {
              _userScrollUntil = DateTime.now().add(const Duration(seconds: 4));
              Timer(const Duration(milliseconds: 4100), _scrollToActive);
            }
            return false;
          },
          child: _EdgeFade(
            fraction: fs ? 0.22 : 0.14,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: pad),
              child: Column(
                crossAxisAlignment: fs ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.lines.length; i++)
                    _line(i, active, activeSize, idleSize, align, p.accentBright, s),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(
    int i,
    int active,
    double activeSize,
    double idleSize,
    TextAlign align,
    Color activeColor,
    double s,
  ) {
    final line = widget.lines[i];
    final isActive = i == active;
    final dist = (i - active).abs();
    final past = active >= 0 && i < active;
    final idleAlpha = (past ? 0.42 : 0.72) - (dist > 3 ? 0.12 : 0);
    final text = line.isGap ? '♪' : line.text;
    final fs = widget.fullscreen;

    Widget content = Text(text, textAlign: align);
    if (isActive && fs && !line.isGap) {
      final end = i + 1 < widget.lines.length
          ? widget.lines[i + 1].time
          : line.time + const Duration(seconds: 5);
      content = _KaraokeText(
        text: text,
        align: align,
        start: line.time,
        end: end,
        livePosition: widget.livePosition,
        sungColor: activeColor,
      );
    }

    return Padding(
      key: _keys[i],
      padding: EdgeInsets.symmetric(vertical: (fs ? 12 : 8) * s),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          fontFamily: 'Roboto',
          color: isActive
              ? (fs ? Colors.white : activeColor)
              : HarmonixColors.textSecondary.withValues(alpha: idleAlpha),
          fontSize: isActive ? activeSize : idleSize,
          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          height: 1.25,
          letterSpacing: isActive ? -0.4 : -0.1,
          shadows: isActive
              ? [Shadow(color: activeColor.withValues(alpha: 0.45), blurRadius: 24 * s)]
              : const [],
        ),
        child: content,
      ),
    );
  }
}

/// Línea activa estilo karaoke: la parte "cantada" se pinta con el acento,
/// el resto en blanco tenue. Se actualiza cada frame con su propio Ticker.
class _KaraokeText extends StatefulWidget {
  const _KaraokeText({
    required this.text,
    required this.align,
    required this.start,
    required this.end,
    required this.livePosition,
    required this.sungColor,
  });

  final String text;
  final TextAlign align;
  final Duration start;
  final Duration end;
  final Duration Function() livePosition;
  final Color sungColor;

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _progress = _compute();
    _ticker = createTicker((_) {
      final p = _compute();
      if ((p - _progress).abs() > 0.002) setState(() => _progress = p);
    })..start();
  }

  double _compute() {
    final total = (widget.end - widget.start).inMilliseconds;
    // El barrido termina un poco antes de la siguiente línea (respiración).
    final span = (total * 0.85).clamp(400, 8000);
    final t = (widget.livePosition() - widget.start).inMilliseconds / span;
    return t.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          widget.sungColor,
          Color.lerp(widget.sungColor, Colors.white, 0.35)!,
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.55),
        ],
        stops: [0, p, (p + 0.04).clamp(0, 1), 1],
      ).createShader(r),
      child: Text(widget.text, textAlign: widget.align),
    );
  }
}

/// Letra sin sincronizar: texto estático desplazable.
class PlainLyricsView extends StatelessWidget {
  const PlainLyricsView({super.key, required this.lines, this.fullscreen = false});
  final List<LyricLine> lines;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.palette;
    return Column(
      crossAxisAlignment: fullscreen ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 8 * s),
          padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 6 * s),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            'Letra sin sincronizar',
            style: TextStyle(
              color: p.accentBright,
              fontSize: 14 * s.clamp(1.0, 1.6),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: _EdgeFade(
            fraction: 0.08,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: 24 * s),
              children: [
                Text(
                  lines.map((l) => l.text).join('\n'),
                  textAlign: fullscreen ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    color: HarmonixColors.textPrimary.withValues(alpha: 0.88),
                    fontSize: (fullscreen ? 34 : 24) * s,
                    fontWeight: FontWeight.w600,
                    height: 1.55,
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

class _LyricsLoading extends StatelessWidget {
  const _LyricsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26 * s,
          height: 26 * s,
          child: CircularProgressIndicator(strokeWidth: 3, color: p.accentBright),
        ),
        SizedBox(width: 16 * s),
        Text(
          'Buscando la letra…',
          style: TextStyle(
            color: HarmonixColors.textSecondary,
            fontSize: 22 * s,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// "Letra no disponible" con la información del álbum.
class LyricsUnavailable extends StatelessWidget {
  const LyricsUnavailable({super.key, required this.track});
  final TrackInfo? track;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = context.palette;
    final t = track;
    Widget chip(IconData icon, String label) => Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14 * s),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22 * s, color: p.accentBright),
          SizedBox(width: 10 * s),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HarmonixColors.textPrimary,
                fontSize: 18 * s,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64 * s,
          height: 64 * s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [p.accent.withValues(alpha: 0.35), p.accentDim.withValues(alpha: 0.15)],
            ),
          ),
          child: Icon(Icons.music_off_rounded, color: p.accentBright, size: 32 * s),
        ),
        SizedBox(height: 18 * s),
        Text(
          'Letra no disponible',
          style: TextStyle(
            color: HarmonixColors.textPrimary,
            fontSize: 30 * s,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 6 * s),
        Text(
          'Disfruta la música — no encontramos la letra de esta canción.',
          style: TextStyle(color: HarmonixColors.textSecondary, fontSize: 19 * s, height: 1.35),
        ),
        if (t != null) ...[
          SizedBox(height: 22 * s),
          Wrap(
            spacing: 12 * s,
            runSpacing: 12 * s,
            children: [
              if (t.album.isNotEmpty) chip(Icons.album_rounded, t.album),
              if (t.artist.isNotEmpty) chip(Icons.person_rounded, t.artist),
              if (t.duration > Duration.zero)
                chip(Icons.schedule_rounded, formatDuration(t.duration)),
            ],
          ),
        ],
      ],
    );
  }
}
