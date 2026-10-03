import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/widgets/car_scope.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';

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
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: GestureDetector(
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
    final cs = context.cs;
    final fs = widget.fullscreen;
    final active = widget.lyricIndex.value;
    final activeSize = (fs ? 56.0 : 32.0) * s;
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
                    _line(i, active, activeSize, idleSize, align, cs, s),
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
    ColorScheme cs,
    double s,
  ) {
    final line = widget.lines[i];
    final isActive = i == active;
    final dist = (i - active).abs();
    final past = active >= 0 && i < active;
    final idleAlpha = (past ? 0.5 : 0.8) - (dist > 3 ? 0.15 : 0);
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
        sungColor: cs.primary,
        unsungColor: cs.onSurface.withValues(alpha: 0.5),
      );
    }

    return Padding(
      key: _keys[i],
      padding: EdgeInsets.symmetric(vertical: (fs ? 12 : 8) * s),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        style: (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(
          color: isActive
              ? (fs ? cs.onSurface : cs.primary)
              : cs.onSurfaceVariant.withValues(alpha: idleAlpha),
          fontSize: isActive ? activeSize : idleSize,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          height: 1.25,
          letterSpacing: 0,
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
    required this.unsungColor,
  });

  final String text;
  final TextAlign align;
  final Duration start;
  final Duration end;
  final Duration Function() livePosition;
  final Color sungColor;
  final Color unsungColor;

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
        colors: [widget.sungColor, widget.sungColor, widget.unsungColor, widget.unsungColor],
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
    final cs = context.cs;
    final k = s.clamp(1.0, 1.6);
    return Column(
      crossAxisAlignment: fullscreen ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 8 * k),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(8 * k),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notes_rounded, size: 20 * k, color: cs.onSecondaryContainer),
              SizedBox(width: 8 * k),
              Text(
                'Letra sin sincronizar',
                style: context.tt.labelLarge.scaled(1.15 * k, color: cs.onSecondaryContainer),
              ),
            ],
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
                  style: context.tt.headlineSmall.scaled(
                    (fullscreen ? 1.4 : 0.95) * s,
                    color: cs.onSurface,
                    weight: FontWeight.w500,
                    height: 1.5,
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
    final cs = context.cs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: 28 * s, child: const CircularProgressIndicator(strokeWidth: 3.5)),
        SizedBox(width: 18 * s),
        Text(
          'Buscando la letra…',
          style: context.tt.titleLarge.scaled(s, color: cs.onSurfaceVariant),
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
    final cs = context.cs;
    final tt = context.tt;
    final t = track;
    Widget chip(IconData icon, String label) => Container(
      height: 48 * s.clamp(1.0, 1.6),
      padding: EdgeInsets.only(left: 14 * s, right: 18 * s),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12 * s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22 * s, color: cs.primary),
          SizedBox(width: 10 * s),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelLarge.scaled(1.25 * s, color: cs.onSurface),
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
          width: 72 * s,
          height: 72 * s,
          decoration: BoxDecoration(
            color: cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(24 * s),
          ),
          child: Icon(Icons.music_off_rounded, color: cs.onTertiaryContainer, size: 36 * s),
        ),
        SizedBox(height: 20 * s),
        Text(
          'Letra no disponible',
          style: tt.headlineMedium.scaled(s, color: cs.onSurface, weight: FontWeight.w500),
        ),
        SizedBox(height: 8 * s),
        Text(
          'Disfruta la música — no encontramos la letra de esta canción.',
          style: tt.bodyLarge.scaled(1.15 * s, color: cs.onSurfaceVariant, height: 1.4),
        ),
        if (t != null) ...[
          SizedBox(height: 24 * s),
          Wrap(
            spacing: 10 * s,
            runSpacing: 10 * s,
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
