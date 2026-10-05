import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Piezas base de Harmonix v2 (web/src/app.css): texto, íconos y la capa de estado
/// con ripple (`lib/ripple.js` + `.state`).

/// Vibración al tocar (ajuste "Vibración" del celular). Apagada por defecto: el modo
/// celular la enciende según sus preferencias.
class HxHaptics {
  HxHaptics._();
  static bool enabled = false;

  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void confirm() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void error() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}

/// Estilo de texto con Google Sans Flex (peso real por eje `wght`, `ROND` opcional).
TextStyle hxText(
  double size, {
  FontWeight weight = FontWeight.w400,
  double height = 1.45,
  Color? color,
  double letterSpacingEm = 0,
  double? rond,
}) => TextStyle(
  fontFamily: AppTheme.font,
  fontSize: size,
  fontWeight: weight,
  height: height,
  color: color,
  letterSpacing: letterSpacingEm * size,
  fontVariations: [
    FontVariation('wght', weight.value.toDouble()),
    if (rond != null) FontVariation('ROND', rond),
  ],
);

/// Tokens tipográficos de Caelestia (`--t-*`).
class HxType {
  HxType._();
  static TextStyle headlineS([Color? c]) =>
      hxText(24, weight: FontWeight.w500, height: 1.25, color: c);
  static TextStyle titleL([Color? c]) =>
      hxText(22, weight: FontWeight.w500, height: 1.3, color: c);
  static TextStyle titleM([Color? c]) =>
      hxText(16, weight: FontWeight.w500, height: 1.4, color: c);
  static TextStyle bodyL([Color? c]) => hxText(16, height: 1.5, color: c);
  static TextStyle bodyM([Color? c]) => hxText(14, height: 1.45, color: c);
  static TextStyle bodyS([Color? c]) => hxText(12, height: 1.4, color: c);
  static TextStyle labelL([Color? c]) =>
      hxText(14, weight: FontWeight.w500, height: 1.3, color: c);
  static TextStyle labelM([Color? c]) =>
      hxText(12, weight: FontWeight.w500, height: 1.3, color: c);

  /// Saludo grande del inicio (`.home h1`): 400, -0.03em, ROND 100.
  static TextStyle greeting(double size, [Color? c]) =>
      hxText(size, height: 1.05, color: c, letterSpacingEm: -0.03, rond: 100);

  /// Título de página (`SettingsView h1`): 400 45px/1.1, -0.02em.
  static TextStyle pageTitle([Color? c]) =>
      hxText(45, height: 1.1, color: c, letterSpacingEm: -0.02);
}

/// Ícono Material Symbols Rounded como `.icon` / `.icon.filled` de Harmonix.
class HxIcon extends StatelessWidget {
  const HxIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.filled = false,
    this.weight,
  });
  final IconData icon;
  final double size;
  final Color? color;
  final bool filled;
  final double? weight;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: filled ? 1 : 0),
    duration: const Duration(milliseconds: 350),
    curve: HxMotion.standard,
    builder: (context, f, _) => Icon(
      icon,
      size: size,
      color: color,
      fill: f,
      weight: weight ?? (400 + 100 * f),
      opticalSize: 24,
    ),
  );
}

/// Superficie pulsable con la capa de estado de MD3 (hover 8 %, presionado 10 %) y el
/// ripple que nace donde se tocó. El color y la forma se animan (200 ms).
class HxSurface extends StatelessWidget {
  const HxSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onHighlightChanged,
    this.color = Colors.transparent,
    this.contentColor,
    this.shape = const RoundedRectangleBorder(),
    this.duration = HxMotion.dFxSlow,
    this.tooltip,
  });
  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHighlightChanged;
  final Color color;
  final Color? contentColor;
  final ShapeBorder shape;
  final Duration duration;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = contentColor ?? DefaultTextStyle.of(context).style.color;
    final base = fg ?? Theme.of(context).colorScheme.onSurface;
    Widget w = Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      animationDuration: duration,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HxHaptics.tap();
                onTap!();
              },
        onHighlightChanged: onHighlightChanged,
        customBorder: shape,
        splashFactory: InkRipple.splashFactory,
        splashColor: base.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        overlayColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return base.withValues(alpha: 0.10);
          }
          if (s.contains(WidgetState.hovered)) {
            return base.withValues(alpha: 0.08);
          }
          if (s.contains(WidgetState.focused)) {
            return base.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
        child: contentColor == null
            ? child
            : IconTheme.merge(
                data: IconThemeData(color: contentColor),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: contentColor),
                  child: child,
                ),
              ),
      ),
    );
    if (tooltip != null) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

/// Mientras se mantiene presionado (para el `shapeMorph`: radio chico al presionar).
mixin HxPressState<T extends StatefulWidget> on State<T> {
  bool pressed = false;
  void setPressed(bool v) {
    if (v != pressed) setState(() => pressed = v);
  }
}
