import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';
import 'typography.dart';

/// Tema Harmonix basado en Material 3 con paleta azul marino fija.
///
/// Soporta dynamic theming Material You: el [seedColor] del esquema puede
/// cambiarse en tiempo de ejecución desde Ajustes, regenerando la paleta
/// MD3 completa con [ColorScheme.fromSeed] pero conservando los colores
/// fijos Harmonix para fondo/superficie.
class HarmonixTheme {
  HarmonixTheme._();

  static Color _seed = HarmonixColors.accent;

  static Color get currentSeed => _seed;

  static void setSeed(Color color) {
    _seed = color;
  }

  /// Esquema oscuro con la paleta Harmonix personalizada.
  static ColorScheme _colorScheme(Color seed) {
    final seeded = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return seeded.copyWith(
      // Forzamos la paleta Harmonix sobre la semilla
      surface: HarmonixColors.background,
      onSurface: HarmonixColors.textPrimary,
      surfaceContainerLowest: HarmonixColors.backgroundDark,
      surfaceContainerLow: HarmonixColors.background,
      surfaceContainer: HarmonixColors.surface,
      surfaceContainerHigh: HarmonixColors.surfaceVariant,
      surfaceContainerHighest: HarmonixColors.surfaceContainerHigh,
      onSurfaceVariant: HarmonixColors.textSecondary,
      primary: HarmonixColors.accent,
      onPrimary: Colors.white,
      primaryContainer: HarmonixColors.surfaceVariant,
      onPrimaryContainer: HarmonixColors.accentBright,
      secondary: HarmonixColors.accent,
      secondaryContainer: HarmonixColors.surfaceVariant,
      onSecondaryContainer: HarmonixColors.accentBright,
      tertiary: HarmonixColors.favorite,
      tertiaryContainer: HarmonixColors.surfaceVariant,
      onTertiaryContainer: HarmonixColors.favorite,
      outline: HarmonixColors.textDisabled,
      outlineVariant: HarmonixColors.textDisabled.withValues(alpha: 0.4),
      error: HarmonixColors.error,
      onError: Colors.white,
      inverseSurface: HarmonixColors.textPrimary,
      onInverseSurface: HarmonixColors.background,
      scrim: Colors.black,
    );
  }

  static ThemeData dark([Color? seed]) {
    final scheme = _colorScheme(seed ?? _seed);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: HarmonixColors.background,
      canvasColor: HarmonixColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: HarmonixTypography.textTheme,
      primaryTextTheme: HarmonixTypography.textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: HarmonixTypography.textTheme.titleLarge,
        iconTheme: const IconThemeData(color: HarmonixColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: HarmonixColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: HarmonixColors.surface,
        indicatorColor: HarmonixColors.accent.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: HarmonixTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected
                ? HarmonixColors.accentBright
                : HarmonixColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? HarmonixColors.accentBright
                : HarmonixColors.textSecondary,
            size: 24,
          );
        }),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HarmonixColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(56, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: HarmonixTypography.textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HarmonixColors.accent,
          side: BorderSide(color: HarmonixColors.accent.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HarmonixColors.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: HarmonixColors.textPrimary,
          highlightColor: HarmonixColors.accent.withValues(alpha: 0.12),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: HarmonixColors.accent,
        inactiveTrackColor: HarmonixColors.accent.withValues(alpha: 0.2),
        thumbColor: HarmonixColors.accentBright,
        overlayColor: HarmonixColors.accent.withValues(alpha: 0.15),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      dividerTheme: DividerThemeData(
        color: HarmonixColors.textDisabled.withValues(alpha: 0.2),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: HarmonixColors.textSecondary,
        textColor: HarmonixColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: HarmonixColors.surface,
        selectedColor: HarmonixColors.accent,
        labelStyle: HarmonixTypography.textTheme.labelLarge,
        side: BorderSide(
          color: HarmonixColors.textDisabled.withValues(alpha: 0.25),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HarmonixColors.surfaceVariant,
        contentTextStyle: HarmonixTypography.textTheme.bodyMedium?.copyWith(
              color: HarmonixColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HarmonixColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: HarmonixTypography.textTheme.titleLarge,
        contentTextStyle: HarmonixTypography.textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: HarmonixColors.surface,
        modalBackgroundColor: HarmonixColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: HarmonixColors.textDisabled,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: HarmonixColors.accent,
        linearTrackColor: HarmonixColors.accent.withValues(alpha: 0.15),
        circularTrackColor: HarmonixColors.accent.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return HarmonixColors.textDisabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HarmonixColors.accent;
          }
          return HarmonixColors.textDisabled.withValues(alpha: 0.3);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _HarmonixPageTransitionsBuilder(),
          TargetPlatform.iOS: _HarmonixPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Transición de página personalizada: combinación fade + slide vertical suave.
class _HarmonixPageTransitionsBuilder extends PageTransitionsBuilder {
  const _HarmonixPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
