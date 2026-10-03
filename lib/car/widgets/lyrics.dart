import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/loading_indicator.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Letra (`Lyrics.svelte`, LyricList de Caelestia): la línea actual en `primary` con un
/// brillo del mismo color, el resto en `outline`. La lista se desplaza para dejar la
/// línea actual a un tercio del alto (600 ms). Tocar una línea salta ahí.
class HxLyrics extends StatelessWidget {
  const HxLyrics({
    super.key,
    required this.np,
    required this.lyricIndex,
    required this.onSeek,
    this.fontSize = 19,
    this.gap = 8,
    this.align = CarLyricsAlign.left,
    this.glow = true,
    this.seek = CarSeekMode.tap,
  });

  final NowPlaying np;
  final ValueListenable<int> lyricIndex;
  final ValueChanged<Duration> onSeek;
  final double fontSize;
  final double gap;
  final CarLyricsAlign align;

  /// Brillo de la línea actual.
  final bool glow;

  /// Cómo se salta a una línea al tocarla.
  final CarSeekMode seek;

  @override
  Widget build(BuildContext context) {
    final id = np.track?.id ?? '';
    final ok = np.lyricsStatus == LyricsStatus.ok && np.lyrics.isNotEmpty;
    final String status;
    final Widget view;
    final textAlign = align == CarLyricsAlign.center ? TextAlign.center : TextAlign.start;
    if (ok && np.lyricsSynced) {
      status = 'synced';
      view = _LyricList(
        lines: np.lyrics,
        lyricIndex: lyricIndex,
        onSeek: onSeek,
        fontSize: fontSize,
        gap: gap,
        textAlign: textAlign,
        glow: glow,
        seek: seek,
      );
    } else if (ok) {
      status = 'plain';
      view = _Plain(
        text: np.lyrics.map((l) => l.text).join('\n'),
        fontSize: math.max(18, fontSize - 1),
        textAlign: textAlign,
      );
    } else if (np.lyricsStatus == LyricsStatus.loading) {
      status = 'loading';
      view = const Center(child: HxLoadingIndicator(size: 56, label: 'Buscando la letra'));
    } else {
      status = 'none';
      view = const _None();
    }
    // `{#key status + id}`: la vista nueva entra con un fundido.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: HxTextIn(key: ValueKey('$status$id'), offset: 0, child: view),
    );
  }
}

class _None extends StatelessWidget {
  const _None();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final text = CarCustomScope.of(context).text(CarText.noLyrics);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HxIcon(Symbols.lyrics_rounded, size: 64, color: cs.outline),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: context.tt.titleMedium?.copyWith(color: cs.outline),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain({required this.text, required this.fontSize, required this.textAlign});
  final String text;
  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.8, 1],
      ).createShader(r),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, c.maxWidth * 0.4),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            text,
            textAlign: textAlign,
            style: context.tt.bodyLarge?.copyWith(fontSize: fontSize, color: context.cs.onSurfaceVariant),
          ),
        ),
      ),
    ),
  );
}

/// Curva emphasized de MD3 aproximada (la de `Lyrics.svelte`).
class _LyricEase extends Curve {
  const _LyricEase();
  @override
  double transformInternal(double t) => math.min(1, t < 0.1667 ? 14.4 * t * t : 1 - math.pow(1 - t, 3.2) * 0.95);
}

class _LyricList extends StatefulWidget {
  const _LyricList({
    required this.lines,
    required this.lyricIndex,
    required this.onSeek,
    required this.fontSize,
    required this.gap,
    required this.textAlign,
    required this.glow,
    required this.seek,
  });

  final List<LyricLine> lines;
  final ValueListenable<int> lyricIndex;
  final ValueChanged<Duration> onSeek;
  final double fontSize;
  final double gap;
  final TextAlign textAlign;
  final bool glow;
  final CarSeekMode seek;

  @override
  State<_LyricList> createState() => _LyricListState();
}

class _LyricListState extends State<_LyricList> {
  final _scroll = ScrollController();
  final _content = GlobalKey();
  late List<GlobalKey> _keys = _makeKeys();
  DateTime _userScrollUntil = DateTime(0);
  int _active = -1;

  List<GlobalKey> _makeKeys() => List.generate(widget.lines.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _active = widget.lyricIndex.value;
    widget.lyricIndex.addListener(_onIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  @override
  void didUpdateWidget(_LyricList old) {
    super.didUpdateWidget(old);
    if (old.lyricIndex != widget.lyricIndex) {
      old.lyricIndex.removeListener(_onIndex);
      widget.lyricIndex.addListener(_onIndex);
    }
    if (old.lines.length != widget.lines.length) _keys = _makeKeys();
  }

  @override
  void dispose() {
    widget.lyricIndex.removeListener(_onIndex);
    _scroll.dispose();
    super.dispose();
  }

  void _onIndex() {
    final i = widget.lyricIndex.value;
    if (i == _active) return;
    setState(() => _active = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  void _scrollToActive() {
    if (!mounted || !_scroll.hasClients || DateTime.now().isBefore(_userScrollUntil)) return;
    final i = math.max(0, _active);
    if (i >= _keys.length) return;
    final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
    final content = _content.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || content == null) return;
    final top = box.localToGlobal(Offset.zero, ancestor: content).dy;
    final pos = _scroll.position;
    final to = (top - pos.viewportDimension * 0.3).clamp(0.0, pos.maxScrollExtent);
    if ((to - pos.pixels).abs() < 0.5) return;
    final reduced = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduced) {
      _scroll.jumpTo(to);
    } else {
      unawaited(_scroll.animateTo(to, duration: HxMotion.dLarge, curve: const _LyricEase()));
    }
  }

  bool _onScroll(ScrollNotification n) {
    if ((n is ScrollStartNotification && n.dragDetails != null) ||
        (n is ScrollUpdateNotification && n.dragDetails != null) ||
        n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _userScrollUntil = DateTime.now().add(const Duration(seconds: 4));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final base = hxWeight(context.tt.titleLarge, 500).copyWith(fontSize: widget.fontSize, height: 1.3);
    final idle = base.copyWith(
      color: cs.outline,
      shadows: [Shadow(color: cs.primary.withValues(alpha: 0), blurRadius: 14)],
    );
    final current = base.copyWith(
      color: cs.primary,
      shadows: [Shadow(color: cs.primary.withValues(alpha: widget.glow ? 0.5 : 0), blurRadius: 14)],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight.isFinite && c.maxHeight > 0 ? c.maxHeight : 400.0;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0, math.min(0.4, 24 / h), 0.8, 1],
          ).createShader(r),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              controller: _scroll,
              // La primera línea arranca arriba; el espacio abajo deja subir las últimas.
              padding: EdgeInsets.fromLTRB(4, 4, 4, c.maxWidth * 0.6),
              child: Column(
                key: _content,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.lines.length; i++)
                    Padding(
                      key: _keys[i],
                      padding: EdgeInsets.only(bottom: i == widget.lines.length - 1 ? 0 : widget.gap),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.seek == CarSeekMode.tap ? () => widget.onSeek(widget.lines[i].time) : null,
                        onDoubleTap: widget.seek == CarSeekMode.doubleTap
                            ? () => widget.onSeek(widget.lines[i].time)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: AnimatedDefaultTextStyle(
                            duration: HxMotion.dFxSlow,
                            curve: HxMotion.fxSlow,
                            style: i == _active ? current : idle,
                            textAlign: widget.textAlign,
                            child: Text(widget.lines[i].isGap ? '. . .' : widget.lines[i].text),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
