import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';

/// Variantes de `.mbtn` de Harmonix.
enum HxButtonKind { filled, tonal, text, outlined }

/// Botón común de MD3 de Harmonix (`.mbtn`): 40 px, píldora real (alto/2) que pasa a
/// 8 px al presionar.
class HxButton extends StatefulWidget {
  const HxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = HxButtonKind.filled,
    this.icon,
    this.trailingIcon,
    this.height = 40,
  });
  final String label;
  final VoidCallback? onPressed;
  final HxButtonKind kind;
  final IconData? icon;
  final IconData? trailingIcon;
  final double height;

  @override
  State<HxButton> createState() => _HxButtonState();
}

class _HxButtonState extends State<HxButton> with HxPressState {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (widget.kind) {
      HxButtonKind.filled => (cs.primary, cs.onPrimary),
      HxButtonKind.tonal => (cs.secondaryContainer, cs.onSecondaryContainer),
      HxButtonKind.text => (Colors.transparent, cs.primary),
      HxButtonKind.outlined => (Colors.transparent, cs.primary),
    };
    final h = widget.height;
    final r = pressed ? HxRadius.sV : h / 2;
    final side = widget.kind == HxButtonKind.outlined
        ? BorderSide(color: cs.outline)
        : BorderSide.none;
    final padH = widget.kind == HxButtonKind.text ? 12.0 : 24.0;
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: IgnorePointer(
        ignoring: !enabled,
        child: HxSurface(
          onTap: widget.onPressed,
          onHighlightChanged: setPressed,
          color: bg,
          contentColor: fg,
          duration: HxMotion.dFx,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r),
            side: side,
          ),
          child: SizedBox(
            height: h,
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.icon != null ? padH - 8 : padH,
                right: widget.trailingIcon != null ? padH - 8 : padH,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    HxIcon(widget.icon!, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: HxType.labelL(fg),
                    maxLines: 1,
                    softWrap: false,
                  ),
                  if (widget.trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    HxIcon(widget.trailingIcon!, size: 18, color: fg),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón grande "play" de `Controls.svelte`: primary con radio 12 cuando está activo,
/// surfaceContainerHighest en píldora cuando no; 8 px al presionar.
class HxBigButton extends StatefulWidget {
  const HxBigButton({
    super.key,
    required this.checked,
    required this.onPressed,
    required this.child,
    this.height = 56,
  });
  final bool checked;
  final VoidCallback? onPressed;
  final Widget child;
  final double height;

  @override
  State<HxBigButton> createState() => _HxBigButtonState();
}

class _HxBigButtonState extends State<HxBigButton> with HxPressState {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.checked ? cs.primary : cs.surfaceContainerHighest;
    final fg = widget.checked ? cs.onPrimary : cs.onSurfaceVariant;
    final r = pressed
        ? HxRadius.sV
        : (widget.checked ? HxRadius.mV : widget.height / 2);
    return HxSurface(
      onTap: widget.onPressed == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onPressed!();
            },
      onHighlightChanged: setPressed,
      color: bg,
      contentColor: fg,
      duration: HxMotion.dFx,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Center(child: widget.child),
      ),
    );
  }
}

/// Botón de ícono redondo (`.act` / `.icon-btn`): 40 px, radio 12 al presionar.
class HxIconButton extends StatefulWidget {
  const HxIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 40,
    this.iconSize = 22,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  State<HxIconButton> createState() => _HxIconButtonState();
}

class _HxIconButtonState extends State<HxIconButton> with HxPressState {
  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return HxSurface(
      onTap: widget.onPressed,
      onHighlightChanged: setPressed,
      contentColor: c,
      tooltip: widget.tooltip,
      duration: HxMotion.dSpringFast,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          pressed ? HxRadius.mV : widget.size / 2,
        ),
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: Center(
          child: HxIcon(widget.icon, size: widget.iconSize, color: c),
        ),
      ),
    );
  }
}

/// Switch de MD3 de Harmonix (`Switch.svelte`), solo el control.
class HxSwitch extends StatelessWidget {
  const HxSwitch({super.key, required this.value, this.pressed = false});
  final bool value;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = pressed ? 28.0 : (value ? 24.0 : 16.0);
    final left = value ? 20.0 : 6.0;
    const fx = HxMotion.dFxSlow, sp = HxMotion.dSpringFast;
    return AnimatedContainer(
      duration: fx,
      curve: HxMotion.standard,
      width: 52,
      height: 32,
      decoration: BoxDecoration(
        color: value ? cs.primary : cs.surfaceContainerHighest,
        border: Border.all(color: value ? cs.primary : cs.outline, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: sp,
            curve: HxMotion.springFast,
            left: left,
            top: (28 - size) / 2,
            width: size,
            height: size,
            child: AnimatedContainer(
              duration: fx,
              curve: HxMotion.standard,
              decoration: BoxDecoration(
                color: value ? cs.onPrimary : cs.outline,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: value
                  ? Icon(
                      Symbols.check_rounded,
                      size: 16,
                      color: cs.onPrimaryContainer,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila con etiqueta, descripción y switch (`Switch.svelte`), toda tocable.
class HxSwitchRow extends StatefulWidget {
  const HxSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<HxSwitchRow> createState() => _HxSwitchRowState();
}

class _HxSwitchRowState extends State<HxSwitchRow> with HxPressState {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      toggled: widget.value,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setPressed(true),
        onTapUp: (_) => setPressed(false),
        onTapCancel: () => setPressed(false),
        onTap: () => widget.onChanged(!widget.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: HxType.bodyL(cs.onSurface)),
                    if (widget.description != null)
                      Text(
                        widget.description!,
                        style: HxType.bodyM(cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              HxSwitch(value: widget.value, pressed: pressed),
            ],
          ),
        ),
      ),
    );
  }
}

class HxSegment<T> {
  const HxSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Botones segmentados de MD3 de Harmonix (`Segmented.svelte`), selección única con
/// check animado en el elegido.
class HxSegmented<T> extends StatelessWidget {
  const HxSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<HxSegment<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) Container(width: 1, color: cs.outline),
              Expanded(child: _seg(context, cs, options[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, ColorScheme cs, HxSegment<T> o) {
    final sel = o.value == value;
    final fg = sel ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      selected: sel,
      button: true,
      child: HxSurface(
        onTap: () => onChanged(o.value),
        color: sel ? cs.secondaryContainer : Colors.transparent,
        contentColor: fg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: HxMotion.dFxSlow,
                curve: HxMotion.standard,
                width: sel ? 18 : 0,
                child: AnimatedOpacity(
                  duration: HxMotion.dFx,
                  opacity: sel ? 1 : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: 18,
                      alignment: Alignment.centerLeft,
                      child: Icon(Symbols.check_rounded, size: 18, color: fg),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  o.label,
                  style: HxType.labelL(fg),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de Harmonix (`NowPlaying .chip`): 36 px, radio 8, borde outline-variant;
/// encendido = secondaryContainer sin borde.
class HxChip extends StatelessWidget {
  const HxChip({
    super.key,
    required this.label,
    this.icon,
    this.on = false,
    this.onTap,
    this.mono = false,
    this.tooltip,
  });
  final String label;
  final IconData? icon;
  final bool on;
  final VoidCallback? onTap;
  final bool mono;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = on ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final style = mono
        ? HxType.labelL(fg).copyWith(
            fontFamily: AppTheme.fontNum,
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : HxType.labelL(fg);
    return HxSurface(
      onTap: onTap,
      tooltip: tooltip,
      color: on ? cs.secondaryContainer : Colors.transparent,
      contentColor: fg,
      shape: RoundedRectangleBorder(
        borderRadius: HxRadius.s,
        side: BorderSide(color: on ? Colors.transparent : cs.outlineVariant),
      ),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: EdgeInsets.only(left: icon != null ? 10 : 16, right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                HxIcon(icon!, size: 20, color: fg, filled: on),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
