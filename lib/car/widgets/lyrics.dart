import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/loading_indicator.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Letra (`Lyrics.svelte`, LyricList de Caelestia): la línea actual en `primary` con un
/// brillo del mismo color, el resto en `outline`. La lista se desplaza para dejar la
/// línea actual a un tercio del alto (600 ms por defecto). Tocar una línea salta ahí.
///
/// Al pasar de línea se anima según Configuración → Letra ([CarLyricsOpts.anim]): Suave,
/// Deslizar, Escala, Desenfoque o Karaoke (relleno de izquierda a derecha con el tiempo
/// entre esta línea y la siguiente). Con animaciones reducidas todo cambia sin transición.
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
    this.opts,
    this.fullscreen = false,
    this.reduced,
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

  /// Animación, desplazamiento y opacidad (`null` = los de [CarCustomScope]).
  final CarLyricsOpts? opts;

  /// Letra a pantalla completa (usa "Suave" si la animación no aplica ahí).
  final bool fullscreen;

  /// Animaciones reducidas (`null` = [carReducedMotion]).
  final bool? reduced;

  @override
  Widget build(BuildContext context) {
    final id = np.track?.id ?? '';
    final ok = np.lyricsStatus == LyricsStatus.ok && np.lyrics.isNotEmpty;
    final String status;
    final Widget view;
    final textAlign = align == CarLyricsAlign.center ? TextAlign.center : TextAlign.start;
    final o = opts ?? CarCustomScope.of(context).lyrics;
    final red = reduced ?? carReducedMotion(context);
    if (ok && np.lyricsSynced) {
      status = 'synced';
      view = _LyricList(
        np: np,
        lyricIndex: lyricIndex,
        onSeek: onSeek,
        fontSize: fontSize,
        gap: gap,
        textAlign: textAlign,
        glow: glow,
        seek: seek,
        anim: o.animFor(fullscreen: fullscreen),
        animDuration: Duration(milliseconds: o.animMs),
        curve: lyricCurve(o.animCurve),
        scrollDuration: Duration(milliseconds: o.scrollMs),
        inactiveOpacity: o.inactiveOpacity,
        lead: Duration(milliseconds: o.offsetMs),
        reduced: red,
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

/// Curva de [CarLyricCurve].
Curve lyricCurve(CarLyricCurve c) => switch (c) {
  CarLyricCurve.emphasized => HxMotion.emphasizedDecel,
  CarLyricCurve.standard => HxMotion.standard,
  CarLyricCurve.linear => Curves.linear,
};

/// Progreso 0..1 del relleno karaoke de la línea [index] en [pos]: del tiempo de la línea al
/// de la siguiente (la última dura hasta el final del tema, máx. 6 s).
@visibleForTesting
double karaokeProgress(List<LyricLine> lines, int index, Duration pos, {Duration? trackEnd}) {
  if (index < 0 || index >= lines.length) return 0;
  final start = lines[index].time;
  Duration end;
  if (index + 1 < lines.length) {
    end = lines[index + 1].time;
  } else {
    const cap = Duration(seconds: 6);
    end = trackEnd != null && trackEnd > start ? trackEnd : start + cap;
    if (end - start > cap) end = start + cap;
  }
  final span = (end - start).inMicroseconds;
  if (span <= 0) return 1;
  return ((pos - start).inMicroseconds / span).clamp(0.0, 1.0);
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
    required this.np,
    required this.lyricIndex,
    required this.onSeek,
    required this.fontSize,
    required this.gap,
    required this.textAlign,
    required this.glow,
    required this.seek,
    required this.anim,
    required this.animDuration,
    required this.curve,
    required this.scrollDuration,
    required this.inactiveOpacity,
    required this.lead,
    required this.reduced,
  });

  final NowPlaying np;
  final ValueListenable<int> lyricIndex;
  final ValueChanged<Duration> onSeek;
  final double fontSize;
  final double gap;
  final TextAlign textAlign;
  final bool glow;
  final CarSeekMode seek;
  final CarLyricAnim anim;
  final Duration animDuration;
  final Curve curve;
  final Duration scrollDuration;
  final double inactiveOpacity;
  final Duration lead;
  final bool reduced;

  List<LyricLine> get lines => np.lyrics;

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
      _onIndex();
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
    if (widget.reduced || widget.scrollDuration == Duration.zero) {
      _scroll.jumpTo(to);
    } else {
      unawaited(_scroll.animateTo(to, duration: widget.scrollDuration, curve: const _LyricEase()));
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

  /// Progreso karaoke de la línea actual "ahora" (interpolado con el reloj local).
  double _karaoke() {
    final np = widget.np;
    return karaokeProgress(
      widget.lines,
      _active,
      np.livePosition() + widget.lead,
      trackEnd: np.track?.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = hxWeight(context.tt.titleLarge, 500).copyWith(fontSize: widget.fontSize, height: 1.3);
    final anim = widget.reduced ? CarLyricAnim.none : widget.anim;
    // Karaoke con animaciones reducidas: la línea actual completa, sin relleno progresivo.
    final karaoke = widget.anim == CarLyricAnim.karaoke && !widget.reduced;
    final duration = switch (anim) {
      CarLyricAnim.none => Duration.zero,
      _ => widget.animDuration,
    };
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
                          child: LyricLineView(
                            text: widget.lines[i].isGap ? '. . .' : widget.lines[i].text,
                            active: i == _active,
                            style: base,
                            textAlign: widget.textAlign,
                            glow: widget.glow,
                            anim: anim,
                            duration: duration,
                            curve: widget.curve,
                            inactiveOpacity: widget.inactiveOpacity,
                            progress: karaoke && i == _active ? _karaoke : null,
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

/// Una línea de la letra con su animación de entrada/salida (activa ⇄ inactiva).
///
/// `t` (0 = inactiva, 1 = activa) se anima con [duration] y [curve]; de ahí salen el color
/// (`outline` → `primary`), el brillo, la opacidad y, según [anim], el desplazamiento
/// (solo al entrar), la escala o el desenfoque. Con [progress] (karaoke) la línea activa se
/// rellena fila por fila de izquierda a derecha.
@visibleForTesting
class LyricLineView extends StatefulWidget {
  const LyricLineView({
    super.key,
    required this.text,
    required this.active,
    required this.style,
    this.textAlign = TextAlign.start,
    this.glow = true,
    this.anim = CarLyricAnim.fade,
    this.duration = const Duration(milliseconds: 350),
    this.curve = HxMotion.emphasizedDecel,
    this.inactiveOpacity = 1,
    this.progress,
  });

  final String text;
  final bool active;
  final TextStyle style;
  final TextAlign textAlign;
  final bool glow;
  final CarLyricAnim anim;
  final Duration duration;
  final Curve curve;
  final double inactiveOpacity;

  /// Relleno karaoke 0..1 (se consulta en cada cuadro). `null` = sin karaoke.
  final double Function()? progress;

  /// Desplazamiento (px) con el que entra la línea en "Deslizar".
  static const slidePx = 10.0;

  /// Escala de las líneas inactivas en "Escala".
  static const inactiveScale = 0.94;

  /// Desenfoque (sigma) de las líneas inactivas en "Desenfoque".
  static const blurSigma = 1.6;

  @override
  State<LyricLineView> createState() => LyricLineViewState();
}

@visibleForTesting
class LyricLineViewState extends State<LyricLineView> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.active ? 1 : 0,
  );

  /// La última transición fue de entrada (inactiva → activa).
  bool _entering = false;

  /// Relleno karaoke (se actualiza en cada cuadro mientras la línea está activa).
  final _fill = ValueNotifier<double>(0);
  Ticker? _ticker;

  /// `t` actual con la curva aplicada (para pruebas).
  double get t => _curved;

  double get _curved {
    final v = _c.value;
    if (_c.isAnimating || (v > 0 && v < 1)) {
      // Entrada con la curva elegida; salida con su espejo (desacelera también).
      return _entering ? widget.curve.transform(v) : 1 - widget.curve.transform(1 - v);
    }
    return v;
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(LyricLineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _c.duration = widget.duration;
    if (oldWidget.active != widget.active) {
      _entering = widget.active;
      if (widget.duration == Duration.zero) {
        _c.value = widget.active ? 1 : 0;
      } else if (widget.active) {
        _c.forward(from: 0);
      } else {
        _c.reverse(from: 1);
      }
    }
    _syncTicker();
  }

  void _syncTicker() {
    final want = widget.progress != null && widget.active;
    if (want) {
      _fill.value = widget.progress!();
      _ticker ??= createTicker((_) {
        final p = widget.progress;
        if (p != null) _fill.value = p();
      });
      if (!_ticker!.isActive) _ticker!.start();
    } else {
      _ticker?.stop();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _c.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final karaoke = widget.progress != null;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _curved;
        final idle = cs.outline.withValues(alpha: cs.outline.a * widget.inactiveOpacity);
        // En karaoke la parte sin cantar de la línea activa queda en `outline` (más visible).
        final rest = karaoke ? Color.lerp(idle, cs.outline, t)! : Color.lerp(idle, cs.primary, t)!;
        final glow = Shadow(color: cs.primary.withValues(alpha: widget.glow ? 0.5 * t : 0), blurRadius: 14);
        Widget child = karaoke
            ? _KaraokeText(
                text: widget.text,
                style: widget.style,
                textAlign: widget.textAlign,
                rest: rest,
                fillStyle: widget.style.copyWith(color: cs.primary, shadows: [glow]),
                fill: _fill,
              )
            : Text(
                widget.text,
                textAlign: widget.textAlign,
                style: widget.style.copyWith(color: rest, shadows: [glow]),
              );
        final align = widget.textAlign == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart;
        switch (widget.anim) {
          case CarLyricAnim.slide:
            final dy = _entering ? (1 - t) * LyricLineView.slidePx : 0.0;
            if (dy > 0.01) child = Transform.translate(offset: Offset(0, dy), child: child);
          case CarLyricAnim.scale:
            final s = LyricLineView.inactiveScale + (1 - LyricLineView.inactiveScale) * t;
            child = Transform.scale(scale: s, alignment: align, child: child);
          case CarLyricAnim.blur:
            final sigma = (1 - t) * LyricLineView.blurSigma;
            child = ImageFiltered(
              enabled: sigma > 0.05,
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
              child: child,
            );
          case CarLyricAnim.none || CarLyricAnim.fade || CarLyricAnim.karaoke:
            break;
        }
        return child;
      },
    );
  }
}

/// Texto karaoke: el texto en [rest] y encima el mismo en [fillStyle], recortado fila por
/// fila hasta [fill] (0..1 del ancho total de todas las filas).
class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.rest,
    required this.fillStyle,
    required this.fill,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final Color rest;
  final TextStyle fillStyle;
  final ValueListenable<double> fill;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          textAlign: textAlign,
          textDirection: dir,
          textScaler: scaler,
        )..layout(maxWidth: c.maxWidth.isFinite ? c.maxWidth : double.infinity);
        final rows = tp.computeLineMetrics();
        tp.dispose();
        return Stack(
          children: [
            Text(text, textAlign: textAlign, style: style.copyWith(color: rest), textScaler: scaler),
            Positioned.fill(
              child: ClipPath(
                clipper: _KaraokeClip(rows, fill),
                child: Text(text, textAlign: textAlign, style: fillStyle, textScaler: scaler),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KaraokeClip extends CustomClipper<Path> {
  _KaraokeClip(this.rows, this.fill) : super(reclip: fill);
  final List<LineMetrics> rows;
  final ValueListenable<double> fill;

  @override
  Path getClip(Size size) {
    final path = Path();
    final total = rows.fold<double>(0, (a, m) => a + m.width);
    var left = fill.value.clamp(0.0, 1.0) * total;
    var top = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final m = rows[i];
      if (left <= 0) break;
      final w = math.min(left, m.width);
      // El brillo se sale un poco del texto: margen arriba (primera fila), abajo (última) y a
      // los lados, sin invadir la fila siguiente.
      final t0 = i == 0 ? top - 14 : top;
      final b0 = i == rows.length - 1 ? top + m.height + 14 : top + m.height;
      path.addRect(Rect.fromLTRB(m.left - 16, t0, m.left + w + (w >= m.width ? 16 : 0), b0));
      left -= m.width;
      top += m.height;
    }
    return path;
  }

  @override
  bool shouldReclip(_KaraokeClip oldClipper) => !identical(oldClipper.rows, rows) || oldClipper.fill != fill;
}
