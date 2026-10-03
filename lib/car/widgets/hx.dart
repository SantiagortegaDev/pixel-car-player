import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Primitivas visuales de Harmonix v2 (web/src/app.css + componentes chicos) para la
/// pantalla del carro: íconos Material Symbols Rounded, botones con `shapeMorph`,
/// chips, píldoras del selector, botones `.mbtn`, `text-in` y portada con fundido.

extension HxContext on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

/// Cambia el peso de un estilo de Google Sans Flex (fuente variable: hay que mover
/// también el eje `wght`).
TextStyle hxWeight(TextStyle? s, int weight) => (s ?? const TextStyle()).copyWith(
  fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

/// Ícono Material Symbols Rounded con FILL/wght como en Harmonix (`.icon`, `.filled`).
class HxIcon extends StatelessWidget {
  const HxIcon(this.icon, {super.key, this.size = 24, this.fill = false, this.weight, this.color});
  final IconData icon;
  final double size;
  final bool fill;
  final double? weight;
  final Color? color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: fill ? 1 : 0),
    duration: const Duration(milliseconds: 350),
    curve: HxMotion.standard,
    builder: (_, f, _) =>
        Icon(icon, size: size, fill: f, weight: weight ?? (fill ? 500 : 400), opticalSize: 24, color: color),
  );
}

/// Superficie táctil con ripple MD3 (10 % del color del contenido) recortada a [radius].
class _Tap extends StatelessWidget {
  const _Tap({required this.radius, required this.fg, required this.onTap, required this.child, this.onHighlight});
  final double radius;
  final Color fg;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHighlight;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      onHighlightChanged: onHighlight,
      splashFactory: InkRipple.splashFactory,
      splashColor: fg.withValues(alpha: 0.1),
      highlightColor: fg.withValues(alpha: 0.1),
      hoverColor: fg.withValues(alpha: 0.08),
      focusColor: fg.withValues(alpha: 0.1),
      child: child,
    ),
  );
}

/// Mantiene el estado "presionado" para los `:active` de CSS.
mixin _Pressed<T extends StatefulWidget> on State<T> {
  bool pressed = false;
  void setPressed(bool v) {
    if (v != pressed) setState(() => pressed = v);
  }
}

/// `.icon-btn` de NowPlaying: 48 px, redondo, `onSurfaceVariant`; al presionar el radio
/// pasa a 8 px (DefaultEffects, 200 ms).
class HxIconButton extends StatefulWidget {
  const HxIconButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.fill = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool fill;

  @override
  State<HxIconButton> createState() => _HxIconButtonState();
}

class _HxIconButtonState extends State<HxIconButton> with _Pressed {
  @override
  Widget build(BuildContext context) {
    final fg = context.cs.onSurfaceVariant;
    return Tooltip(
      message: widget.tooltip,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: pressed ? HxRadius.sV : 24),
        duration: HxMotion.dFx,
        curve: HxMotion.fx,
        builder: (_, r, child) => _Tap(radius: r, fg: fg, onTap: widget.onTap, onHighlight: setPressed, child: child!),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: HxIcon(widget.icon, color: fg, fill: widget.fill),
          ),
        ),
      ),
    );
  }
}

/// `.chip` de NowPlaying (36 px, borde outline-variant, label-l). `on` = secondaryContainer.
class HxChip extends StatelessWidget {
  const HxChip({super.key, required this.icon, required this.label, this.on = false, this.onTap, this.maxWidth});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = on ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Semantics(
      button: onTap != null,
      toggled: on,
      child: AnimatedContainer(
        duration: HxMotion.dFxSlow,
        curve: HxMotion.fxSlow,
        height: 36,
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        decoration: BoxDecoration(
          color: on ? cs.secondaryContainer : cs.secondaryContainer.withValues(alpha: 0),
          borderRadius: HxRadius.s,
          border: Border.all(color: on ? cs.outlineVariant.withValues(alpha: 0) : cs.outlineVariant),
        ),
        child: _Tap(
          radius: HxRadius.sV - 1,
          fg: fg,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 15, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HxIcon(icon, size: 20, color: fg, fill: on),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.labelLarge?.copyWith(color: fg),
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

/// Píldora del selector Letra / A continuación (chip de filtro MD3, 40 px).
class HxPill extends StatelessWidget {
  const HxPill({super.key, required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected ? cs.onSecondary : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: HxMotion.dFxSlow,
        curve: HxMotion.fxSlow,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? cs.secondary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _Tap(
          radius: 20,
          fg: fg,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HxIcon(icon, size: 20, color: fg, fill: selected),
                const SizedBox(width: 8),
                Text(label, maxLines: 1, style: context.tt.labelLarge?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum HxButtonKind { filled, tonal, text, outlined }

/// Botón común `.mbtn` (relleno, tonal, texto, con borde): píldora real; al presionar el
/// radio baja a 8 px.
class HxButton extends StatefulWidget {
  const HxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = HxButtonKind.filled,
    this.height = 40,
    this.danger = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final HxButtonKind kind;
  final double height;
  final bool danger;

  @override
  State<HxButton> createState() => _HxButtonState();
}

class _HxButtonState extends State<HxButton> with _Pressed {
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = widget.height;
    final (bg, fg) = switch (widget.kind) {
      HxButtonKind.filled => (cs.primary, cs.onPrimary),
      HxButtonKind.tonal => (cs.secondaryContainer, cs.onSecondaryContainer),
      HxButtonKind.text => (Colors.transparent, widget.danger ? cs.error : cs.primary),
      HxButtonKind.outlined => (Colors.transparent, cs.primary),
    };
    final disabled = widget.onTap == null;
    return Opacity(
      opacity: disabled ? 0.38 : 1,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: pressed ? HxRadius.sV : h / 2),
        duration: HxMotion.dFx,
        curve: HxMotion.standard,
        builder: (_, r, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(r),
            border: widget.kind == HxButtonKind.outlined ? Border.all(color: cs.outline) : null,
          ),
          child: _Tap(radius: r, fg: fg, onTap: widget.onTap, onHighlight: setPressed, child: child!),
        ),
        child: SizedBox(
          height: h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.kind == HxButtonKind.text ? 12 : 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Transform.translate(
                    offset: const Offset(-8, 0),
                    child: HxIcon(widget.icon!, size: h >= 48 ? 20 : 18, color: fg),
                  ),
                ],
                Text(
                  widget.label,
                  maxLines: 1,
                  style: context.tt.labelLarge?.copyWith(color: fg, fontSize: h >= 48 ? 15 : 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `text-in` de StyledText: lo nuevo entra con fundido y 6 px de desplazamiento.
/// Dale una `key` distinta para que vuelva a animar (como `{#key}`).
class HxTextIn extends StatefulWidget {
  const HxTextIn({super.key, required this.child, this.offset = 6});
  final Widget child;
  final double offset;

  @override
  State<HxTextIn> createState() => _HxTextInState();
}

class _HxTextInState extends State<HxTextIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: HxMotion.dFxSlow)..forward();
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: HxMotion.fxSlow);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, child) => Opacity(
      opacity: _a.value,
      child: Transform.translate(offset: Offset(0, widget.offset * (1 - _a.value)), child: child),
    ),
    child: widget.child,
  );
}

/// Portada (FadeImage de Caelestia): la imagen aparece con un fundido sobre
/// `surfaceContainerHighest`; sin imagen, una nota musical.
class HxCover extends StatelessWidget {
  const HxCover({super.key, required this.bytes, this.asset, this.iconSize = 48});
  final Uint8List? bytes;
  final String? asset;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final ImageProvider? img = bytes != null
        ? MemoryImage(bytes!)
        : asset != null
        ? AssetImage(asset!)
        : null;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: HxIcon(Symbols.music_note_rounded, size: iconSize, fill: true, color: cs.onSurfaceVariant),
          ),
          if (img != null)
            Image(
              image: img,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (_, child, frame, sync) => sync
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: HxMotion.dFxSlow,
                      curve: HxMotion.fxSlow,
                      child: child,
                    ),
            ),
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Nombre legible de la app de música.
String? sourceAppName(String? pkg) => switch (pkg) {
  null || '' => null,
  'com.spotify.music' => 'Spotify',
  'com.google.android.apps.youtube.music' => 'YouTube Music',
  'com.apple.android.music' => 'Apple Music',
  'deezer.android.app' => 'Deezer',
  'com.amazon.mp3' => 'Amazon Music',
  'com.soundcloud.android' => 'SoundCloud',
  'com.aspiro.tidal' => 'TIDAL',
  _ => pkg.split('.').last,
};
