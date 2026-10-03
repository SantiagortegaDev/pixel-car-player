import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Piezas de `SettingsView.svelte` de Harmonix v2 (secciones con encabezado en primary,
/// tarjetas `surfaceContainer` radio 28, `Switch.svelte`, `Segmented.svelte`, campos
/// rellenos, `Dialog.svelte`) más un slider MD3 Expressive, selector de formas y colores.
/// Todo con objetivos táctiles grandes (≥ 48 px) para usar en el carro.

/// Sección: ícono + título en primary (y "Restablecer" opcional) sobre una tarjeta.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.onReset,
    this.resetEnabled = true,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  final VoidCallback? onReset;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, 0, onReset == null ? 8 : 0, onReset == null ? 10 : 4),
            child: Row(
              children: [
                HxIcon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: context.tt.titleMedium?.copyWith(color: cs.primary)),
                ),
                if (onReset != null)
                  HxButton(
                    label: 'Restablecer',
                    icon: Symbols.restart_alt_rounded,
                    kind: HxButtonKind.text,
                    height: 40,
                    onTap: resetEnabled ? onReset : null,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: HxRadius.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.item`: etiqueta, descripción y un control debajo.
class SettingsItem extends StatelessWidget {
  const SettingsItem({super.key, required this.label, this.desc, required this.child, this.trailing});
  final String label;
  final String? desc;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
              ),
              ?trailing,
            ],
          ),
          if (desc != null) ...[
            const SizedBox(height: 4),
            Text(desc!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Texto aclaratorio dentro de una tarjeta (`.desc.block`).
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: HxIcon(icon!, size: 20, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(text, style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Fila con texto a la izquierda y una acción (botón) a la derecha.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.desc,
    required this.action,
    this.warning = false,
  });
  final IconData icon;
  final String label;
  final String? desc;
  final Widget action;

  /// Resalta el ícono (permiso faltante, etc.).
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: warning ? cs.errorContainer : cs.secondaryContainer,
              borderRadius: HxRadius.m,
            ),
            child: HxIcon(icon, size: 22, color: warning ? cs.onErrorContainer : cs.onSecondaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                if (desc != null) Text(desc!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }
}

/// Estado con ícono (`.status` de SettingsView): primary si está bien.
class SettingsStatus extends StatelessWidget {
  const SettingsStatus({super.key, required this.ok, required this.text, this.okIcon, this.offIcon});
  final bool ok;
  final String text;
  final IconData? okIcon;
  final IconData? offIcon;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final color = ok ? cs.primary : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HxIcon(
          ok ? (okIcon ?? Symbols.check_circle_rounded) : (offIcon ?? Symbols.info_rounded),
          size: 18,
          fill: true,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: context.tt.labelLarge?.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// Botones segmentados de MD3 (`Segmented.svelte`), con check en el elegido. 48 px.
class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    const h = 48.0;
    return Container(
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(h / 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: cs.outline),
            Expanded(child: _segment(context, options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, (T, String) o) {
    final cs = context.cs;
    final sel = o.$1 == value;
    final fg = sel ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: sel,
      button: true,
      child: AnimatedContainer(
        duration: HxMotion.dFxSlow,
        curve: HxMotion.standard,
        color: sel ? cs.secondaryContainer : cs.secondaryContainer.withValues(alpha: 0),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onChanged(o.$1),
            splashColor: fg.withValues(alpha: 0.1),
            highlightColor: fg.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: HxMotion.dFxSlow,
                      curve: HxMotion.standard,
                      child: sel
                          ? Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: HxIcon(Symbols.check_rounded, size: 18, color: fg),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Flexible(
                      child: Text(
                        o.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tt.labelLarge?.copyWith(color: fg, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch de MD3 (`Switch.svelte`): fila con etiqueta + descripción y el control propio.
class SettingsSwitch extends StatefulWidget {
  const SettingsSwitch({
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
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final on = widget.value;
    final handle = _pressed ? 28.0 : (on ? 24.0 : 16.0);
    // Centro del cursor: 16 px (apagado) / 36 px (encendido) desde el borde izquierdo.
    final cx = on ? 36.0 : 16.0;
    return Semantics(
      toggled: on,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          widget.onChanged(!on);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                      if (widget.description != null)
                        Text(widget.description!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AnimatedContainer(
                  duration: HxMotion.dFxSlow,
                  curve: HxMotion.standard,
                  width: 52,
                  height: 32,
                  decoration: BoxDecoration(
                    color: on ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: on ? cs.primary : cs.outline, width: 2),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositioned(
                        duration: HxMotion.dSpringFast,
                        curve: HxMotion.springFast,
                        left: cx - 2 - handle / 2,
                        top: (28 - handle) / 2,
                        width: handle,
                        height: handle,
                        child: AnimatedContainer(
                          duration: HxMotion.dFxSlow,
                          curve: HxMotion.standard,
                          decoration: BoxDecoration(color: on ? cs.onPrimary : cs.outline, shape: BoxShape.circle),
                          child: on
                              ? Center(child: HxIcon(Symbols.check_rounded, size: 16, color: cs.onPrimaryContainer))
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slider de MD3 Expressive (como el de progreso de Harmonix, sin onda): pista activa
/// gruesa en primary, cursor de 4 px, pista restante en secondaryContainer con punto
/// final. A los lados, botones − / + para pasos exactos (útil en el carro).
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.label,
    required this.value,
    required this.range,
    required this.onChanged,
    this.desc,
    this.format,
    this.defaultValue,
  });

  final String label;
  final String? desc;
  final double value;
  final CarRange range;
  final ValueChanged<double> onChanged;
  final String Function(double v)? format;

  /// Si se pasa, se marca en la pista.
  final double? defaultValue;

  double _snap(double v) {
    final s = range.step;
    final snapped = (((v - range.min) / s).round() * s + range.min);
    // Evita 0.30000000004.
    return range.clamp(double.parse(snapped.toStringAsFixed(4)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final text = format?.call(value) ?? value.toStringAsFixed(range.step < 1 ? 2 : 0);
    return Semantics(
      slider: true,
      label: label,
      value: text,
      increasedValue: format?.call(_snap(value + range.step)),
      decreasedValue: format?.call(_snap(value - range.step)),
      onIncrease: () => onChanged(_snap(value + range.step)),
      onDecrease: () => onChanged(_snap(value - range.step)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: HxRadius.s),
                  child: Text(
                    text,
                    style: AppTheme.numStyle(context, size: 14).copyWith(color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            if (desc != null) ...[
              const SizedBox(height: 4),
              Text(desc!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _StepButton(
                  icon: Symbols.remove_rounded,
                  tooltip: 'Menos',
                  onTap: value <= range.min ? null : () => onChanged(_snap(value - range.step)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Track(
                    frac: ((value - range.min) / (range.max - range.min)).clamp(0.0, 1.0),
                    mark: defaultValue == null
                        ? null
                        : ((defaultValue! - range.min) / (range.max - range.min)).clamp(0.0, 1.0),
                    onFrac: (f) => onChanged(_snap(range.min + f * (range.max - range.min))),
                  ),
                ),
                const SizedBox(width: 8),
                _StepButton(
                  icon: Symbols.add_rounded,
                  tooltip: 'Más',
                  onTap: value >= range.max ? null : () => onChanged(_snap(value + range.step)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = cs.onSecondaryContainer;
    return Opacity(
      opacity: onTap == null ? 0.38 : 1,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: cs.secondaryContainer,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: fg.withValues(alpha: 0.1),
            highlightColor: fg.withValues(alpha: 0.1),
            child: SizedBox.square(
              dimension: 48,
              child: Center(child: HxIcon(icon, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Track extends StatefulWidget {
  const _Track({required this.frac, required this.onFrac, this.mark});
  final double frac;
  final double? mark;
  final ValueChanged<double> onFrac;

  @override
  State<_Track> createState() => _TrackState();
}

class _TrackState extends State<_Track> {
  bool _drag = false;

  static const _gap = 6.0, _handle = 4.0;

  double _fracAt(double x, double w) => ((x - _gap) / math.max(1, w - _handle - _gap * 2)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => widget.onFrac(_fracAt(d.localPosition.dx, w)),
          onHorizontalDragStart: (d) {
            setState(() => _drag = true);
            widget.onFrac(_fracAt(d.localPosition.dx, w));
          },
          onHorizontalDragUpdate: (d) => widget.onFrac(_fracAt(d.localPosition.dx, w)),
          onHorizontalDragEnd: (_) => setState(() => _drag = false),
          onHorizontalDragCancel: () => setState(() => _drag = false),
          child: SizedBox(
            height: 48,
            width: w,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _drag ? 1 : 0),
              duration: HxMotion.dSpringFast,
              curve: HxMotion.springFast,
              builder: (_, d, _) => CustomPaint(
                painter: _TrackPainter(
                  frac: widget.frac,
                  mark: widget.mark,
                  active: cs.primary,
                  inactive: cs.secondaryContainer,
                  dot: cs.onSecondaryContainer,
                  drag: d,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.frac,
    required this.mark,
    required this.active,
    required this.inactive,
    required this.dot,
    required this.drag,
  });
  final double frac;
  final double? mark;
  final Color active, inactive, dot;
  final double drag;

  @override
  void paint(Canvas canvas, Size size) {
    const th = 16.0, gap = _TrackState._gap, handle = _TrackState._handle;
    final w = size.width, cy = size.height / 2;
    final full = math.max(0.0, w - handle - gap * 2);
    final hx = gap + frac * full;
    const outer = Radius.circular(th / 2), inner = Radius.circular(2);
    // Pista activa.
    if (hx - gap > 0) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(0, cy - th / 2, hx - gap, cy + th / 2),
          topLeft: outer,
          bottomLeft: outer,
          topRight: inner,
          bottomRight: inner,
        ),
        Paint()..color = active,
      );
    }
    // Pista restante.
    final rx = hx + handle + gap;
    if (w - rx > 0) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(rx, cy - th / 2, w, cy + th / 2),
          topLeft: inner,
          bottomLeft: inner,
          topRight: outer,
          bottomRight: outer,
        ),
        Paint()..color = inactive,
      );
      if (w - rx > 12) canvas.drawCircle(Offset(w - th / 2, cy), 2, Paint()..color = dot);
    }
    // Marca del valor de fábrica.
    final m = mark;
    if (m != null && (m - frac).abs() > 0.02) {
      final mx = gap + m * full + handle / 2;
      canvas.drawCircle(Offset(mx, cy), 2.5, Paint()..color = mx < hx ? inactive : active.withValues(alpha: 0.7));
    }
    // Cursor.
    final hh = 44.0 + 4 * drag;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(hx, cy - hh / 2, handle, hh), const Radius.circular(2)),
      Paint()..color = active,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.frac != frac ||
      old.mark != mark ||
      old.active != active ||
      old.inactive != inactive ||
      old.dot != dot ||
      old.drag != drag;
}

/// Campo de texto relleno de MD3 (`.field`): 56 px, surfaceContainerHighest, línea abajo.
class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    this.hint,
    this.helper,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.suffix,
    this.monospace = false,
    this.fieldKey,
  });
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final Widget? suffix;
  final bool monospace;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    const radius = BorderRadius.vertical(top: Radius.circular(4));
    final style = (monospace ? tt.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 14) : tt.bodyLarge)?.copyWith(
      color: cs.onSurface,
      fontSize: monospace ? 14 : 18,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          minLines: 1,
          style: style,
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: style?.copyWith(color: cs.onSurfaceVariant),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            isDense: false,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.onSurfaceVariant),
            ),
            enabledBorder: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.onSurfaceVariant),
            ),
            focusedBorder: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(helper!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// Colores fijos sugeridos (semillas de MD3; los de Harmonix + algunos más).
const kCarSwatches = [
  0xFF3F6D8E,
  0xFF6750A4,
  0xFFB3261E,
  0xFFE8743B,
  0xFFD4A017,
  0xFF386A20,
  0xFF006A6A,
  0xFF7D5260,
  0xFF0061A4,
  0xFFC2185B,
  0xFF00897B,
  0xFF5D4037,
];

/// Círculos de color (`.swatches` de SettingsView): el elegido pasa a cuadrado redondeado
/// con un check.
class ColorSwatches extends StatelessWidget {
  const ColorSwatches({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in kCarSwatches)
          _Swatch(color: Color(c), selected: (value & 0xFFFFFF) == (c & 0xFFFFFF), onTap: () => onChanged(c)),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color ${colorHex(color.toARGB32())}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? HxRadius.mV : 24),
        duration: HxMotion.dFx,
        curve: HxMotion.standard,
        builder: (_, r, _) => Material(
          color: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: 48,
              child: selected ? Center(child: HxIcon(Symbols.check_rounded, size: 22, color: fg)) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de formas MD3 (cuadrícula): la forma en primaryContainer; la elegida sobre
/// secondaryContainer y en primary.
class ShapePicker extends StatelessWidget {
  const ShapePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const labels = {
    'circle': 'Círculo',
    'cookie4': 'Galleta 4',
    'cookie6': 'Galleta 6',
    'cookie7': 'Galleta 7',
    'cookie9': 'Galleta 9',
    'cookie12': 'Galleta 12',
    'sunny': 'Sol',
    'verySunny': 'Sol intenso',
    'softBurst': 'Destello',
    'clover4': 'Trébol 4',
    'clover8': 'Trébol 8',
    'pentagon': 'Pentágono',
    'triangle': 'Triángulo',
    'gem': 'Gema',
    'square': 'Cuadrado',
    'pill': 'Píldora',
    'oval': 'Óvalo',
  };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in M3Shape.all.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            label: labels[e.key] ?? e.key,
            child: Tooltip(
              message: labels[e.key] ?? e.key,
              child: AnimatedContainer(
                duration: HxMotion.dFxSlow,
                curve: HxMotion.standard,
                decoration: BoxDecoration(
                  color: e.key == value ? cs.secondaryContainer : cs.surfaceContainerHigh,
                  borderRadius: e.key == value ? HxRadius.l : HxRadius.xl,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: RoundedRectangleBorder(borderRadius: e.key == value ? HxRadius.l : HxRadius.xl),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onChanged(e.key),
                    child: SizedBox.square(
                      dimension: 64,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipPath(
                          clipper: M3ShapeClipper(e.value),
                          child: ColoredBox(color: e.key == value ? cs.primary : cs.primaryContainer),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tarjetas de opción con una muestra (variantes de esquema, color de barras…).
class ChoiceTiles<T> extends StatelessWidget {
  const ChoiceTiles({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.minWidth = 150,
  });
  final T value;

  /// (valor, etiqueta, muestra de colores).
  final List<(T, String, List<Color>)> options;
  final ValueChanged<T> onChanged;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = math.max(1, ((c.maxWidth + 8) / (minWidth + 8)).floor());
        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              SizedBox(
                width: w,
                child: Semantics(
                  button: true,
                  selected: o.$1 == value,
                  child: AnimatedContainer(
                    duration: HxMotion.dFxSlow,
                    curve: HxMotion.standard,
                    decoration: BoxDecoration(
                      color: o.$1 == value ? cs.secondaryContainer : cs.surfaceContainerHigh,
                      borderRadius: o.$1 == value ? HxRadius.m : HxRadius.l,
                      border: Border.all(
                        color: o.$1 == value ? cs.secondary : cs.secondaryContainer.withValues(alpha: 0),
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      borderRadius: o.$1 == value ? HxRadius.m : HxRadius.l,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onChanged(o.$1),
                        child: SizedBox(
                          height: 56,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                if (o.$3.isNotEmpty) ...[
                                  _Dots(
                                    colors: o.$3,
                                    ring: o.$1 == value ? cs.secondaryContainer : cs.surfaceContainerHigh,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    o.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.tt.labelLarge?.copyWith(
                                      fontSize: 14,
                                      color: o.$1 == value ? cs.onSecondaryContainer : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Muestra de colores superpuestos (círculos de 22 px que se pisan 8 px).
class _Dots extends StatelessWidget {
  const _Dots({required this.colors, required this.ring});
  final List<Color> colors;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    const d = 20.0, step = 11.0;
    return SizedBox(
      width: d + step * (colors.length - 1),
      height: d,
      child: Stack(
        children: [
          for (final (i, c) in colors.indexed)
            Positioned(
              left: step * i,
              top: 0,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Diálogo de MD3 (`Dialog.svelte`): velo 40 %, contenedor surfaceContainerHigh radio 28,
/// entra con la curva emphasized (escala 0,9 × 0,7 desde arriba).
Future<T?> showHxDialog<T>(
  BuildContext context, {
  required String title,
  IconData? icon,
  required Widget Function(BuildContext context) content,
  required List<Widget> Function(BuildContext context) actions,
  double maxWidth = 560,
}) {
  final theme = Theme.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (ctx, _, _) => Theme(
      data: theme,
      child: Builder(
        builder: (ctx) {
          final cs = ctx.cs;
          final mq = MediaQuery.of(ctx);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(maxWidth, mq.size.width - 32),
                    maxHeight: math.min(720, mq.size.height - 48),
                  ),
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: HxRadius.xl),
                    elevation: 12,
                    shadowColor: Colors.black.withValues(alpha: 0.6),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (icon != null) ...[
                            Center(child: HxIcon(icon, color: cs.secondary)),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            title,
                            textAlign: icon != null ? TextAlign.center : TextAlign.start,
                            style: ctx.tt.headlineSmall?.copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: DefaultTextStyle(
                              style: ctx.tt.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
                              child: SingleChildScrollView(child: content(ctx)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions(ctx)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: HxMotion.emphasizedDecel, reverseCurve: HxMotion.emphasizedAccel);
      return FadeTransition(
        opacity: c,
        child: AnimatedBuilder(
          animation: c,
          builder: (_, child) => Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.diagonal3Values(0.9 + 0.1 * c.value, 0.7 + 0.3 * c.value, 1),
            child: child,
          ),
          child: child,
        ),
      );
    },
  );
}

/// Snackbar corto con el estilo de la app.
void showHxSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// Copia al portapapeles (ignora errores en plataformas sin portapapeles).
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> pasteText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } catch (_) {
    return null;
  }
}
