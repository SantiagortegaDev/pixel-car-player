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

enum CarThemeMode { dark, light, auto }

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

/// Secciones del modelo (para restablecer por partes).
enum CarSection { connection, startup, hotspot, design, cover, visualizer, lyrics, visibility, texts, gestures }

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
    this.wavy = true,
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
  final bool wavy;
  final double waveAmplitude;
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
    bool? wavy,
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
    wavy: wavy ?? this.wavy,
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
      wavy: _bool(m['wavy'], d.wavy),
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
  });

  final double scale;

  /// Multiplicador del espacio entre líneas.
  final double spacing;
  final CarLyricsAlign align;
  final bool glow;

  /// Adelanto con el que se resalta la línea (compensa la latencia del Bluetooth).
  final int offsetMs;
  final CarSeekMode seek;

  static const scaleRange = CarRange(0.7, 1.8, 0.05);
  static const spacingRange = CarRange(0.5, 3.0, 0.1);
  static const offsetRange = CarRange(-1000, 2000, 50);

  CarLyricsOpts copyWith({
    double? scale,
    double? spacing,
    CarLyricsAlign? align,
    bool? glow,
    int? offsetMs,
    CarSeekMode? seek,
  }) => CarLyricsOpts(
    scale: scale ?? this.scale,
    spacing: spacing ?? this.spacing,
    align: align ?? this.align,
    glow: glow ?? this.glow,
    offsetMs: offsetMs ?? this.offsetMs,
    seek: seek ?? this.seek,
  );

  @override
  Map<String, dynamic> toJson() => {
    'scale': scale,
    'spacing': spacing,
    'align': align.name,
    'glow': glow,
    'offsetMs': offsetMs,
    'seek': seek.name,
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
  const CarHotspotOpts({this.autoEnable = false, this.recheckMinutes = 0, this.ssid = '', this.password = ''});

  /// Al iniciar: verificar el hotspot y encenderlo si está apagado.
  final bool autoEnable;

  /// Volver a verificar cada N minutos (0 = solo al iniciar).
  final int recheckMinutes;

  /// Nombre y contraseña de la red (para el QR). Los escribe el usuario o se leen del sistema.
  final String ssid;
  final String password;

  static const recheckRange = CarRange(0, 60, 5);

  CarHotspotOpts copyWith({bool? autoEnable, int? recheckMinutes, String? ssid, String? password}) => CarHotspotOpts(
    autoEnable: autoEnable ?? this.autoEnable,
    recheckMinutes: recheckMinutes ?? this.recheckMinutes,
    ssid: ssid ?? this.ssid,
    password: password ?? this.password,
  );

  @override
  Map<String, dynamic> toJson() => {
    'autoEnable': autoEnable,
    'recheckMinutes': recheckMinutes,
    'ssid': ssid,
    'password': password,
  };

  factory CarHotspotOpts.fromJson(Object? json) {
    final m = _map(json);
    const d = CarHotspotOpts();
    return CarHotspotOpts(
      autoEnable: _bool(m['autoEnable'], d.autoEnable),
      recheckMinutes: _num(m['recheckMinutes'], d.recheckMinutes.toDouble(), recheckRange).round(),
      ssid: _str(m['ssid'], d.ssid, 64),
      password: _str(m['password'], d.password, 128),
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
      other.gestures == gestures;

  @override
  int get hashCode =>
      Object.hash(design, cover, visualizer, lyrics, visibility, texts, connection, startup, hotspot, gestures);
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
