import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart' show SchemeVariant;

/// Personalización completa de la pantalla del carro.
///
/// Inmutable y por secciones (cada una con `copyWith`, `toJson` y `fromJson`). Al leer,
/// cualquier clave que falte o tenga un valor inválido toma el valor por defecto (y los
/// números se acotan a su rango), así que agregar campos en el futuro no rompe nada.

// ---------------------------------------------------------------------------
// Enums

enum CarColorSource { art, fixed }

/// Tema: oscuro, claro, el del sistema o por horario (oscuro de noche, ver [CarNightOpts]).
enum CarThemeMode { dark, light, auto, schedule }

enum CarVizColor { primary, secondary, tertiary, onSurface }

enum CarTransport { auto, wifi, bt }

enum CarLyricsAlign { left, center }

enum CarSeekMode { off, tap, doubleTap }

/// Animaciones (como `motion` de Harmonix v2): del sistema, siempre completas o reducidas.
enum CarMotion { system, full, reduced }

/// De dónde salen las barras del visualizador.
enum CarVizSource {
  /// Audio real si la tableta lo detecta; si no, el espectro simulado mientras suena.
  auto,

  /// Solo el audio real (Visualizer de Android). Sin audio, las barras quedan quietas.
  real,

  /// Siempre el espectro simulado (no pide permisos).
  simulated,
}

/// Animación de la letra al pasar de línea.
enum CarLyricAnim {
  /// Cambio instantáneo de color.
  none('Ninguna'),

  /// Fundido de color (y brillo).
  fade('Suave'),

  /// La línea nueva sube ~10 px a su lugar mientras la anterior se apaga.
  slide('Deslizar'),

  /// La línea actual crece de 0,94 a 1; las demás quedan un poco más chicas.
  scale('Escala'),

  /// Las demás líneas se desenfocan apenas; la actual se ve nítida.
  blur('Desenfoque'),

  /// La línea actual se va llenando de izquierda a derecha con el tiempo del tema.
  karaoke('Karaoke');

  const CarLyricAnim(this.label);
  final String label;
}

/// Curva de la animación de la letra.
enum CarLyricCurve {
  emphasized('Enfatizada'),
  standard('Estándar'),
  linear('Lineal');

  const CarLyricCurve(this.label);
  final String label;
}

/// Qué tan rápido siguen las barras al audio real.
enum CarVizResponse {
  /// Más suavizado (movimiento tranquilo).
  smooth('Suave'),

  /// El de Harmonix (ataque 0,35 · caída 0,12).
  normal('Normal'),

  /// Casi sin suavizado: las barras siguen cada cuadro del FFT.
  precise('Precisa');

  const CarVizResponse(this.label);
  final String label;

  /// Factor de ataque (sube) y caída (baja) por cuadro de 60 fps.
  (double attack, double release) get smoothing => switch (this) {
    CarVizResponse.smooth => (0.2, 0.07),
    CarVizResponse.normal => (0.35, 0.12),
    CarVizResponse.precise => (0.8, 0.4),
  };
}

/// Secciones del modelo (para restablecer por partes).
enum CarSection {
  connection,
  startup,
  hotspot,
  design,
  cover,
  visualizer,
  lyrics,
  visibility,
  texts,
  gestures,
  animations,
  standby,
  style,
  night,
  controls,
  keepFront,
  updates,
}

/// Rango de un ajuste numérico (lo usan el modelo para acotar y la UI para los sliders).
@immutable
class CarRange {
  const CarRange(this.min, this.max, this.step);
  final double min, max, step;
  double clamp(double v) => v.clamp(min, max).toDouble();
}

// ---------------------------------------------------------------------------
// Elementos que se pueden ocultar

enum CarElementGroup {
  header('Encabezado'),
  info('Información del tema'),
  controls('Botones de control'),
  chips('Chips'),
  side('Panel lateral'),
  stage('Portada y fondo'),
  idle('Pantalla de espera');

  const CarElementGroup(this.label);
  final String label;
}

enum CarElement {
  header(CarElementGroup.header, 'Encabezado completo', 'Toda la barra de arriba.'),
  headerLeft(CarElementGroup.header, 'Botón izquierdo', 'Abre la letra en pantalla completa.'),
  headerLabel(CarElementGroup.header, 'Texto del encabezado', '«Reproduciendo».'),
  clock.hiddenByDefault(CarElementGroup.header, 'Reloj', 'Hora actual en el encabezado.'),
  statusChip(CarElementGroup.header, 'Chip de conexión', 'Nombre del celular y Wi-Fi/Bluetooth.'),
  btChip(CarElementGroup.header, 'Chip de Bluetooth', 'Equipo Bluetooth conectado al radio (p. ej. tu celular).'),
  wifiChip(CarElementGroup.header, 'Chip de Wi-Fi / hotspot', 'Red Wi-Fi o clientes del hotspot del carro.'),
  settingsButton(
    CarElementGroup.header,
    'Botón de Configuración',
    'Mantén presionado el fondo para abrir Configuración.',
  ),
  title(CarElementGroup.info, 'Título'),
  artist(CarElementGroup.info, 'Artista'),
  album(CarElementGroup.info, 'Álbum'),
  progress(CarElementGroup.info, 'Barra de progreso'),
  times(CarElementGroup.info, 'Tiempos', 'Transcurrido y duración a los lados de la barra.'),
  shuffle(CarElementGroup.controls, 'Aleatorio'),
  previous(CarElementGroup.controls, 'Anterior'),
  playPause(CarElementGroup.controls, 'Reproducir / pausar'),
  next(CarElementGroup.controls, 'Siguiente'),
  repeat(CarElementGroup.controls, 'Repetir'),
  like(CarElementGroup.controls, 'Me gusta', 'Corazón al final de la fila (si la app del celular lo permite).'),
  chips(CarElementGroup.chips, 'Fila de chips', 'Todos los chips debajo de los controles.'),
  chipFullscreen(CarElementGroup.chips, 'Chip «Letra en pantalla completa»'),
  chipKeepOn(CarElementGroup.chips, 'Chip «Mantener encendida»'),
  sidePanel(
    CarElementGroup.side,
    'Panel lateral completo',
    'Letra y A continuación. La portada y los datos se centran.',
  ),
  tabPills(CarElementGroup.side, 'Selector de pestañas', 'Las píldoras Letra / A continuación.'),
  lyricsTab(CarElementGroup.side, 'Pestaña Letra'),
  queueTab(CarElementGroup.side, 'Pestaña A continuación'),
  cover(CarElementGroup.stage, 'Portada (disco)', 'Sin portada, los datos y el panel ocupan su lugar.'),
  visualizer(CarElementGroup.stage, 'Barras del visualizador', 'Las líneas alrededor de la portada.'),
  backgroundShapes(CarElementGroup.stage, 'Formas de fondo', 'Formas que flotan detrás del reproductor.'),
  idleIcon(CarElementGroup.idle, 'Ícono de espera'),
  idleButtons(CarElementGroup.idle, 'Botones de espera', 'Ajustes de conexión y Ver demo.'),
  idleSteps(CarElementGroup.idle, 'Pasos para conectar'),
  idleIps(CarElementGroup.idle, 'IP de esta tableta');

  const CarElement(this.group, this.label, [this.description]) : defaultVisible = true;
  const CarElement.hiddenByDefault(this.group, this.label, [this.description]) : defaultVisible = false;

  final CarElementGroup group;
  final String label;
  final String? description;
  final bool defaultVisible;
}

/// Qué elementos se ven. Solo guarda lo que difiere del valor por defecto.
@immutable
class CarVisibility {
  const CarVisibility([this._overrides = const {}]);
  final Map<CarElement, bool> _overrides;

  bool operator [](CarElement e) => _overrides[e] ?? e.defaultVisible;

  /// Todos los elementos de [els] visibles.
  bool all(Iterable<CarElement> els) => els.every((e) => this[e]);

  /// Alguno de [els] visible.
  bool any(Iterable<CarElement> els) => els.any((e) => this[e]);

  CarVisibility withElement(CarElement e, bool visible) {
    final m = Map<CarElement, bool>.of(_overrides);
    if (visible == e.defaultVisible) {
      m.remove(e);
    } else {
      m[e] = visible;
    }
    return CarVisibility(Map.unmodifiable(m));
  }

  /// Muestra u oculta todos los elementos de una vez.
  CarVisibility withAll(bool visible) => CarVisibility(
    Map.unmodifiable({
      for (final e in CarElement.values)
        if (e.defaultVisible != visible) e: visible,
    }),
  );

  int get hiddenCount => CarElement.values.where((e) => !this[e]).length;

  Map<String, dynamic> toJson() => {
    for (final e in CarElement.values)
      if (_overrides.containsKey(e)) e.name: _overrides[e],
  };

  factory CarVisibility.fromJson(Object? json) {
    final m = _map(json);
    final out = <CarElement, bool>{};
    for (final e in CarElement.values) {
      final v = m[e.name];
      if (v is bool && v != e.defaultVisible) out[e] = v;
    }
    return CarVisibility(Map.unmodifiable(out));
  }

  @override
  bool operator ==(Object other) => other is CarVisibility && mapEquals(other._overrides, _overrides);

  @override
  int get hashCode => Object.hashAllUnordered(_overrides.entries.map((e) => Object.hash(e.key, e.value)));
}

// ---------------------------------------------------------------------------
// Textos editables

enum CarTextGroup {
  player('Reproductor'),
  panel('Letra y cola'),
  status('Conexión'),
  idle('Pantalla de espera');

  const CarTextGroup(this.label);
  final String label;
}

enum CarText {
  headerPlayer(CarTextGroup.player, 'Encabezado del reproductor', 'Reproduciendo'),
  headerLyrics(CarTextGroup.player, 'Encabezado de la letra completa', 'Letra'),
  headerIdle(CarTextGroup.player, 'Encabezado en espera', 'Pixel Car Player'),
  chipFullscreen(CarTextGroup.player, 'Chip de letra completa', 'Letra en pantalla completa'),
  chipKeepOn(CarTextGroup.player, 'Chip de pantalla (activo)', 'Pantalla siempre encendida'),
  chipKeepOff(CarTextGroup.player, 'Chip de pantalla (inactivo)', 'Mantener encendida'),
  unknownArtist(CarTextGroup.player, 'Artista sin nombre', 'Artista desconocido'),
  unknownAlbum(CarTextGroup.player, 'Álbum sin nombre', 'Álbum desconocido'),
  tabLyrics(CarTextGroup.panel, 'Pestaña Letra', 'Letra'),
  tabQueue(CarTextGroup.panel, 'Pestaña A continuación', 'A continuación'),
  noLyrics(CarTextGroup.panel, 'Letra no disponible', 'No hay letra para este tema.'),
  emptyQueue(CarTextGroup.panel, 'Cola vacía', 'No hay más temas en la cola.'),
  statusSearching(CarTextGroup.status, 'Chip: buscando', 'Buscando al celular…'),
  statusOff(CarTextGroup.status, 'Chip: sin conexión', 'Sin conexión'),
  idleTitle(CarTextGroup.idle, 'Título de espera', 'Esperando al celular…'),
  idleText(
    CarTextGroup.idle,
    'Texto de espera',
    'La música, la portada y la letra aparecerán aquí en cuanto tu celular se conecte.',
  ),
  idleConnectedText(
    CarTextGroup.idle,
    'Texto con el celular conectado',
    'Pon música en el celular y aparecerá aquí al instante.',
  ),
  idleSettingsButton(CarTextGroup.idle, 'Botón de ajustes', 'Ajustes de conexión'),
  idleDemoButton(CarTextGroup.idle, 'Botón de demo', 'Ver demo'),
  stepsTitle(CarTextGroup.idle, 'Título de los pasos', 'Cómo conectar'),
  step1Title(CarTextGroup.idle, 'Paso 1', 'Abre Pixel Car Player en el celular'),
  step1Text(CarTextGroup.idle, 'Paso 1 · detalle', 'Activa “Transmitir” y deja la música sonando.'),
  step2Title(CarTextGroup.idle, 'Paso 2', 'Conecta la tableta al hotspot del celular'),
  step2Text(CarTextGroup.idle, 'Paso 2 · detalle', 'O a la misma red Wi-Fi. También puedes usar Bluetooth en Ajustes.'),
  step3Title(CarTextGroup.idle, 'Paso 3', 'Listo'),
  step3Text(CarTextGroup.idle, 'Paso 3 · detalle', 'Se conectará sola; no hace falta tocar nada más.');

  const CarText(this.group, this.label, this.defaultText);
  final CarTextGroup group;
  final String label;
  final String defaultText;
}

/// Textos personalizados. Cadena vacía = elemento oculto.
@immutable
class CarTexts {
  const CarTexts([this._overrides = const {}]);
  final Map<CarText, String> _overrides;

  String operator [](CarText t) => _overrides[t] ?? t.defaultText;

  bool isCustom(CarText t) => _overrides.containsKey(t);

  CarTexts withText(CarText t, String? value) {
    final m = Map<CarText, String>.of(_overrides);
    if (value == null || value == t.defaultText) {
      m.remove(t);
    } else {
      m[t] = value;
    }
    return CarTexts(Map.unmodifiable(m));
  }

  int get customCount => _overrides.length;

  Map<String, dynamic> toJson() => {
    for (final t in CarText.values)
      if (_overrides.containsKey(t)) t.name: _overrides[t],
  };

  factory CarTexts.fromJson(Object? json) {
    final m = _map(json);
    final out = <CarText, String>{};
    for (final t in CarText.values) {
      final v = m[t.name];
      if (v is String && v != t.defaultText) out[t] = v.length > 400 ? v.substring(0, 400) : v;
    }
    return CarTexts(Map.unmodifiable(out));
  }

  @override
  bool operator ==(Object other) => other is CarTexts && mapEquals(other._overrides, _overrides);

  @override
  int get hashCode => Object.hashAllUnordered(_overrides.entries.map((e) => Object.hash(e.key, e.value)));
}

// ---------------------------------------------------------------------------
// Secciones

/// Igualdad por contenido (vía JSON) para las secciones de valores simples.
mixin _JsonEquality {
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && jsonEncode((other as _JsonEquality).toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

@immutable
class CarDesign with _JsonEquality {
  const CarDesign({
    this.colorSource = CarColorSource.art,
    this.fixedColor = 0xFF3F6D8E,
    this.variant = SchemeVariant.tonalSpot,
    this.themeMode = CarThemeMode.dark,
    this.uiScale = 1.0,
    this.titleScale = 1.0,
    this.controlHeight = 56,
    this.progressStyle = CarProgressStyle.wavy,
    this.waveAmplitude = 1.0,
    this.shapesCount = 14,
    this.shapesOpacity = 1.0,
    this.shapesAnimate = true,
    this.motion = CarMotion.system,
  });

  final CarColorSource colorSource;

  /// ARGB del color fijo.
  final int fixedColor;
  final SchemeVariant variant;
  final CarThemeMode themeMode;
  final double uiScale;
  final double titleScale;
  final double controlHeight;

  /// Ondulada (Harmonix), plana o fina.
  final CarProgressStyle progressStyle;
  final double waveAmplitude;

  /// La barra de progreso ondula (estilo "Ondulada").
  bool get wavy => progressStyle == CarProgressStyle.wavy;
  final int shapesCount;
  final double shapesOpacity;
  final bool shapesAnimate;

  /// Animaciones: Sistema (sigue «quitar animaciones» de Android) / Completas / Reducidas.
  final CarMotion motion;

  static const uiScaleRange = CarRange(0.8, 1.6, 0.05);
  static const titleScaleRange = CarRange(0.7, 1.6, 0.05);
  static const controlHeightRange = CarRange(48, 96, 2);
  static const waveAmplitudeRange = CarRange(0.2, 2.0, 0.1);
  static const shapesCountRange = CarRange(0, 30, 1);
  static const shapesOpacityRange = CarRange(0, 3, 0.1);

  CarDesign copyWith({
    CarColorSource? colorSource,
    int? fixedColor,
    SchemeVariant? variant,
    CarThemeMode? themeMode,
    double? uiScale,
    double? titleScale,
    double? controlHeight,
    CarProgressStyle? progressStyle,
    double? waveAmplitude,
    int? shapesCount,
    double? shapesOpacity,
    bool? shapesAnimate,
    CarMotion? motion,
  }) => CarDesign(
    colorSource: colorSource ?? this.colorSource,
    fixedColor: fixedColor ?? this.fixedColor,
    variant: variant ?? this.variant,
    themeMode: themeMode ?? this.themeMode,
    uiScale: uiScale ?? this.uiScale,
    titleScale: titleScale ?? this.titleScale,
    controlHeight: controlHeight ?? this.controlHeight,
    progressStyle: progressStyle ?? this.progressStyle,
    waveAmplitude: waveAmplitude ?? this.waveAmplitude,
    shapesCount: shapesCount ?? this.shapesCount,
    shapesOpacity: shapesOpacity ?? this.shapesOpacity,
    shapesAnimate: shapesAnimate ?? this.shapesAnimate,
    motion: motion ?? this.motion,
  );

  @override
  Map<String, dynamic> toJson() => {
    'colorSource': colorSource.name,
    'fixedColor': colorHex(fixedColor),
    'variant': variant.name,
    'themeMode': themeMode.name,
    'uiScale': uiScale,
    'titleScale': titleScale,
    'controlHeight': controlHeight,
    'progressStyle': progressStyle.name,
    // Para versiones anteriores de la app.
    'wavy': wavy,
    'waveAmplitude': waveAmplitude,
    'shapesCount': shapesCount,
    'shapesOpacity': shapesOpacity,
    'shapesAnimate': shapesAnimate,
    'motion': motion.name,
  };

  factory CarDesign.fromJson(Object? json) {
    final m = _map(json);
    const d = CarDesign();
    return CarDesign(
      colorSource: _enum(CarColorSource.values, m['colorSource'], d.colorSource),
      fixedColor: parseColorHex(m['fixedColor']) ?? d.fixedColor,
      variant: _enum(SchemeVariant.values, m['variant'], d.variant),
      themeMode: _enum(CarThemeMode.values, m['themeMode'], d.themeMode),
      uiScale: _num(m['uiScale'], d.uiScale, uiScaleRange),
      titleScale: _num(m['titleScale'], d.titleScale, titleScaleRange),
      controlHeight: _num(m['controlHeight'], d.controlHeight, controlHeightRange),
      progressStyle: _enum(
        CarProgressStyle.values,
        m['progressStyle'],
        _bool(m['wavy'], true) ? CarProgressStyle.wavy : CarProgressStyle.plain,
      ),
      waveAmplitude: _num(m['waveAmplitude'], d.waveAmplitude, waveAmplitudeRange),
      shapesCount: _num(m['shapesCount'], d.shapesCount.toDouble(), shapesCountRange).round(),
      shapesOpacity: _num(m['shapesOpacity'], d.shapesOpacity, shapesOpacityRange),
      shapesAnimate: _bool(m['shapesAnimate'], d.shapesAnimate),
      motion: _enum(CarMotion.values, m['motion'], d.motion),
    );
  }
}

@immutable
class CarCoverOpts with _JsonEquality {
  const CarCoverOpts({
    this.shape = 'cookie9',
    this.rotate = true,
    this.turnSeconds = 23.5,
    this.scale = 1.0,
    this.outline = true,
    this.glow = false,
  });

  /// Nombre en `M3Shape.all`.
  final String shape;
  final bool rotate;

  /// Segundos por vuelta.
  final double turnSeconds;
  final double scale;
  final bool outline;
  final bool glow;

  static const turnRange = CarRange(4, 90, 0.5);
  static const scaleRange = CarRange(0.6, 1.4, 0.05);

  CarCoverOpts copyWith({String? shape, bool? rotate, double? turnSeconds, double? scale, bool? outline, bool? glow}) =>
      CarCoverOpts(
        shape: shape ?? this.shape,
        rotate: rotate ?? this.rotate,
        turnSeconds: turnSeconds ?? this.turnSeconds,
        scale: scale ?? this.scale,
        outline: outline ?? this.outline,
        glow: glow ?? this.glow,
      );

  @override
  Map<String, dynamic> toJson() => {
    'shape': shape,
    'rotate': rotate,
    'turnSeconds': turnSeconds,
    'scale': scale,
    'outline': outline,
    'glow': glow,
  };

  factory CarCoverOpts.fromJson(Object? json, {Set<String>? shapes}) {
    final m = _map(json);
    const d = CarCoverOpts();
    final s = m['shape'];
    return CarCoverOpts(
      shape: s is String && (shapes == null || shapes.contains(s)) ? s : d.shape,
      rotate: _bool(m['rotate'], d.rotate),
      turnSeconds: _num(m['turnSeconds'], d.turnSeconds, turnRange),
      scale: _num(m['scale'], d.scale, scaleRange),
      outline: _bool(m['outline'], d.outline),
      glow: _bool(m['glow'], d.glow),
    );
  }
}

@immutable
class CarVisualizerOpts with _JsonEquality {
  const CarVisualizerOpts({
    this.amplification = 1.0,
    this.bars = 44,
    this.thickness = 1.0,
    this.spacing = 12,
    this.speed = 1.0,
    this.roundCaps = true,
    this.color = CarVizColor.primary,
    this.pausedDots = true,
    this.source = CarVizSource.auto,
    this.sensitivity = 1.0,
    this.animateAlways = false,
    this.response = CarVizResponse.normal,
  });

  /// Multiplicador del largo de las barras.
  final double amplification;
  final int bars;
  final double thickness;

  /// Distancia (px) entre la forma y el nacimiento de las barras.
  final double spacing;
  final double speed;
  final bool roundCaps;
  final CarVizColor color;
  final bool pausedDots;

  /// Audio real / simulado / automático.
  final CarVizSource source;

  /// Ganancia sobre el audio real (sube si las barras se mueven poco).
  final double sensitivity;

  /// Animar aunque no se sepa si está sonando (p. ej. la app Bluetooth del radio no avisa).
  final bool animateAlways;

  /// Suavizado de las barras (Suave / Normal / Precisa).
  final CarVizResponse response;

  static const amplificationRange = CarRange(0.25, 3.0, 0.05);
  static const barsRange = CarRange(16, 96, 2);
  static const thicknessRange = CarRange(0.4, 2.5, 0.05);
  static const spacingRange = CarRange(0, 40, 1);
  static const speedRange = CarRange(0.25, 2.5, 0.05);
  static const sensitivityRange = CarRange(0.25, 4.0, 0.05);

  /// ¿Se usa (o se intenta usar) el Visualizer de Android?
  bool get wantsRealAudio => source != CarVizSource.simulated;

  CarVisualizerOpts copyWith({
    double? amplification,
    int? bars,
    double? thickness,
    double? spacing,
    double? speed,
    bool? roundCaps,
    CarVizColor? color,
    bool? pausedDots,
    CarVizSource? source,
    double? sensitivity,
    bool? animateAlways,
    CarVizResponse? response,
  }) => CarVisualizerOpts(
    amplification: amplification ?? this.amplification,
    bars: bars ?? this.bars,
    thickness: thickness ?? this.thickness,
    spacing: spacing ?? this.spacing,
    speed: speed ?? this.speed,
    roundCaps: roundCaps ?? this.roundCaps,
    color: color ?? this.color,
    pausedDots: pausedDots ?? this.pausedDots,
    source: source ?? this.source,
    sensitivity: sensitivity ?? this.sensitivity,
    animateAlways: animateAlways ?? this.animateAlways,
    response: response ?? this.response,
  );

  @override
  Map<String, dynamic> toJson() => {
    'amplification': amplification,
    'bars': bars,
    'thickness': thickness,
    'spacing': spacing,
    'speed': speed,
    'roundCaps': roundCaps,
    'color': color.name,
    'pausedDots': pausedDots,
    'source': source.name,
    'sensitivity': sensitivity,
    'animateAlways': animateAlways,
    'response': response.name,
  };

  factory CarVisualizerOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarVisualizerOpts();
    // Siempre par: el espectro se refleja izquierda/derecha.
    final bars = _num(m['bars'], d.bars.toDouble(), barsRange).round() ~/ 2 * 2;
    return CarVisualizerOpts(
      amplification: _num(m['amplification'], d.amplification, amplificationRange),
      bars: bars,
      thickness: _num(m['thickness'], d.thickness, thicknessRange),
      spacing: _num(m['spacing'], d.spacing, spacingRange),
      speed: _num(m['speed'], d.speed, speedRange),
      roundCaps: _bool(m['roundCaps'], d.roundCaps),
      color: _enum(CarVizColor.values, m['color'], d.color),
      pausedDots: _bool(m['pausedDots'], d.pausedDots),
      source: _enum(CarVizSource.values, m['source'], d.source),
      sensitivity: _num(m['sensitivity'], d.sensitivity, sensitivityRange),
      animateAlways: _bool(m['animateAlways'], d.animateAlways),
      response: _enum(CarVizResponse.values, m['response'], d.response),
    );
  }
}

@immutable
class CarLyricsOpts with _JsonEquality {
  const CarLyricsOpts({
    this.scale = 1.0,
    this.spacing = 1.0,
    this.align = CarLyricsAlign.left,
    this.glow = true,
    this.offsetMs = 150,
    this.seek = CarSeekMode.tap,
    this.anim = CarLyricAnim.slide,
    this.animMs = 350,
    this.animCurve = CarLyricCurve.emphasized,
    this.animFullscreen = true,
    this.scrollMs = 600,
    this.inactiveOpacity = 1.0,
    this.maxVisible = 0,
    this.weight = 500,
  });

  final double scale;

  /// Multiplicador del espacio entre líneas.
  final double spacing;
  final CarLyricsAlign align;
  final bool glow;

  /// Adelanto con el que se resalta la línea (compensa la latencia del Bluetooth).
  final int offsetMs;
  final CarSeekMode seek;

  /// Animación al pasar de línea.
  final CarLyricAnim anim;

  /// Duración de esa animación (ms).
  final int animMs;
  final CarLyricCurve animCurve;

  /// También en la letra a pantalla completa (si no, allí se usa «Suave»).
  final bool animFullscreen;

  /// Duración del desplazamiento hasta la línea actual (ms; Harmonix: 600).
  final int scrollMs;

  /// Opacidad de las líneas que no suenan (1 = solo el color `outline`).
  final double inactiveOpacity;

  /// Líneas visibles alrededor de la actual (0 = todas).
  final int maxVisible;

  /// Peso de la letra (300–900).
  final int weight;

  static const scaleRange = CarRange(0.7, 1.8, 0.05);
  static const spacingRange = CarRange(0.5, 3.0, 0.1);
  static const offsetRange = CarRange(-1000, 2000, 50);
  static const animMsRange = CarRange(100, 800, 50);
  static const scrollMsRange = CarRange(150, 1500, 50);
  static const inactiveOpacityRange = CarRange(0.2, 1.0, 0.05);
  static const maxVisibleRange = CarRange(0, 15, 1);
  static const weightRange = CarRange(300, 900, 100);

  /// Animación que corresponde a la letra normal o a la de pantalla completa.
  CarLyricAnim animFor({bool fullscreen = false}) =>
      fullscreen && !animFullscreen && anim != CarLyricAnim.none ? CarLyricAnim.fade : anim;

  CarLyricsOpts copyWith({
    double? scale,
    double? spacing,
    CarLyricsAlign? align,
    bool? glow,
    int? offsetMs,
    CarSeekMode? seek,
    CarLyricAnim? anim,
    int? animMs,
    CarLyricCurve? animCurve,
    bool? animFullscreen,
    int? scrollMs,
    double? inactiveOpacity,
    int? maxVisible,
    int? weight,
  }) => CarLyricsOpts(
    scale: scale ?? this.scale,
    spacing: spacing ?? this.spacing,
    align: align ?? this.align,
    glow: glow ?? this.glow,
    offsetMs: offsetMs ?? this.offsetMs,
    seek: seek ?? this.seek,
    anim: anim ?? this.anim,
    animMs: animMs ?? this.animMs,
    animCurve: animCurve ?? this.animCurve,
    animFullscreen: animFullscreen ?? this.animFullscreen,
    scrollMs: scrollMs ?? this.scrollMs,
    inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
    maxVisible: maxVisible ?? this.maxVisible,
    weight: weight ?? this.weight,
  );

  @override
  Map<String, dynamic> toJson() => {
    'scale': scale,
    'spacing': spacing,
    'align': align.name,
    'glow': glow,
    'offsetMs': offsetMs,
    'seek': seek.name,
    'anim': anim.name,
    'animMs': animMs,
    'animCurve': animCurve.name,
    'animFullscreen': animFullscreen,
    'scrollMs': scrollMs,
    'inactiveOpacity': inactiveOpacity,
    'maxVisible': maxVisible,
    'weight': weight,
  };

  factory CarLyricsOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarLyricsOpts();
    return CarLyricsOpts(
      scale: _num(m['scale'], d.scale, scaleRange),
      spacing: _num(m['spacing'], d.spacing, spacingRange),
      align: _enum(CarLyricsAlign.values, m['align'], d.align),
      glow: _bool(m['glow'], d.glow),
      offsetMs: _num(m['offsetMs'], d.offsetMs.toDouble(), offsetRange).round(),
      seek: _enum(CarSeekMode.values, m['seek'], d.seek),
      anim: _enum(CarLyricAnim.values, m['anim'], d.anim),
      animMs: _num(m['animMs'], d.animMs.toDouble(), animMsRange).round(),
      animCurve: _enum(CarLyricCurve.values, m['animCurve'], d.animCurve),
      animFullscreen: _bool(m['animFullscreen'], d.animFullscreen),
      scrollMs: _num(m['scrollMs'], d.scrollMs.toDouble(), scrollMsRange).round(),
      inactiveOpacity: _num(m['inactiveOpacity'], d.inactiveOpacity, inactiveOpacityRange),
      maxVisible: _num(m['maxVisible'], d.maxVisible.toDouble(), maxVisibleRange).round(),
      weight: (_num(m['weight'], d.weight.toDouble(), weightRange) / 100).round() * 100,
    );
  }
}

@immutable
class CarConnectionOpts with _JsonEquality {
  const CarConnectionOpts({
    this.autoConnect = true,
    this.transport = CarTransport.auto,
    this.reconnectSeconds = 10,
    this.demoWhenIdle = false,
  });

  final bool autoConnect;
  final CarTransport transport;

  /// Espera máxima entre intentos de conexión.
  final int reconnectSeconds;

  /// Muestra la demo mientras no haya celular.
  final bool demoWhenIdle;

  static const reconnectRange = CarRange(2, 60, 1);

  CarConnectionOpts copyWith({bool? autoConnect, CarTransport? transport, int? reconnectSeconds, bool? demoWhenIdle}) =>
      CarConnectionOpts(
        autoConnect: autoConnect ?? this.autoConnect,
        transport: transport ?? this.transport,
        reconnectSeconds: reconnectSeconds ?? this.reconnectSeconds,
        demoWhenIdle: demoWhenIdle ?? this.demoWhenIdle,
      );

  @override
  Map<String, dynamic> toJson() => {
    'autoConnect': autoConnect,
    'transport': transport.name,
    'reconnectSeconds': reconnectSeconds,
    'demoWhenIdle': demoWhenIdle,
  };

  factory CarConnectionOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarConnectionOpts();
    return CarConnectionOpts(
      autoConnect: _bool(m['autoConnect'], d.autoConnect),
      transport: _enum(CarTransport.values, m['transport'], d.transport),
      reconnectSeconds: _num(m['reconnectSeconds'], d.reconnectSeconds.toDouble(), reconnectRange).round(),
      demoWhenIdle: _bool(m['demoWhenIdle'], d.demoWhenIdle),
    );
  }
}

@immutable
class CarStartupOpts with _JsonEquality {
  const CarStartupOpts({
    this.autostart = false,
    this.autostartDelay = 3,
    this.immersive = true,
    this.lockLandscape = false,
    this.startLyricsFullscreen = false,
    this.companionEnabled = false,
    this.companionPackage = '',
    this.companionLabel = '',
    this.companionDelayMs = 1500,
  });

  /// Se guarda además en `car_autostart` (lo lee el BootReceiver nativo).
  final bool autostart;

  /// Se guarda además en `car_autostart_delay` (segundos).
  final int autostartDelay;
  final bool immersive;
  final bool lockLandscape;
  final bool startLyricsFullscreen;

  /// Abrir la app acompañante (p. ej. la de música Bluetooth del radio) al iniciar, detrás.
  /// Se guarda además en `car_companion_package` (vacío = apagado) para el BootReceiver.
  final bool companionEnabled;
  final String companionPackage;

  /// Nombre visible de la app (solo para mostrar).
  final String companionLabel;

  /// Espera (ms) antes de volver a traer Pixel Car Player al frente. También en
  /// `car_companion_delay`.
  final int companionDelayMs;

  static const delayRange = CarRange(0, 60, 1);
  static const companionDelayRange = CarRange(0, 10000, 250);

  /// Paquete a abrir al iniciar ('' = ninguno).
  String get companionToLaunch => companionEnabled ? companionPackage : '';

  CarStartupOpts copyWith({
    bool? autostart,
    int? autostartDelay,
    bool? immersive,
    bool? lockLandscape,
    bool? startLyricsFullscreen,
    bool? companionEnabled,
    String? companionPackage,
    String? companionLabel,
    int? companionDelayMs,
  }) => CarStartupOpts(
    autostart: autostart ?? this.autostart,
    autostartDelay: autostartDelay ?? this.autostartDelay,
    immersive: immersive ?? this.immersive,
    lockLandscape: lockLandscape ?? this.lockLandscape,
    startLyricsFullscreen: startLyricsFullscreen ?? this.startLyricsFullscreen,
    companionEnabled: companionEnabled ?? this.companionEnabled,
    companionPackage: companionPackage ?? this.companionPackage,
    companionLabel: companionLabel ?? this.companionLabel,
    companionDelayMs: companionDelayMs ?? this.companionDelayMs,
  );

  @override
  Map<String, dynamic> toJson() => {
    'autostart': autostart,
    'autostartDelay': autostartDelay,
    'immersive': immersive,
    'lockLandscape': lockLandscape,
    'startLyricsFullscreen': startLyricsFullscreen,
    'companionEnabled': companionEnabled,
    'companionPackage': companionPackage,
    'companionLabel': companionLabel,
    'companionDelayMs': companionDelayMs,
  };

  factory CarStartupOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarStartupOpts();
    return CarStartupOpts(
      autostart: _bool(m['autostart'], d.autostart),
      autostartDelay: _num(m['autostartDelay'], d.autostartDelay.toDouble(), delayRange).round(),
      immersive: _bool(m['immersive'], d.immersive),
      lockLandscape: _bool(m['lockLandscape'], d.lockLandscape),
      startLyricsFullscreen: _bool(m['startLyricsFullscreen'], d.startLyricsFullscreen),
      companionEnabled: _bool(m['companionEnabled'], d.companionEnabled),
      companionPackage: _str(m['companionPackage'], d.companionPackage, 256),
      companionLabel: _str(m['companionLabel'], d.companionLabel, 128),
      companionDelayMs: _num(m['companionDelayMs'], d.companionDelayMs.toDouble(), companionDelayRange).round(),
    );
  }
}

/// Hotspot del carro (la tableta comparte su conexión; el celular se conecta a ella).
@immutable
class CarHotspotOpts with _JsonEquality {
  const CarHotspotOpts({
    this.autoEnable = false,
    this.recheckMinutes = 0,
    this.ssid = '',
    this.password = '',
    this.shareWithPhone = true,
    this.allowTemporary = false,
  });

  /// Al iniciar: verificar el hotspot y encenderlo si está apagado.
  final bool autoEnable;

  /// Volver a verificar cada N minutos (0 = solo al iniciar).
  final int recheckMinutes;

  /// Nombre y contraseña de la red (para el QR). Los escribe el usuario o se leen del sistema.
  final String ssid;
  final String password;

  /// Mandar la red al celular al conectar (`{"t":"hotspot"}`) para que se una solo.
  final bool shareWithPhone;

  /// Si el radio no deja encender su hotspot, permitir uno temporal (LocalOnlyHotspot, con
  /// nombre y clave aleatorios). Apagado: solo se usa la red configurada en el radio.
  final bool allowTemporary;

  static const recheckRange = CarRange(0, 60, 5);

  CarHotspotOpts copyWith({
    bool? autoEnable,
    int? recheckMinutes,
    String? ssid,
    String? password,
    bool? shareWithPhone,
    bool? allowTemporary,
  }) => CarHotspotOpts(
    autoEnable: autoEnable ?? this.autoEnable,
    recheckMinutes: recheckMinutes ?? this.recheckMinutes,
    ssid: ssid ?? this.ssid,
    password: password ?? this.password,
    shareWithPhone: shareWithPhone ?? this.shareWithPhone,
    allowTemporary: allowTemporary ?? this.allowTemporary,
  );

  @override
  Map<String, dynamic> toJson() => {
    'autoEnable': autoEnable,
    'recheckMinutes': recheckMinutes,
    'ssid': ssid,
    'password': password,
    'shareWithPhone': shareWithPhone,
    'allowTemporary': allowTemporary,
  };

  factory CarHotspotOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarHotspotOpts();
    return CarHotspotOpts(
      autoEnable: _bool(m['autoEnable'], d.autoEnable),
      recheckMinutes: _num(m['recheckMinutes'], d.recheckMinutes.toDouble(), recheckRange).round(),
      ssid: _str(m['ssid'], d.ssid, 64),
      password: _str(m['password'], d.password, 128),
      shareWithPhone: _bool(m['shareWithPhone'], d.shareWithPhone),
      allowTemporary: _bool(m['allowTemporary'], d.allowTemporary),
    );
  }
}

/// Texto del QR para unirse a una red Wi-Fi (`WIFI:T:WPA;S:<ssid>;P:<clave>;;`), con los
/// caracteres especiales escapados. Sin contraseña = red abierta (`T:nopass`).
String wifiQrData(String ssid, String password) {
  String esc(String v) => v.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  if (password.isEmpty) return 'WIFI:T:nopass;S:${esc(ssid)};;';
  return 'WIFI:T:WPA;S:${esc(ssid)};P:${esc(password)};;';
}

@immutable
class CarGestureOpts with _JsonEquality {
  const CarGestureOpts({this.tapCover = false, this.swipeCover = true});

  /// Tocar la portada = reproducir/pausar.
  final bool tapCover;

  /// Deslizar la portada a los lados = siguiente/anterior.
  final bool swipeCover;

  CarGestureOpts copyWith({bool? tapCover, bool? swipeCover}) =>
      CarGestureOpts(tapCover: tapCover ?? this.tapCover, swipeCover: swipeCover ?? this.swipeCover);

  @override
  Map<String, dynamic> toJson() => {'tapCover': tapCover, 'swipeCover': swipeCover};

  factory CarGestureOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarGestureOpts();
    return CarGestureOpts(tapCover: _bool(m['tapCover'], d.tapCover), swipeCover: _bool(m['swipeCover'], d.swipeCover));
  }
}

// ---------------------------------------------------------------------------
// v3: animaciones, reloj/espera, estilo, noche, controles, siempre encima, actualizaciones

/// Transición entre pantallas (reproductor ⇄ letra completa ⇄ reloj ⇄ Configuración).
enum CarScreenTransition {
  fade('Fundido'),
  sharedX('Eje X'),
  sharedY('Eje Y'),
  zoom('Zoom'),
  none('Ninguna');

  const CarScreenTransition(this.label);
  final String label;
}

/// Animación al cambiar la portada.
enum CarCoverChange {
  crossfade('Fundido'),
  slide('Deslizar'),
  scalePop('Escala'),
  morph('Forma');

  const CarCoverChange(this.label);
  final String label;
}

/// Modo rendimiento: menos barras, formas y desenfoque para mantener 60 fps.
enum CarPerfMode {
  auto('Automático'),
  on('Siempre'),
  off('Nunca');

  const CarPerfMode(this.label);
  final String label;
}

/// Tipografía de la interfaz.
enum CarFont {
  googleSans('Google Sans Flex', 'Google Sans Flex'),
  rubik('Rubik', 'Rubik'),
  system('Del sistema', null);

  const CarFont(this.label, this.family);
  final String label;

  /// Familia de Flutter (`null` = la del sistema).
  final String? family;
}

/// Estilo de la barra de progreso.
enum CarProgressStyle {
  wavy('Ondulada'),
  plain('Plana'),
  thin('Fina');

  const CarProgressStyle(this.label);
  final String label;
}

/// Fondo del reproductor.
enum CarBackground {
  shapes('Formas'),
  blurredCover('Portada difuminada'),
  solid('Sólido'),
  gradient('Degradado');

  const CarBackground(this.label);
  final String label;
}

/// Bordes de los chips.
enum CarChipCorners {
  rounded('Redondeados'),
  pill('Píldora');

  const CarChipCorners(this.label);
  final String label;
}

/// Qué muestra el tiempo de la izquierda.
enum CarTimeFormat {
  elapsed('Transcurrido'),
  remaining('Restante');

  const CarTimeFormat(this.label);
  final String label;
}

@immutable
class CarAnimOpts with _JsonEquality {
  const CarAnimOpts({
    this.splash = true,
    this.splashMs = 1300,
    this.transition = CarScreenTransition.fade,
    this.transitionMs = 400,
    this.entrance = true,
    this.entranceMs = 550,
    this.staggerMs = 60,
    this.coverChange = CarCoverChange.crossfade,
    this.chipAnim = true,
    this.listEntrance = true,
    this.pressIntensity = 1.0,
    this.perf = CarPerfMode.auto,
  });

  /// Animación de inicio (logo con forma que cambia → contenido).
  final bool splash;
  final int splashMs;
  final CarScreenTransition transition;
  final int transitionMs;

  /// Entrada escalonada de encabezado, portada, detalles, controles y panel.
  final bool entrance;
  final int entranceMs;
  final int staggerMs;
  final CarCoverChange coverChange;

  /// Los chips de estado entran y salen con animación.
  final bool chipAnim;

  /// Las secciones de Configuración entran escalonadas.
  final bool listEntrance;

  /// Intensidad de la respuesta al presionar botones (0 = ninguna, 1 = Harmonix).
  final double pressIntensity;
  final CarPerfMode perf;

  static const splashMsRange = CarRange(400, 3000, 100);
  static const transitionMsRange = CarRange(150, 1200, 50);
  static const entranceMsRange = CarRange(200, 1200, 50);
  static const staggerMsRange = CarRange(0, 200, 10);
  static const pressRange = CarRange(0, 2, 0.1);

  CarAnimOpts copyWith({
    bool? splash,
    int? splashMs,
    CarScreenTransition? transition,
    int? transitionMs,
    bool? entrance,
    int? entranceMs,
    int? staggerMs,
    CarCoverChange? coverChange,
    bool? chipAnim,
    bool? listEntrance,
    double? pressIntensity,
    CarPerfMode? perf,
  }) => CarAnimOpts(
    splash: splash ?? this.splash,
    splashMs: splashMs ?? this.splashMs,
    transition: transition ?? this.transition,
    transitionMs: transitionMs ?? this.transitionMs,
    entrance: entrance ?? this.entrance,
    entranceMs: entranceMs ?? this.entranceMs,
    staggerMs: staggerMs ?? this.staggerMs,
    coverChange: coverChange ?? this.coverChange,
    chipAnim: chipAnim ?? this.chipAnim,
    listEntrance: listEntrance ?? this.listEntrance,
    pressIntensity: pressIntensity ?? this.pressIntensity,
    perf: perf ?? this.perf,
  );

  @override
  Map<String, dynamic> toJson() => {
    'splash': splash,
    'splashMs': splashMs,
    'transition': transition.name,
    'transitionMs': transitionMs,
    'entrance': entrance,
    'entranceMs': entranceMs,
    'staggerMs': staggerMs,
    'coverChange': coverChange.name,
    'chipAnim': chipAnim,
    'listEntrance': listEntrance,
    'pressIntensity': pressIntensity,
    'perf': perf.name,
  };

  factory CarAnimOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarAnimOpts();
    return CarAnimOpts(
      splash: _bool(m['splash'], d.splash),
      splashMs: _num(m['splashMs'], d.splashMs.toDouble(), splashMsRange).round(),
      transition: _enum(CarScreenTransition.values, m['transition'], d.transition),
      transitionMs: _num(m['transitionMs'], d.transitionMs.toDouble(), transitionMsRange).round(),
      entrance: _bool(m['entrance'], d.entrance),
      entranceMs: _num(m['entranceMs'], d.entranceMs.toDouble(), entranceMsRange).round(),
      staggerMs: _num(m['staggerMs'], d.staggerMs.toDouble(), staggerMsRange).round(),
      coverChange: _enum(CarCoverChange.values, m['coverChange'], d.coverChange),
      chipAnim: _bool(m['chipAnim'], d.chipAnim),
      listEntrance: _bool(m['listEntrance'], d.listEntrance),
      pressIntensity: _num(m['pressIntensity'], d.pressIntensity, pressRange),
      perf: _enum(CarPerfMode.values, m['perf'], d.perf),
    );
  }
}

/// Reloj de espera (protector de pantalla).
@immutable
class CarStandbyOpts with _JsonEquality {
  const CarStandbyOpts({
    this.idleMinutes = 10,
    this.whenDisconnected = false,
    this.use24h = true,
    this.seconds = false,
    this.date = true,
    this.cover = true,
    this.shapes = true,
    this.burnIn = true,
    this.clockScale = 1.0,
  });

  /// Sin nada sonando durante N minutos se muestra el reloj (0 = nunca).
  final int idleMinutes;

  /// Sin celular conectado se muestra el reloj en vez de la pantalla de espera.
  final bool whenDisconnected;
  final bool use24h;
  final bool seconds;
  final bool date;

  /// La portada de lo último que sonó, chiquita.
  final bool cover;

  /// Formas que flotan despacio detrás del reloj.
  final bool shapes;

  /// Corre todo unos píxeles cada minuto (protege pantallas OLED/LCD de marcas).
  final bool burnIn;
  final double clockScale;

  static const idleRange = CarRange(0, 60, 1);
  static const clockScaleRange = CarRange(0.6, 1.4, 0.05);

  CarStandbyOpts copyWith({
    int? idleMinutes,
    bool? whenDisconnected,
    bool? use24h,
    bool? seconds,
    bool? date,
    bool? cover,
    bool? shapes,
    bool? burnIn,
    double? clockScale,
  }) => CarStandbyOpts(
    idleMinutes: idleMinutes ?? this.idleMinutes,
    whenDisconnected: whenDisconnected ?? this.whenDisconnected,
    use24h: use24h ?? this.use24h,
    seconds: seconds ?? this.seconds,
    date: date ?? this.date,
    cover: cover ?? this.cover,
    shapes: shapes ?? this.shapes,
    burnIn: burnIn ?? this.burnIn,
    clockScale: clockScale ?? this.clockScale,
  );

  @override
  Map<String, dynamic> toJson() => {
    'idleMinutes': idleMinutes,
    'whenDisconnected': whenDisconnected,
    'use24h': use24h,
    'seconds': seconds,
    'date': date,
    'cover': cover,
    'shapes': shapes,
    'burnIn': burnIn,
    'clockScale': clockScale,
  };

  factory CarStandbyOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarStandbyOpts();
    return CarStandbyOpts(
      idleMinutes: _num(m['idleMinutes'], d.idleMinutes.toDouble(), idleRange).round(),
      whenDisconnected: _bool(m['whenDisconnected'], d.whenDisconnected),
      use24h: _bool(m['use24h'], d.use24h),
      seconds: _bool(m['seconds'], d.seconds),
      date: _bool(m['date'], d.date),
      cover: _bool(m['cover'], d.cover),
      shapes: _bool(m['shapes'], d.shapes),
      burnIn: _bool(m['burnIn'], d.burnIn),
      clockScale: _num(m['clockScale'], d.clockScale, clockScaleRange),
    );
  }
}

/// Tipografía y disposición del reproductor.
@immutable
class CarStyleOpts with _JsonEquality {
  const CarStyleOpts({
    this.font = CarFont.googleSans,
    this.titleWeight = 500,
    this.letterSpacing = -0.01,
    this.headerHeight = 60,
    this.sidePanelPct = 0,
    this.coverRight = false,
    this.controlsBottom = false,
    this.timeFormat = CarTimeFormat.elapsed,
    this.showRemaining = false,
    this.background = CarBackground.shapes,
    this.backgroundDim = 0,
    this.chipCorners = CarChipCorners.rounded,
    this.haptics = true,
  });

  final CarFont font;

  /// Peso del título (300–900, fuente variable).
  final int titleWeight;

  /// Espaciado de letras del título (em).
  final double letterSpacing;

  /// Alto del encabezado (px, incluye el margen de arriba).
  final double headerHeight;

  /// Ancho del panel lateral en % del escenario (0 = automático).
  final int sidePanelPct;

  /// Portada a la derecha (la fila se invierte).
  final bool coverRight;

  /// Controles en una barra abajo a todo el ancho (en vez de debajo de los datos).
  final bool controlsBottom;
  final CarTimeFormat timeFormat;

  /// A la derecha, el tiempo restante (−m:ss) en vez de la duración.
  final bool showRemaining;
  final CarBackground background;

  /// Oscurece el fondo (0–0,8).
  final double backgroundDim;
  final CarChipCorners chipCorners;

  /// Vibración corta al tocar los controles.
  final bool haptics;

  static const titleWeightRange = CarRange(300, 900, 100);
  static const letterSpacingRange = CarRange(-0.05, 0.1, 0.005);
  static const headerHeightRange = CarRange(44, 96, 2);
  static const sidePanelRange = CarRange(0, 60, 5);
  static const backgroundDimRange = CarRange(0, 0.8, 0.05);

  CarStyleOpts copyWith({
    CarFont? font,
    int? titleWeight,
    double? letterSpacing,
    double? headerHeight,
    int? sidePanelPct,
    bool? coverRight,
    bool? controlsBottom,
    CarTimeFormat? timeFormat,
    bool? showRemaining,
    CarBackground? background,
    double? backgroundDim,
    CarChipCorners? chipCorners,
    bool? haptics,
  }) => CarStyleOpts(
    font: font ?? this.font,
    titleWeight: titleWeight ?? this.titleWeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    headerHeight: headerHeight ?? this.headerHeight,
    sidePanelPct: sidePanelPct ?? this.sidePanelPct,
    coverRight: coverRight ?? this.coverRight,
    controlsBottom: controlsBottom ?? this.controlsBottom,
    timeFormat: timeFormat ?? this.timeFormat,
    showRemaining: showRemaining ?? this.showRemaining,
    background: background ?? this.background,
    backgroundDim: backgroundDim ?? this.backgroundDim,
    chipCorners: chipCorners ?? this.chipCorners,
    haptics: haptics ?? this.haptics,
  );

  @override
  Map<String, dynamic> toJson() => {
    'font': font.name,
    'titleWeight': titleWeight,
    'letterSpacing': letterSpacing,
    'headerHeight': headerHeight,
    'sidePanelPct': sidePanelPct,
    'coverRight': coverRight,
    'controlsBottom': controlsBottom,
    'timeFormat': timeFormat.name,
    'showRemaining': showRemaining,
    'background': background.name,
    'backgroundDim': backgroundDim,
    'chipCorners': chipCorners.name,
    'haptics': haptics,
  };

  factory CarStyleOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarStyleOpts();
    return CarStyleOpts(
      font: _enum(CarFont.values, m['font'], d.font),
      titleWeight: (_num(m['titleWeight'], d.titleWeight.toDouble(), titleWeightRange) / 100).round() * 100,
      letterSpacing: _num(m['letterSpacing'], d.letterSpacing, letterSpacingRange),
      headerHeight: _num(m['headerHeight'], d.headerHeight, headerHeightRange),
      sidePanelPct: _num(m['sidePanelPct'], d.sidePanelPct.toDouble(), sidePanelRange).round(),
      coverRight: _bool(m['coverRight'], d.coverRight),
      controlsBottom: _bool(m['controlsBottom'], d.controlsBottom),
      timeFormat: _enum(CarTimeFormat.values, m['timeFormat'], d.timeFormat),
      showRemaining: _bool(m['showRemaining'], d.showRemaining),
      background: _enum(CarBackground.values, m['background'], d.background),
      backgroundDim: _num(m['backgroundDim'], d.backgroundDim, backgroundDimRange),
      chipCorners: _enum(CarChipCorners.values, m['chipCorners'], d.chipCorners),
      haptics: _bool(m['haptics'], d.haptics),
    );
  }
}

/// Modo noche: atenúa la pantalla en un horario (y el tema "Por horario" usa el mismo).
@immutable
class CarNightOpts with _JsonEquality {
  const CarNightOpts({this.dim = false, this.start = 19 * 60, this.end = 6 * 60 + 30, this.dimAmount = 0.35});

  final bool dim;

  /// Minutos desde la medianoche.
  final int start;
  final int end;

  /// Cuánto se oscurece (0,05–0,8).
  final double dimAmount;

  static const minuteRange = CarRange(0, 1439, 15);
  static const dimRange = CarRange(0.05, 0.8, 0.05);

  /// ¿[now] cae dentro del horario de noche? (cruza la medianoche si start > end).
  bool isNight(DateTime now) {
    final m = now.hour * 60 + now.minute;
    if (start == end) return false;
    return start < end ? (m >= start && m < end) : (m >= start || m < end);
  }

  CarNightOpts copyWith({bool? dim, int? start, int? end, double? dimAmount}) => CarNightOpts(
    dim: dim ?? this.dim,
    start: start ?? this.start,
    end: end ?? this.end,
    dimAmount: dimAmount ?? this.dimAmount,
  );

  @override
  Map<String, dynamic> toJson() => {'dim': dim, 'start': start, 'end': end, 'dimAmount': dimAmount};

  factory CarNightOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarNightOpts();
    return CarNightOpts(
      dim: _bool(m['dim'], d.dim),
      start: _num(m['start'], d.start.toDouble(), minuteRange).round(),
      end: _num(m['end'], d.end.toDouble(), minuteRange).round(),
      dimAmount: _num(m['dimAmount'], d.dimAmount, dimRange),
    );
  }
}

/// Aleatorio / repetir / me gusta y la cola.
@immutable
class CarControlsOpts with _JsonEquality {
  const CarControlsOpts({this.hideUnavailable = true, this.queueTapToSkip = true, this.queueCovers = true});

  /// Oculta aleatorio / repetir / me gusta si la app del celular no los permite (si no, se
  /// ven deshabilitados).
  final bool hideUnavailable;

  /// Tocar un tema de "A continuación" salta a ese tema.
  final bool queueTapToSkip;

  /// Miniaturas en "A continuación".
  final bool queueCovers;

  CarControlsOpts copyWith({bool? hideUnavailable, bool? queueTapToSkip, bool? queueCovers}) => CarControlsOpts(
    hideUnavailable: hideUnavailable ?? this.hideUnavailable,
    queueTapToSkip: queueTapToSkip ?? this.queueTapToSkip,
    queueCovers: queueCovers ?? this.queueCovers,
  );

  @override
  Map<String, dynamic> toJson() => {
    'hideUnavailable': hideUnavailable,
    'queueTapToSkip': queueTapToSkip,
    'queueCovers': queueCovers,
  };

  factory CarControlsOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarControlsOpts();
    return CarControlsOpts(
      hideUnavailable: _bool(m['hideUnavailable'], d.hideUnavailable),
      queueTapToSkip: _bool(m['queueTapToSkip'], d.queueTapToSkip),
      queueCovers: _bool(m['queueCovers'], d.queueCovers),
    );
  }
}

/// Mantener Pixel Car Player encima de otras apps (p. ej. la de música Bluetooth) y la
/// burbuja flotante.
@immutable
class CarKeepFrontOpts with _JsonEquality {
  const CarKeepFrontOpts({
    this.enabled = false,
    this.apps = const {},
    this.anyApp = false,
    this.includeLauncher = false,
    this.delayMs = 1500,
    this.bubble = false,
    this.bubbleSize = 64,
    this.bubbleOpacity = 0.9,
  });

  /// Volver a Pixel Car Player cuando se abran [apps] (o cualquiera con [anyApp]).
  final bool enabled;

  /// Paquete → nombre visible.
  final Map<String, String> apps;
  final bool anyApp;

  /// Con "cualquier app", también al volver a la pantalla de inicio (launcher).
  final bool includeLauncher;
  final int delayMs;
  final bool bubble;
  final int bubbleSize;
  final double bubbleOpacity;

  static const delayRange = CarRange(0, 10000, 250);
  static const bubbleSizeRange = CarRange(40, 120, 4);
  static const bubbleOpacityRange = CarRange(0.3, 1, 0.05);

  CarKeepFrontOpts copyWith({
    bool? enabled,
    Map<String, String>? apps,
    bool? anyApp,
    bool? includeLauncher,
    int? delayMs,
    bool? bubble,
    int? bubbleSize,
    double? bubbleOpacity,
  }) => CarKeepFrontOpts(
    enabled: enabled ?? this.enabled,
    apps: apps ?? this.apps,
    anyApp: anyApp ?? this.anyApp,
    includeLauncher: includeLauncher ?? this.includeLauncher,
    delayMs: delayMs ?? this.delayMs,
    bubble: bubble ?? this.bubble,
    bubbleSize: bubbleSize ?? this.bubbleSize,
    bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
  );

  /// Config para `setKeepInFront` ([fallback] = la app acompañante si no se eligió ninguna).
  Map<String, dynamic> nativeConfig({String fallback = ''}) => {
    'enabled': enabled,
    'packages': apps.isEmpty && fallback.isNotEmpty && !anyApp ? [fallback] : apps.keys.toList(),
    'anyApp': anyApp,
    'includeLauncher': includeLauncher,
    'delayMs': delayMs,
  };

  Map<String, dynamic> bubbleConfig() => {'enabled': bubble, 'size': bubbleSize, 'opacity': bubbleOpacity};

  @override
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'apps': apps,
    'anyApp': anyApp,
    'includeLauncher': includeLauncher,
    'delayMs': delayMs,
    'bubble': bubble,
    'bubbleSize': bubbleSize,
    'bubbleOpacity': bubbleOpacity,
  };

  factory CarKeepFrontOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarKeepFrontOpts();
    final apps = <String, String>{};
    for (final e in _map(m['apps']).entries) {
      if (e.key.isEmpty || e.key.length > 256 || apps.length >= 32) continue;
      apps[e.key] = _str(e.value, e.key, 128);
    }
    return CarKeepFrontOpts(
      enabled: _bool(m['enabled'], d.enabled),
      apps: Map.unmodifiable(apps),
      anyApp: _bool(m['anyApp'], d.anyApp),
      includeLauncher: _bool(m['includeLauncher'], d.includeLauncher),
      delayMs: _num(m['delayMs'], d.delayMs.toDouble(), delayRange).round(),
      bubble: _bool(m['bubble'], d.bubble),
      bubbleSize: _num(m['bubbleSize'], d.bubbleSize.toDouble(), bubbleSizeRange).round(),
      bubbleOpacity: _num(m['bubbleOpacity'], d.bubbleOpacity, bubbleOpacityRange),
    );
  }
}

@immutable
class CarUpdateOpts with _JsonEquality {
  const CarUpdateOpts({this.autoCheck = true, this.backupBeforeInstall = true});

  /// Buscar actualizaciones al iniciar (una vez por día).
  final bool autoCheck;

  /// Exportar la configuración a un archivo antes de instalar.
  final bool backupBeforeInstall;

  CarUpdateOpts copyWith({bool? autoCheck, bool? backupBeforeInstall}) => CarUpdateOpts(
    autoCheck: autoCheck ?? this.autoCheck,
    backupBeforeInstall: backupBeforeInstall ?? this.backupBeforeInstall,
  );

  @override
  Map<String, dynamic> toJson() => {'autoCheck': autoCheck, 'backupBeforeInstall': backupBeforeInstall};

  factory CarUpdateOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarUpdateOpts();
    return CarUpdateOpts(
      autoCheck: _bool(m['autoCheck'], d.autoCheck),
      backupBeforeInstall: _bool(m['backupBeforeInstall'], d.backupBeforeInstall),
    );
  }
}

// ---------------------------------------------------------------------------
// Todo junto

@immutable
class CarCustomization {
  const CarCustomization({
    this.design = const CarDesign(),
    this.cover = const CarCoverOpts(),
    this.visualizer = const CarVisualizerOpts(),
    this.lyrics = const CarLyricsOpts(),
    this.visibility = const CarVisibility(),
    this.texts = const CarTexts(),
    this.connection = const CarConnectionOpts(),
    this.startup = const CarStartupOpts(),
    this.hotspot = const CarHotspotOpts(),
    this.gestures = const CarGestureOpts(),
    this.anim = const CarAnimOpts(),
    this.standby = const CarStandbyOpts(),
    this.style = const CarStyleOpts(),
    this.night = const CarNightOpts(),
    this.controls = const CarControlsOpts(),
    this.keepFront = const CarKeepFrontOpts(),
    this.updates = const CarUpdateOpts(),
  });

  static const defaults = CarCustomization();
  static const version = 1;

  final CarDesign design;
  final CarCoverOpts cover;
  final CarVisualizerOpts visualizer;
  final CarLyricsOpts lyrics;
  final CarVisibility visibility;
  final CarTexts texts;
  final CarConnectionOpts connection;
  final CarStartupOpts startup;
  final CarHotspotOpts hotspot;
  final CarGestureOpts gestures;
  final CarAnimOpts anim;
  final CarStandbyOpts standby;
  final CarStyleOpts style;
  final CarNightOpts night;
  final CarControlsOpts controls;
  final CarKeepFrontOpts keepFront;
  final CarUpdateOpts updates;

  /// Atajo: ¿se ve el elemento?
  bool show(CarElement e) => visibility[e];

  /// Atajo: texto (vacío = oculto).
  String text(CarText t) => texts[t];

  CarCustomization copyWith({
    CarDesign? design,
    CarCoverOpts? cover,
    CarVisualizerOpts? visualizer,
    CarLyricsOpts? lyrics,
    CarVisibility? visibility,
    CarTexts? texts,
    CarConnectionOpts? connection,
    CarStartupOpts? startup,
    CarHotspotOpts? hotspot,
    CarGestureOpts? gestures,
    CarAnimOpts? anim,
    CarStandbyOpts? standby,
    CarStyleOpts? style,
    CarNightOpts? night,
    CarControlsOpts? controls,
    CarKeepFrontOpts? keepFront,
    CarUpdateOpts? updates,
  }) => CarCustomization(
    design: design ?? this.design,
    cover: cover ?? this.cover,
    visualizer: visualizer ?? this.visualizer,
    lyrics: lyrics ?? this.lyrics,
    visibility: visibility ?? this.visibility,
    texts: texts ?? this.texts,
    connection: connection ?? this.connection,
    startup: startup ?? this.startup,
    hotspot: hotspot ?? this.hotspot,
    gestures: gestures ?? this.gestures,
    anim: anim ?? this.anim,
    standby: standby ?? this.standby,
    style: style ?? this.style,
    night: night ?? this.night,
    controls: controls ?? this.controls,
    keepFront: keepFront ?? this.keepFront,
    updates: updates ?? this.updates,
  );

  /// Devuelve una copia con [section] en sus valores por defecto.
  CarCustomization resetSection(CarSection section) => switch (section) {
    CarSection.design => copyWith(design: const CarDesign()),
    CarSection.cover => copyWith(cover: const CarCoverOpts()),
    CarSection.visualizer => copyWith(visualizer: const CarVisualizerOpts()),
    CarSection.lyrics => copyWith(lyrics: const CarLyricsOpts()),
    CarSection.visibility => copyWith(visibility: const CarVisibility()),
    CarSection.texts => copyWith(texts: const CarTexts()),
    CarSection.connection => copyWith(connection: const CarConnectionOpts()),
    CarSection.startup => copyWith(startup: const CarStartupOpts()),
    CarSection.hotspot => copyWith(hotspot: const CarHotspotOpts()),
    CarSection.gestures => copyWith(gestures: const CarGestureOpts()),
    CarSection.animations => copyWith(anim: const CarAnimOpts()),
    CarSection.standby => copyWith(standby: const CarStandbyOpts()),
    CarSection.style => copyWith(style: const CarStyleOpts()),
    CarSection.night => copyWith(night: const CarNightOpts()),
    CarSection.controls => copyWith(controls: const CarControlsOpts()),
    CarSection.keepFront => copyWith(keepFront: const CarKeepFrontOpts()),
    CarSection.updates => copyWith(updates: const CarUpdateOpts()),
  };

  /// ¿La sección está en sus valores por defecto?
  bool isDefault(CarSection section) => resetSection(section) == this;

  Map<String, dynamic> toJson() => {
    'v': version,
    'design': design.toJson(),
    'cover': cover.toJson(),
    'visualizer': visualizer.toJson(),
    'lyrics': lyrics.toJson(),
    'visibility': visibility.toJson(),
    'texts': texts.toJson(),
    'connection': connection.toJson(),
    'startup': startup.toJson(),
    'hotspot': hotspot.toJson(),
    'gestures': gestures.toJson(),
    'anim': anim.toJson(),
    'standby': standby.toJson(),
    'style': style.toJson(),
    'night': night.toJson(),
    'controls': controls.toJson(),
    'keepFront': keepFront.toJson(),
    'updates': updates.toJson(),
  };

  /// Lee un JSON; lo que falte o sea inválido toma el valor por defecto.
  /// [shapes]: nombres de forma válidos (si se pasa, una forma desconocida vuelve a la de fábrica).
  factory CarCustomization.fromJson(Object? json, {Set<String>? shapes}) {
    final m = _map(json);
    return CarCustomization(
      design: CarDesign.fromJson(m['design']),
      cover: CarCoverOpts.fromJson(m['cover'], shapes: shapes),
      visualizer: CarVisualizerOpts.fromJson(m['visualizer']),
      lyrics: CarLyricsOpts.fromJson(m['lyrics']),
      visibility: CarVisibility.fromJson(m['visibility']),
      texts: CarTexts.fromJson(m['texts']),
      connection: CarConnectionOpts.fromJson(m['connection']),
      startup: CarStartupOpts.fromJson(m['startup']),
      hotspot: CarHotspotOpts.fromJson(m['hotspot']),
      gestures: CarGestureOpts.fromJson(m['gestures']),
      anim: CarAnimOpts.fromJson(m['anim']),
      standby: CarStandbyOpts.fromJson(m['standby']),
      style: CarStyleOpts.fromJson(m['style']),
      night: CarNightOpts.fromJson(m['night']),
      controls: CarControlsOpts.fromJson(m['controls']),
      keepFront: CarKeepFrontOpts.fromJson(m['keepFront']),
      updates: CarUpdateOpts.fromJson(m['updates']),
    );
  }

  /// Texto JSON legible (exportar).
  String encode({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

  /// Lee el texto exportado. Lanza [FormatException] si no es un objeto JSON.
  static CarCustomization decode(String text, {Set<String>? shapes}) {
    final Object? raw = jsonDecode(text.trim());
    if (raw is! Map) throw const FormatException('Se esperaba un objeto JSON');
    return CarCustomization.fromJson(raw, shapes: shapes);
  }

  @override
  bool operator ==(Object other) =>
      other is CarCustomization &&
      other.design == design &&
      other.cover == cover &&
      other.visualizer == visualizer &&
      other.lyrics == lyrics &&
      other.visibility == visibility &&
      other.texts == texts &&
      other.connection == connection &&
      other.startup == startup &&
      other.hotspot == hotspot &&
      other.gestures == gestures &&
      other.anim == anim &&
      other.standby == standby &&
      other.style == style &&
      other.night == night &&
      other.controls == controls &&
      other.keepFront == keepFront &&
      other.updates == updates;

  @override
  int get hashCode => Object.hash(
    design,
    cover,
    visualizer,
    lyrics,
    visibility,
    texts,
    connection,
    startup,
    hotspot,
    gestures,
    anim,
    standby,
    style,
    night,
    controls,
    keepFront,
    updates,
  );
}

// ---------------------------------------------------------------------------
// Ayudas de lectura

Map<String, dynamic> _map(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
  return const {};
}

double _num(Object? v, double def, CarRange r) => v is num && v.isFinite ? r.clamp(v.toDouble()) : def;

bool _bool(Object? v, bool def) => v is bool ? v : def;

String _str(Object? v, String def, int maxLen) => v is String ? (v.length > maxLen ? v.substring(0, maxLen) : v) : def;

T _enum<T extends Enum>(List<T> values, Object? v, T def) {
  for (final e in values) {
    if (e.name == v) return e;
  }
  return def;
}

/// `#RRGGBB` (o `#AARRGGBB`) de un ARGB.
String colorHex(int argb) {
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  return '#$rgb';
}

/// Lee `#RGB`, `#RRGGBB`, `RRGGBB` o `#AARRGGBB` (siempre opaco). `null` si no es válido.
int? parseColorHex(Object? v) {
  if (v is int) return 0xFF000000 | (v & 0xFFFFFF);
  if (v is! String) return null;
  var s = v.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length == 8) s = s.substring(2);
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : 0xFF000000 | n;
}
