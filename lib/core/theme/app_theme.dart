import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

/// Tokens Material 3 de Harmonix v2 (web/src/app.css + lib/theme.js), portados a Flutter.
///
/// - Color: esquema dinámico **Tonal Spot** generado desde la portada (como Caelestia /
///   Android), semilla por defecto `#3f6d8e`. Nunca uses colores fijos: usa
///   `Theme.of(context).colorScheme`.
/// - Tipografía: Google Sans Flex (títulos en Medium) y Rubik para números.
/// - Forma y movimiento: [HxRadius], [HxMotion].
class AppTheme {
  AppTheme._();

  static const Color fallbackSeed = Color(0xFF3F6D8E);
  static const String font = 'Google Sans Flex';
  static const String fontNum = 'Rubik';

  /// Esquema dinámico exacto (material_color_utilities) desde una semilla. Por defecto
  /// Tonal Spot, como Android / Harmonix v2; [variant] elige otra variante de Material You.
  static ColorScheme schemeFromSeed(Color seed,
      {Brightness brightness = Brightness.dark,
      SchemeVariant variant = SchemeVariant.tonalSpot}) {
    final hct = mcu.Hct.fromInt(seed.toARGB32());
    final dark = brightness == Brightness.dark;
    final mcu.DynamicScheme s = switch (variant) {
      SchemeVariant.tonalSpot => mcu.SchemeTonalSpot(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.vibrant => mcu.SchemeVibrant(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.expressive => mcu.SchemeExpressive(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.fidelity => mcu.SchemeFidelity(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.neutral => mcu.SchemeNeutral(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.content => mcu.SchemeContent(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
      SchemeVariant.monochrome => mcu.SchemeMonochrome(sourceColorHct: hct, isDark: dark, contrastLevel: 0),
    };
    Color c(int argb) => Color(argb);
    return ColorScheme(
      brightness: brightness,
      primary: c(s.primary),
      onPrimary: c(s.onPrimary),
      primaryContainer: c(s.primaryContainer),
      onPrimaryContainer: c(s.onPrimaryContainer),
      secondary: c(s.secondary),
      onSecondary: c(s.onSecondary),
      secondaryContainer: c(s.secondaryContainer),
      onSecondaryContainer: c(s.onSecondaryContainer),
      tertiary: c(s.tertiary),
      onTertiary: c(s.onTertiary),
      tertiaryContainer: c(s.tertiaryContainer),
      onTertiaryContainer: c(s.onTertiaryContainer),
      error: c(s.error),
      onError: c(s.onError),
      errorContainer: c(s.errorContainer),
      onErrorContainer: c(s.onErrorContainer),
      surface: c(s.surface),
      onSurface: c(s.onSurface),
      surfaceDim: c(s.surfaceDim),
      surfaceBright: c(s.surfaceBright),
      surfaceContainerLowest: c(s.surfaceContainerLowest),
      surfaceContainerLow: c(s.surfaceContainerLow),
      surfaceContainer: c(s.surfaceContainer),
      surfaceContainerHigh: c(s.surfaceContainerHigh),
      surfaceContainerHighest: c(s.surfaceContainerHighest),
      onSurfaceVariant: c(s.onSurfaceVariant),
      outline: c(s.outline),
      outlineVariant: c(s.outlineVariant),
      shadow: c(s.shadow),
      scrim: c(s.scrim),
      inverseSurface: c(s.inverseSurface),
      onInverseSurface: c(s.inverseOnSurface),
      inversePrimary: c(s.inversePrimary),
      surfaceTint: c(s.surfaceTint),
    );
  }

  /// Semilla desde una imagen, igual que `seedFromImage` de Harmonix v2: se reduce a
  /// 96×96, se cuantiza (Celebi, 128 colores) y se elige con Score (como Android).
  static Future<Color> seedFromImageBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 96, targetHeight: 96);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    if (data == null) return fallbackSeed;
    final px = <int>[];
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 3) < 255) continue;
      px.add((0xFF << 24) |
          (data.getUint8(i) << 16) |
          (data.getUint8(i + 1) << 8) |
          data.getUint8(i + 2));
    }
    if (px.isEmpty) return fallbackSeed;
    final q = await mcu.QuantizerCelebi().quantize(px, 128);
    final ranked = mcu.Score.score(q.colorToCount,
        fallbackColorARGB: fallbackSeed.toARGB32());
    return Color(ranked.first);
  }

  static TextTheme textTheme(Color onSurface) {
    TextStyle t(double size, FontWeight w, double height) => TextStyle(
          fontFamily: font,
          fontSize: size,
          fontWeight: w,
          height: height,
          color: onSurface,
          fontVariations: [FontVariation('wght', w.value.toDouble())],
        );
    const m = FontWeight.w500, r = FontWeight.w400;
    // Escala de Caelestia (app.css: --t-*).
    return TextTheme(
      displayLarge: t(57, r, 1.12),
      displayMedium: t(45, r, 1.16),
      displaySmall: t(36, r, 1.22),
      headlineLarge: t(32, m, 1.2),
      headlineMedium: t(28, m, 1.2),
      headlineSmall: t(24, m, 1.25),
      titleLarge: t(22, m, 1.3),
      titleMedium: t(16, m, 1.4),
      titleSmall: t(14, m, 1.4),
      bodyLarge: t(16, r, 1.5),
      bodyMedium: t(14, r, 1.45),
      bodySmall: t(12, r, 1.4),
      labelLarge: t(14, m, 1.3),
      labelMedium: t(12, m, 1.3),
      labelSmall: t(11, r, 1.3),
    );
  }

  /// Estilo para números (tiempos): Rubik, como `--font-num`.
  static TextStyle numStyle(BuildContext context, {double size = 12}) =>
      TextStyle(
        fontFamily: fontNum,
        fontSize: size,
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData build(ColorScheme s) {
    final isDark = s.brightness == Brightness.dark;
    final text = textTheme(s.onSurface);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: s,
      brightness: s.brightness,
      fontFamily: font,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      scaffoldBackgroundColor: s.surface,
      canvasColor: s.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: HxRadius.xl),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: HxRadius.s),
        side: BorderSide(color: s.outlineVariant),
        labelStyle: text.labelLarge?.copyWith(color: s.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          side: BorderSide(color: s.outlineVariant),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            textStyle: text.labelLarge, shape: const StadiumBorder()),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: s.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: HxRadius.l),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: HxRadius.xl),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        modalBackgroundColor: s.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: s.surfaceContainer,
        indicatorColor: s.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: HxRadius.s),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData dark([ColorScheme? s]) => build(s ?? schemeFromSeed(fallbackSeed));
}

/// Variantes de esquema de Material You (Harmonix v2 `lib/theme.js` → `VARIANTS`).
enum SchemeVariant { tonalSpot, vibrant, expressive, fidelity, neutral, content, monochrome }

/// Redondeos de Caelestia / MD3 (`--r-*`).
class HxRadius {
  HxRadius._();
  static const double xsV = 4, sV = 8, mV = 12, lV = 16, liV = 20, xlV = 28, xliV = 32, xxlV = 48;
  static final xs = BorderRadius.circular(xsV);
  static final s = BorderRadius.circular(sV);
  static final m = BorderRadius.circular(mV);
  static final l = BorderRadius.circular(lV);
  static final li = BorderRadius.circular(liV);
  static final xl = BorderRadius.circular(xlV);
  static final xli = BorderRadius.circular(xliV);
  static final xxl = BorderRadius.circular(xxlV);
}

/// Curvas y duraciones de Caelestia (`--fx`, `--spring-*`, `--d-*`).
class HxMotion {
  HxMotion._();
  static const emphasizedDecel = Cubic(0.05, 0.7, 0.1, 1);
  static const emphasizedAccel = Cubic(0.3, 0, 0.8, 0.15);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const springFast = Cubic(0.3, 0, 0, 1);
  static const spring = Cubic(0.2, 0, 0, 1);
  static const fxFast = Cubic(0.31, 0.94, 0.34, 1);
  static const fx = Cubic(0.34, 0.8, 0.34, 1);
  static const fxSlow = Cubic(0.34, 0.88, 0.34, 1);
  static const dSpringFast = Duration(milliseconds: 350);
  static const dSpring = Duration(milliseconds: 500);
  static const dFxFast = Duration(milliseconds: 150);
  static const dFx = Duration(milliseconds: 200);
  static const dFxSlow = Duration(milliseconds: 300);
  static const dLarge = Duration(milliseconds: 600);
  static const dTheme = Duration(milliseconds: 900);
}

/// Transición de tema de Harmonix v2: todos los tokens a la vez, interpolados en OKLab
/// con ease-in-out cúbico durante 900 ms (lib/theme.js `applySeed`).
class HxAnimatedTheme extends StatefulWidget {
  const HxAnimatedTheme({super.key, required this.scheme, required this.child});
  final ColorScheme scheme;
  final Widget child;

  @override
  State<HxAnimatedTheme> createState() => _HxAnimatedThemeState();
}

class _HxAnimatedThemeState extends State<HxAnimatedTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: HxMotion.dTheme)
        ..addListener(_tick);
  late ColorScheme _from = widget.scheme;
  late ColorScheme _shown = widget.scheme;
  late ThemeData _theme = AppTheme.build(widget.scheme);

  static double _ease(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  void _tick() {
    final k = _ease(_c.value);
    _shown = lerpSchemeOklab(_from, widget.scheme, k);
    setState(() => _theme = AppTheme.build(_shown));
  }

  @override
  void didUpdateWidget(HxAnimatedTheme old) {
    super.didUpdateWidget(old);
    if (old.scheme != widget.scheme) {
      _from = _shown; // arranca desde lo que se ve ahora
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(data: _theme, child: widget.child);
}

ColorScheme lerpSchemeOklab(ColorScheme a, ColorScheme b, double t) {
  Color l(Color x, Color y) => oklabLerp(x, y, t);
  return ColorScheme(
    brightness: t < 0.5 ? a.brightness : b.brightness,
    primary: l(a.primary, b.primary),
    onPrimary: l(a.onPrimary, b.onPrimary),
    primaryContainer: l(a.primaryContainer, b.primaryContainer),
    onPrimaryContainer: l(a.onPrimaryContainer, b.onPrimaryContainer),
    secondary: l(a.secondary, b.secondary),
    onSecondary: l(a.onSecondary, b.onSecondary),
    secondaryContainer: l(a.secondaryContainer, b.secondaryContainer),
    onSecondaryContainer: l(a.onSecondaryContainer, b.onSecondaryContainer),
    tertiary: l(a.tertiary, b.tertiary),
    onTertiary: l(a.onTertiary, b.onTertiary),
    tertiaryContainer: l(a.tertiaryContainer, b.tertiaryContainer),
    onTertiaryContainer: l(a.onTertiaryContainer, b.onTertiaryContainer),
    error: l(a.error, b.error),
    onError: l(a.onError, b.onError),
    errorContainer: l(a.errorContainer, b.errorContainer),
    onErrorContainer: l(a.onErrorContainer, b.onErrorContainer),
    surface: l(a.surface, b.surface),
    onSurface: l(a.onSurface, b.onSurface),
    surfaceDim: l(a.surfaceDim, b.surfaceDim),
    surfaceBright: l(a.surfaceBright, b.surfaceBright),
    surfaceContainerLowest: l(a.surfaceContainerLowest, b.surfaceContainerLowest),
    surfaceContainerLow: l(a.surfaceContainerLow, b.surfaceContainerLow),
    surfaceContainer: l(a.surfaceContainer, b.surfaceContainer),
    surfaceContainerHigh: l(a.surfaceContainerHigh, b.surfaceContainerHigh),
    surfaceContainerHighest:
        l(a.surfaceContainerHighest, b.surfaceContainerHighest),
    onSurfaceVariant: l(a.onSurfaceVariant, b.onSurfaceVariant),
    outline: l(a.outline, b.outline),
    outlineVariant: l(a.outlineVariant, b.outlineVariant),
    shadow: l(a.shadow, b.shadow),
    scrim: l(a.scrim, b.scrim),
    inverseSurface: l(a.inverseSurface, b.inverseSurface),
    onInverseSurface: l(a.onInverseSurface, b.onInverseSurface),
    inversePrimary: l(a.inversePrimary, b.inversePrimary),
    surfaceTint: l(a.surfaceTint, b.surfaceTint),
  );
}

double _toLin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _toSrgb(double c) =>
    c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
double _cbrt(double x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

List<double> _oklab(Color c) {
  final r = _toLin(c.r), g = _toLin(c.g), b = _toLin(c.b);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

Color oklabLerp(Color x, Color y, double t) {
  if (t <= 0) return x;
  if (t >= 1) return y;
  final a = _oklab(x), b = _oklab(y);
  final L = a[0] + (b[0] - a[0]) * t;
  final A = a[1] + (b[1] - a[1]) * t;
  final B = a[2] + (b[2] - a[2]) * t;
  final l = math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3).toDouble();
  final m = math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3).toDouble();
  final s = math.pow(L - 0.0894841775 * A - 1.291485548 * B, 3).toDouble();
  double ch(double v) => _toSrgb(v).clamp(0.0, 1.0);
  return Color.from(
    alpha: x.a + (y.a - x.a) * t,
    red: ch(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    green: ch(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    blue: ch(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
  );
}
