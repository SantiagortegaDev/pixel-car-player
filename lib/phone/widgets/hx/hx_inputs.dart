import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_motion.dart';

/// Slider de MD3 Expressive (`Slider.svelte` de Harmonix): pista de 16 px con el tramo
/// activo en primary, hueco de 6 px a cada lado del asa (barra de 4×44) y pasos.
class HxSlider extends StatefulWidget {
  const HxSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.onChangeEnd,
    this.semanticLabel,
  });
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? semanticLabel;

  @override
  State<HxSlider> createState() => _HxSliderState();
}

class _HxSliderState extends State<HxSlider> {
  bool _drag = false;

  double _snap(double v) {
    v = v.clamp(widget.min, widget.max);
    final d = widget.divisions;
    if (d == null || d <= 0) return v;
    final step = (widget.max - widget.min) / d;
    return widget.min + ((v - widget.min) / step).round() * step;
  }

  double _fromDx(double dx, double width) {
    const pad = 2.0;
    final f = ((dx - pad) / (width - pad * 2)).clamp(0.0, 1.0);
    return _snap(widget.min + f * (widget.max - widget.min));
  }

  void _set(double v) {
    if (v != widget.value) {
      HxHaptics.tap();
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final span = widget.max - widget.min;
    final f = span <= 0
        ? 0.0
        : ((widget.value - widget.min) / span).clamp(0.0, 1.0);
    final step = widget.divisions != null && widget.divisions! > 0
        ? span / widget.divisions!
        : span / 20;
    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.value.round().toString(),
      increasedValue: _snap(widget.value + step).round().toString(),
      decreasedValue: _snap(widget.value - step).round().toString(),
      onIncrease: () => widget.onChanged(_snap(widget.value + step)),
      onDecrease: () => widget.onChanged(_snap(widget.value - step)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final v = _fromDx(d.localPosition.dx, w);
              _set(v);
              widget.onChangeEnd?.call(v);
            },
            onHorizontalDragStart: (d) {
              setState(() => _drag = true);
              _set(_fromDx(d.localPosition.dx, w));
            },
            onHorizontalDragUpdate: (d) => _set(_fromDx(d.localPosition.dx, w)),
            onHorizontalDragEnd: (_) {
              setState(() => _drag = false);
              widget.onChangeEnd?.call(widget.value);
            },
            child: SizedBox(
              height: 44,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: f),
                duration: _drag || hxReduceMotion(context)
                    ? Duration.zero
                    : HxMotion.dSpringFast,
                curve: HxMotion.springFast,
                builder: (context, f, _) {
                  const handle = 4.0, gap = 6.0, track = 16.0;
                  final x = 2 + f * (w - 4);
                  final activeW = (x - handle / 2 - gap).clamp(0.0, w);
                  final inactiveL = (x + handle / 2 + gap).clamp(0.0, w);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (activeW > 0)
                        Positioned(
                          left: 0,
                          width: activeW,
                          top: (44 - track) / 2,
                          height: track,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                                right: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      if (inactiveL < w)
                        Positioned(
                          left: inactiveL,
                          right: 0,
                          top: (44 - track) / 2,
                          height: track,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(2),
                                right: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: x - (_drag ? 1 : handle / 2),
                        top: 0,
                        width: _drag ? 2 : handle,
                        height: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Barra de progreso lineal de MD3 Expressive: pista de 8 px, tramo activo primary,
/// hueco de 4 px y punto final. [value] null = indeterminada (barrido).
class HxProgressBar extends StatefulWidget {
  const HxProgressBar({super.key, required this.value});
  final double? value;

  @override
  State<HxProgressBar> createState() => _HxProgressBarState();
}

class _HxProgressBarState extends State<HxProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  void _sync() {
    final run = widget.value == null && !hxReduceMotion(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HxProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 8,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (widget.value ?? 0).clamp(0.0, 1.0)),
        duration: HxMotion.dFxSlow,
        curve: HxMotion.standard,
        builder: (context, v, _) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: const Size(double.infinity, 8),
            painter: _ProgressPainter(
              value: widget.value == null ? null : v,
              phase: _c.value,
              active: cs.primary,
              track: cs.secondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.value,
    required this.phase,
    required this.active,
    required this.track,
  });
  final double? value;
  final double phase;
  final Color active;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final r = Radius.circular(h / 2);
    void bar(double a, double b, Color c) {
      if (b - a <= 0.5) return;
      canvas.drawRRect(
        RRect.fromLTRBR(a.clamp(0, w), 0, b.clamp(0, w), h, r),
        Paint()..color = c,
      );
    }

    const gap = 4.0;
    if (value == null) {
      final p = Curves.easeInOut.transform(phase);
      final a = w * (p * 1.4 - 0.4), b = a + w * 0.4;
      bar(0, a - gap, track);
      bar(a, b, active);
      bar(b + gap, w, track);
      return;
    }
    final x = w * value!;
    bar(0, x, active);
    bar(x + gap, w, track);
    // Punto de parada al final (MD3 Expressive).
    canvas.drawCircle(Offset(w - h / 2, h / 2), h / 4, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.value != value || old.phase != phase || old.active != active;
}

/// Entrada de un código numérico en casillas (emparejamiento): un solo campo de texto
/// invisible encima de [length] casillas, así funcionan el teclado numérico, pegar y el
/// autocompletado de códigos; el cursor "avanza" solo a la casilla siguiente.
class HxCodeInput extends StatefulWidget {
  const HxCodeInput({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.error = false,
    this.success = false,
    this.autofocus = true,
    this.focusNode,
  });
  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool error;
  final bool success;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<HxCodeInput> createState() => _HxCodeInputState();
}

class _HxCodeInputState extends State<HxCodeInput> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onText);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final focused = _focus.hasFocus;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final n = widget.length;
        final bw = ((box.maxWidth - gap * (n - 1)) / n).clamp(32.0, 52.0);
        final bh = (bw * 1.25).clamp(48.0, 64.0);
        return SizedBox(
          height: bh,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    _box(cs, i, text, focused, bw, bh),
                  ],
                ],
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.011,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(n),
                    ],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(color: Colors.transparent),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                    onChanged: (v) {
                      widget.onChanged?.call(v);
                      if (v.length == n) widget.onCompleted?.call(v);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _box(
    ColorScheme cs,
    int i,
    String text,
    bool focused,
    double w,
    double h,
  ) {
    final has = i < text.length;
    final current =
        focused &&
        widget.enabled &&
        i == text.length.clamp(0, widget.length - 1);
    final Color bg, fg, border;
    if (widget.success) {
      bg = cs.primary;
      fg = cs.onPrimary;
      border = Colors.transparent;
    } else if (widget.error) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
      border = current ? cs.error : Colors.transparent;
    } else {
      bg = has ? cs.secondaryContainer : cs.surfaceContainerHighest;
      fg = has ? cs.onSecondaryContainer : cs.onSurfaceVariant;
      border = current ? cs.primary : Colors.transparent;
    }
    final reduce = hxReduceMotion(context);
    return AnimatedContainer(
      duration: reduce ? Duration.zero : HxMotion.dFxSlow,
      curve: HxMotion.standard,
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        // La casilla activa se redondea más (como el `shapeMorph` de Harmonix).
        borderRadius: BorderRadius.circular(current ? w / 2.6 : HxRadius.mV),
        border: Border.all(color: border, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : HxMotion.dFxSlow,
        switchInCurve: HxMotion.emphasizedDecel,
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(a),
            child: c,
          ),
        ),
        child: Text(
          has ? text[i] : '',
          key: ValueKey('$i:${has ? text[i] : ''}'),
          style: TextStyle(
            fontFamily: AppTheme.fontNum,
            fontSize: (w * 0.6).clamp(20.0, 30.0),
            fontWeight: FontWeight.w500,
            fontVariations: const [FontVariation('wght', 500)],
            color: fg,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Muestra de color (selector de semilla fija): círculo de 40 px que se vuelve cookie
/// con un check al elegirlo.
class HxSwatch extends StatelessWidget {
  const HxSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      selected: selected,
      button: true,
      label: tooltip,
      child: HxSurface(
        onTap: onTap,
        tooltip: tooltip,
        color: color,
        duration: HxMotion.dSpringFast,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(selected ? 14 : 22),
          side: BorderSide(
            color: selected ? cs.onSurface : cs.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1 : 0,
              duration: HxMotion.dSpringFast,
              curve: HxMotion.springFast,
              child: HxIcon(Symbols.check_rounded, size: 22, color: onColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila con casilla (selección múltiple, p. ej. equipos Bluetooth del carro).
class HxCheckRow extends StatelessWidget {
  const HxCheckRow({
    super.key,
    required this.icon,
    required this.title,
    required this.checked,
    required this.onChanged,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = checked ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      checked: checked,
      label: title,
      child: AnimatedContainer(
        duration: HxMotion.dFxSlow,
        curve: HxMotion.standard,
        decoration: BoxDecoration(
          color: checked ? cs.secondaryContainer : Colors.transparent,
          borderRadius: HxRadius.l,
        ),
        child: HxSurface(
          onTap: () => onChanged(!checked),
          contentColor: fg,
          shape: RoundedRectangleBorder(borderRadius: HxRadius.l),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                HxIcon(
                  icon,
                  size: 22,
                  color: checked
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                  filled: checked,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hxText(16, weight: FontWeight.w500, color: fg),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HxType.bodyS(
                            checked
                                ? cs.onSecondaryContainer.withValues(alpha: 0.8)
                                : cs.onSurfaceVariant,
                          ).copyWith(fontFamily: AppTheme.fontNum),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Check(checked: checked),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: HxMotion.dFxSlow,
      curve: HxMotion.standard,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(checked ? 7 : 4),
        border: Border.all(color: checked ? cs.primary : cs.outline, width: 2),
      ),
      child: AnimatedScale(
        scale: checked ? 1 : 0,
        duration: HxMotion.dSpringFast,
        curve: HxMotion.springFast,
        child: Icon(Symbols.check_rounded, size: 16, color: cs.onPrimary),
      ),
    );
  }
}
