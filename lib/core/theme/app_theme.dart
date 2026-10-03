import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tema Material Design 3 + Material You (estilo Harmonix).
///
/// TODO el color sale de un [ColorScheme] dinámico:
///  - Celular: colores del sistema (wallpaper, Android 12+) vía `dynamic_color`.
///  - Tableta: esquema generado de la carátula que suena
///    ([ColorScheme.fromImageProvider]), igual que el reproductor de Android.
/// Nunca uses colores fijos en widgets: usa `Theme.of(context).colorScheme`.
class AppTheme {
  AppTheme._();

  /// Semilla por defecto (violeta MD3 baseline de Harmonix web).
  static const Color fallbackSeed = Color(0xFF7B5BD6);

  /// Variante tonal de Material You usada en toda la app.
  static const DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot;

  static ColorScheme schemeFromSeed(Color seed,
          {Brightness brightness = Brightness.dark}) =>
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: variant,
      );

  /// Esquema desde una imagen (carátula). Funciona en Android y web.
  static Future<ColorScheme> schemeFromImage(ImageProvider image,
          {Brightness brightness = Brightness.dark}) =>
      ColorScheme.fromImageProvider(
        provider: image,
        brightness: brightness,
        dynamicSchemeVariant: variant,
      );

  static ThemeData dark([ColorScheme? scheme]) =>
      build(scheme ?? schemeFromSeed(fallbackSeed));

  static ThemeData light([ColorScheme? scheme]) =>
      build(scheme ?? schemeFromSeed(fallbackSeed, brightness: Brightness.light));

  /// Construye el ThemeData M3 completo a partir de un esquema.
  static ThemeData build(ColorScheme s) {
    final isDark = s.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: s,
      brightness: s.brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: s.surface,
      canvasColor: s.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        surfaceTintColor: s.surfaceTint,
        centerTitle: false,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
