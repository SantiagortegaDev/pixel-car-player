import 'package:flutter/material.dart';

/// Paleta de colores Harmonix.
///
/// Inspirada en las capturas de referencia: fondo azul marino oscuro,
/// tarjetas en azul más claro y acentos celestes brillantes.
/// Los iconos de categoría (favoritos, recién añadidas) usan tonos adicionales.
class HarmonixColors {
  HarmonixColors._();

  // Fondo principal — azul marino muy oscuro
  static const Color background = Color(0xFF0A1A3A);
  static const Color backgroundDark = Color(0xFF061227);

  // Superficies — tarjetas azul un poco más claro
  static const Color surface = Color(0xFF0F2451);
  static const Color surfaceVariant = Color(0xFF13316B);
  static const Color surfaceContainer = Color(0xFF163372);
  static const Color surfaceContainerHigh = Color(0xFF1B3D85);

  // Acento principal — celeste / azul brillante
  static const Color accent = Color(0xFF4A9EFF);
  static const Color accentBright = Color(0xFF6FB5FF);
  static const Color accentDim = Color(0xFF2D7DD2);

  // Iconos de categoría
  static const Color favorite = Color(0xFFFF6B9D); // rosa
  static const Color recent = Color(0xFFFFA94D);   // naranja
  static const Color download = Color(0xFF4ADE80); // verde
  static const Color library = Color(0xFFA78BFA);  // violeta

  // Texto
  static const Color textPrimary = Color(0xFFF1F5FF);
  static const Color textSecondary = Color(0xFFA9B6D6);
  static const Color textDisabled = Color(0xFF5A6A8C);

  // Estados
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFC107);
  static const Color success = Color(0xFF4ADE80);

  // Gradientes para tarjetas de playlists (categorías)
  static const List<List<Color>> playlistGradients = [
    [Color(0xFFFF6B9D), Color(0xFFC9184A)], // gym / energía
    [Color(0xFF4A9EFF), Color(0xFF1B3D85)], // tristes
    [Color(0xFFFFA94D), Color(0xFFE8590C)], // románticas
    [Color(0xFFA78BFA), Color(0xFF5F3DC4)], // chill
    [Color(0xFF4ADE80), Color(0xFF2B8A3E)], // foco
    [Color(0xFFFFD43B), Color(0xFFF08C00)], // party
  ];

  /// Semillas para dynamic theming Material You.
  static const List<Color> accentSeeds = [
    Color(0xFF4A9EFF), // azul por defecto
    Color(0xFFFF6B9D), // rosa
    Color(0xFF4ADE80), // verde
    Color(0xFFFFA94D), // naranja
    Color(0xFFA78BFA), // violeta
    Color(0xFFFFD43B), // amarillo
    Color(0xFFFF5252), // rojo
    Color(0xFF22D3EE), // cyan
  ];
}
