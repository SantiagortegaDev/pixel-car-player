import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// ButtonRow de Caelestia / Harmonix v2 (`Controls.svelte`): IconButtons con
/// `shapeMorph` de MD3 Expressive.
///  - radio: redondo → 8 px al presionar → 12 px si está activo (DefaultEffects, 200 ms)
///  - al presionar se ensancha 24 px (FastSpatial, 350 ms) y el de play cede el espacio
///  - tonales: secondaryContainer; activos: secondary. Play: primary sonando, surface en pausa.
class HxControls extends StatelessWidget {
  const HxControls({
    super.key,
    required this.playing,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    this.shuffle = false,
    this.repeat = false,
    this.repeatOne = false,
    this.liked = false,
    this.onShuffle,
    this.onRepeat,
    this.onLike,
    this.height = 56,
    this.showShuffle = true,
    this.showPrevious = true,
    this.showPlay = true,
    this.showNext = true,
    this.showRepeat = true,
    this.showLike = false,
    this.pressIntensity = 1,
    this.haptics = false,
  });

  final bool playing;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool shuffle;

  /// Repetir activo (todo o uno); [repeatOne] cambia el ícono a `repeat_one`.
  final bool repeat;
  final bool repeatOne;
  final bool liked;

  /// `null` = deshabilitado (la app del celular no lo permite).
  final VoidCallback? onShuffle;
  final VoidCallback? onRepeat;
  final VoidCallback? onLike;
  final double height;
  final bool showShuffle, showPrevious, showPlay, showNext, showRepeat, showLike;

  /// Qué tanto se ensancha / redondea al presionar (0 = nada, 1 = Harmonix).
  final double pressIntensity;

  /// Vibración corta al tocar.
  final bool haptics;

  /// Ancho mínimo de la fila (en múltiplos del alto) con los botones visibles.
  double get _units =>
      (showShuffle ? 0.9 : 0) +
      (showPrevious ? 1 : 0) +
      (showPlay ? 1.2 : 0) +
      (showNext ? 1 : 0) +
      (showRepeat ? 0.9 : 0) +
      (showLike ? 0.9 : 0);

  int get _count => [showShuffle, showPrevious, showPlay, showNext, showRepeat, showLike].where((v) => v).length;

  VoidCallback? _tap(VoidCallback? f) => f == null
      ? null
      : () {
          if (haptics) HapticFeedback.selectionClick();
          f();
        };

  /// Ancho máximo razonable de la fila para un alto [h] (el de play se estira hasta acá).
  static double maxWidthFor(double h) => math.max(400, h * 7.2);

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        // Si no caben al alto pedido (controles muy altos en una columna angosta), se achican.
        final gaps = 4.0 * (_count - 1);
        final fit = c.maxWidth.isFinite ? (c.maxWidth - gaps) / _units : height;
        final h = math.max(32.0, math.min(height, fit));
        final children = <Widget>[
          if (showShuffle)
            _MorphButton(
              h: h,
              width: h * 0.9,
              kind: _Kind.tonal,
              checked: shuffle,
              icon: Symbols.shuffle_rounded,
              label: 'Aleatorio',
              onTap: _tap(onShuffle),
              press: pressIntensity,
            ),
          if (showPrevious)
            _MorphButton(
              h: h,
              width: h,
              kind: _Kind.tonal,
              big: true,
              icon: Symbols.skip_previous_rounded,
              label: 'Anterior',
              onTap: _tap(onPrevious),
              press: pressIntensity,
            ),
          if (showPlay)
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: h * 1.2),
                child: _MorphButton(
                  h: h,
                  kind: _Kind.play,
                  checked: playing,
                  big: true,
                  icon: playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                  label: playing ? 'Pausar' : 'Reproducir',
                  onTap: _tap(onToggle),
                  press: pressIntensity,
                ),
              ),
            ),
          if (showNext)
            _MorphButton(
              h: h,
              width: h,
              kind: _Kind.tonal,
              big: true,
              icon: Symbols.skip_next_rounded,
              label: 'Siguiente',
              onTap: _tap(onNext),
              press: pressIntensity,
            ),
          if (showRepeat)
            _MorphButton(
              h: h,
              width: h * 0.9,
              kind: _Kind.tonal,
              checked: repeat,
              icon: repeatOne ? Symbols.repeat_one_rounded : Symbols.repeat_rounded,
              label: repeatOne ? 'Repetir uno' : 'Repetir',
              onTap: _tap(onRepeat),
              press: pressIntensity,
            ),
          if (showLike)
            _MorphButton(
              h: h,
              width: h * 0.9,
              kind: _Kind.tonal,
              checked: liked,
              icon: Symbols.favorite_rounded,
              label: liked ? 'Quitar me gusta' : 'Me gusta',
              onTap: _tap(onLike),
              press: pressIntensity,
            ),
        ];
        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: showPlay ? MainAxisSize.max : MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 4), children[i]],
            ],
          ),
        );
      },
    );
  }
}

enum _Kind { tonal, play }

class _MorphButton extends StatefulWidget {
  const _MorphButton({
    required this.h,
    required this.kind,
    required this.icon,
    required this.label,
    required this.onTap,
    this.width,
    this.checked = false,
    this.big = false,
    this.press = 1,
  });

  final double h;

  /// Ancho en reposo (null = ocupa lo que le dan, como el de play).
  final double? width;
  final _Kind kind;
  final IconData icon;
  final String label;

  /// `null` = deshabilitado (38 % de opacidad, sin toque).
  final VoidCallback? onTap;
  final bool checked;
  final bool big;

  /// Intensidad de la respuesta al presionar.
  final double press;

  @override
  State<_MorphButton> createState() => _MorphButtonState();
}

class _MorphButtonState extends State<_MorphButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = widget.h;
    final play = widget.kind == _Kind.play;
    final (bg, fg) = play
        ? (widget.checked ? (cs.primary, cs.onPrimary) : (cs.surfaceContainerHighest, cs.onSurfaceVariant))
        : (widget.checked ? (cs.secondary, cs.onSecondary) : (cs.secondaryContainer, cs.onSecondaryContainer));
    final rest = widget.checked ? HxRadius.mV : h / 2;
    // Con intensidad 0 no cambia; 1 = 8 px (Harmonix); 2 = casi cuadrado.
    final pressed = (rest + (HxRadius.sV - rest) * widget.press).clamp(2.0, h / 2);
    final radius = _pressed ? pressed : rest;
    final fill = widget.checked || play;

    Widget body = TweenAnimationBuilder<double>(
      tween: Tween(end: radius),
      duration: HxMotion.dFx,
      curve: HxMotion.fx,
      builder: (_, r, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: bg),
        duration: HxMotion.dFxSlow,
        curve: HxMotion.fxSlow,
        builder: (_, color, child) => Material(
          color: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: widget.onTap == null ? null : (v) => setState(() => _pressed = v),
            splashFactory: InkRipple.splashFactory,
            splashColor: fg.withValues(alpha: 0.1),
            highlightColor: fg.withValues(alpha: 0.1),
            hoverColor: fg.withValues(alpha: 0.08),
            child: child,
          ),
        ),
        child: child,
      ),
      child: SizedBox(
        height: h,
        child: Center(
          child: HxIcon(widget.icon, size: h * (widget.big ? 0.55 : 0.43), fill: fill, weight: 500, color: fg),
        ),
      ),
    );

    if (widget.width != null) {
      body = TweenAnimationBuilder<double>(
        tween: Tween(end: widget.width! + (_pressed ? 24 * widget.press : 0)),
        duration: HxMotion.dSpringFast,
        curve: HxMotion.springFast,
        builder: (_, w, child) => SizedBox(width: w, child: child),
        child: body,
      );
    }
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      toggled: widget.kind == _Kind.tonal && widget.width != h ? widget.checked : null,
      excludeSemantics: true,
      child: Tooltip(
        message: enabled ? widget.label : '${widget.label} (no disponible)',
        child: AnimatedOpacity(opacity: enabled ? 1 : 0.38, duration: HxMotion.dFxSlow, child: body),
      ),
    );
  }
}
