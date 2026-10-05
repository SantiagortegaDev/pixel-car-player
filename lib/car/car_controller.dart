import 'dart:async';
import 'dart:ui' show Brightness, Color, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:pixel_car_player/car/audio/car_audio_levels.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/lyrics/lrclib_client.dart';
import 'package:pixel_car_player/car/system/car_backup.dart';
import 'package:pixel_car_player/car/system/car_connectivity.dart';
import 'package:pixel_car_player/car/system/car_hotspot.dart';
import 'package:pixel_car_player/car/system/car_performance.dart';
import 'package:pixel_car_player/car/system/car_updates.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// Qué mueve las barras del visualizador ahora mismo (Configuración → Portada y visualizador).
enum CarVizNow {
  /// Audio real con señal.
  real,

  /// Se pidió audio real pero no llega señal (el radio no pasa el audio por Android, sin
  /// permiso o sin cuadros); con "Automático" se usa el simulado.
  realNoSignal,

  /// Espectro simulado (elegido).
  simulated,
}

/// De dónde vienen los datos que se muestran.
enum CarSource {
  /// Nada que mostrar (pantalla de espera).
  none,

  /// Celular conectado por el enlace (Wi-Fi/BT).
  phone,

  /// Sesión multimedia local de la tableta (fallback sin celular).
  local,

  /// Datos simulados.
  demo,
}

/// Estado de la pantalla del carro.
///
/// Recibe mensajes del enlace (o de la demo / sesión local), mantiene un
/// [NowPlaying] y expone comandos. La posición "en vivo" se publica aparte
/// en [position] (≈4 fps) y [lyricIndex] para no reconstruir toda la UI.
class CarController extends ChangeNotifier {
  CarController({
    bool demo = false,
    CarPrefs? prefs,
    CarCustomizationStore? custom,
    CarLinkClient? link,
    NativeBridge? bridge,
    LrcLibClient? lrclib,
    DemoSource Function()? demoFactory,
    Future<Color> Function(Uint8List artwork)? seedBuilder,
    CarHotspot? hotspot,
    CarAudioLevels? audio,
    CarTrustStore? trust,
    CarConnectivity? connectivity,
    CarUpdater? updater,
    CarPerformance? performance,
  }) : _bridge = bridge ?? NativeBridge.instance,
       hotspot = hotspot ?? CarHotspot(bridge: bridge),
       audio = audio ?? CarAudioLevels(),
       connectivity = connectivity ?? CarConnectivity(bridge: bridge),
       updater = updater ?? CarUpdater(bridge: bridge),
       prefs = prefs ?? CarPrefs(demo: demo),
       _ownsCustom = custom == null,
       custom = custom ?? CarCustomizationStore(),
       _demoFactory = demoFactory ?? DemoSource.fromUrl,
       _seedBuilder = seedBuilder ?? AppTheme.seedFromImageBytes {
    _lrclib = lrclib;
    this.prefs.demo = demo || this.prefs.demo;
    final conn = this.custom.value.connection;
    this.link =
        link ??
        CarLinkClient(
          bridge: _bridge,
          manualIp: conn.transport == CarTransport.bt ? null : this.prefs.manualIp,
          btAddress: conn.transport == CarTransport.wifi ? null : this.prefs.btAddress,
          btName: this.prefs.btName,
          useWifi: conn.transport != CarTransport.bt,
          maxBackoff: Duration(seconds: conn.reconnectSeconds),
          trust: trust,
        );
    this.performance = performance ?? CarPerformance(mode: this.custom.value.anim.perf);
    this.performance.addListener(_changed);
    this.updater.backup = saveBackupToFile;
    _lastConnection = conn;
    _lastKeepFront = this.custom.value.keepFront;
    _lastViz = this.custom.value.visualizer;
    _lastHotspot = this.custom.value.hotspot;
    this.hotspot.allowTemporary = this.custom.value.hotspot.allowTemporary;
    this.audio.fastGain = _lastViz.response == CarVizResponse.precise;
    this.custom.addListener(_onCustom);
    this.audio.detected.addListener(_changed);
  }

  final NativeBridge _bridge;
  final DemoSource Function() _demoFactory;
  final Future<Color> Function(Uint8List artwork) _seedBuilder;

  /// Personalización de la pantalla (se aplica en vivo).
  final CarCustomizationStore custom;
  final bool _ownsCustom;
  late CarConnectionOpts _lastConnection;
  late CarVisualizerOpts _lastViz;
  late CarHotspotOpts _lastHotspot;

  /// Hotspot del carro (Configuración → Hotspot).
  final CarHotspot hotspot;

  /// Audio real de la tableta para el visualizador.
  final CarAudioLevels audio;

  /// Bluetooth / Wi-Fi del radio (chips del encabezado y Diagnóstico).
  final CarConnectivity connectivity;

  /// Actualizaciones de la app (Configuración → Actualizaciones).
  final CarUpdater updater;

  /// Modo rendimiento (menos barras / formas / desenfoque).
  late final CarPerformance performance;
  late CarKeepFrontOpts _lastKeepFront;

  /// Celulares de confianza y "Requerir emparejamiento".
  CarTrustStore get trust => link.trust;

  /// Resultado del último pedido de permiso de audio (`null` = aún no se pidió).
  bool? audioPermission;

  /// El Visualizer nativo está corriendo.
  bool visualizerRunning = false;
  bool _audioAsked = false;
  bool _foreground = true;
  Future<void> _vizOp = Future.value();

  /// Se abrió la app acompañante en este arranque.
  bool companionLaunched = false;

  CarCustomization get cfg => custom.value;

  /// Esquema cuando no hay carátula.
  static final ColorScheme fallbackScheme = AppTheme.schemeFromSeed(AppTheme.fallbackSeed);
  LrcLibClient? _lrclib;
  late final CarLinkClient link;
  CarPrefs prefs;

  /// Adelanto con el que se resalta la línea de letra (compensa latencia BT); se ajusta
  /// en Configuración → Letra.
  Duration get lyricLead => Duration(milliseconds: cfg.lyrics.offsetMs);

  // ---- Estado ----
  NowPlaying _remote = const NowPlaying(); // celular o demo
  NowPlaying _local = const NowPlaying();
  List<QueueItem> _queue = const [];
  String? _remoteDevice;
  String? _remoteSource;
  Color? _artSeed;
  Uint8List? _seedFor;
  final Map<String, Color> _seedCache = {};
  static const _seedCacheSize = 24;
  ColorScheme? _schemeMemo;
  Object? _schemeMemoKey;
  List<String> tabletIps = const [];

  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<int> lyricIndex = ValueNotifier(-1);

  DemoSource? _demo;
  StreamSubscription<LinkMessage>? _msgSub;
  StreamSubscription<void>? _authSub;

  /// Última red enviada al celular en este enlace (para no repetirla).
  String? _sharedHotspot;
  StreamSubscription<LinkMessage>? _demoSub;
  StreamSubscription<Map<String, dynamic>>? _nativeSub;
  Timer? _ticker;
  Timer? _ipTimer;
  bool _started = false;
  bool _disposed = false;
  bool _linkStarted = false;

  /// Demo de relleno mientras no hay celular (Conexión → "Mostrar demo sin celular").
  bool _idleDemo = false;

  bool get demo => prefs.demo;

  /// Se está buscando / manteniendo la conexión con el celular.
  bool get linkRunning => _linkStarted;

  /// Se muestra la demo porque no hay celular (no es el modo demo).
  bool get idleDemo => _idleDemo;
  ValueListenable<LinkStatus> get linkStatus => link.status;

  /// Estado del enlace a mostrar (en demo se finge conectado).
  LinkStatus get displayStatus => demo
      ? LinkStatus.connected(device: _remoteDevice ?? 'Pixel 8 (demo)', transport: 'wifi', address: 'demo')
      : link.status.value;

  CarSource get source {
    if (demo) return CarSource.demo;
    if (link.status.value.isLinked) return CarSource.phone;
    if (_local.track != null) return CarSource.local;
    if (_idleDemo) return CarSource.demo;
    return CarSource.none;
  }

  NowPlaying get nowPlaying => switch (source) {
    CarSource.phone || CarSource.demo => _remote,
    CarSource.local => _local,
    CarSource.none => const NowPlaying(),
  };

  /// Próximos temas que mandó el celular (vacío si no hay o no llegó `queue`).
  List<QueueItem> get queue => switch (source) {
    CarSource.phone || CarSource.demo => _queue,
    _ => const [],
  };

  /// Paquete de la app de música (`com.spotify.music`…).
  String? get sourcePackage => source == CarSource.local ? _localPackage : (nowPlaying.track?.source ?? _remoteSource);

  /// Semilla del color: la de la carátula que suena o el color fijo de Configuración.
  Color get seed => cfg.design.colorSource == CarColorSource.fixed
      ? Color(cfg.design.fixedColor)
      : (_artSeed ?? AppTheme.fallbackSeed);

  /// Esquema de color actual (variante y modo de Configuración). [platform] se usa con
  /// el tema "Automático".
  ColorScheme schemeFor([Brightness? platform]) {
    final d = cfg.design;
    final brightness = switch (d.themeMode) {
      CarThemeMode.dark => Brightness.dark,
      CarThemeMode.light => Brightness.light,
      CarThemeMode.auto => platform ?? PlatformDispatcher.instance.platformBrightness,
      CarThemeMode.schedule => night ? Brightness.dark : Brightness.light,
    };
    final key = (seed.toARGB32(), d.variant, brightness);
    if (key == _schemeMemoKey && _schemeMemo != null) return _schemeMemo!;
    _schemeMemoKey = key;
    return _schemeMemo = AppTheme.schemeFromSeed(seed, brightness: brightness, variant: d.variant);
  }

  ColorScheme get scheme => schemeFor();

  /// Hay audio real sonando en la tableta (y el visualizador lo usa).
  bool get audioDetected => cfg.visualizer.wantsRealAudio && audio.detected.value;

  /// Las barras salen del audio real (si no, del espectro simulado).
  bool get useRealAudio => switch (cfg.visualizer.source) {
    CarVizSource.real => true,
    CarVizSource.simulated => false,
    CarVizSource.auto => audio.detected.value,
  };

  /// Fuente activa de las barras ahora.
  CarVizNow get vizNow {
    final v = cfg.visualizer;
    if (v.source == CarVizSource.simulated) return CarVizNow.simulated;
    return audio.detected.value && audio.live ? CarVizNow.real : CarVizNow.realNoSignal;
  }

  /// ¿Animar el visualizador, el giro de la portada y las formas de fondo? Suena según el
  /// celular / la sesión local, o se detectó audio real, o "Animar siempre".
  bool get visualActive {
    final np = nowPlaying;
    if (np.track == null) return false;
    return np.playing || audioDetected || cfg.visualizer.animateAlways;
  }

  // ---- Reloj de espera y noche ----

  DateTime _lastActive = DateTime.now();
  bool _standby = false;
  bool _standbyForced = false;
  bool _dismissedDisconnected = false;
  bool _night = false;
  int _ticks = 0;
  DateTime Function() clock = DateTime.now;

  /// Lo último que sonó (para el reloj de espera).
  NowPlaying lastPlayed = const NowPlaying();

  /// Se muestra el reloj de espera.
  bool get standby => _standby;

  /// Horario de noche ([CarNightOpts]).
  bool get night => _night;

  /// Atenuar la pantalla ahora (modo noche activo y dentro del horario).
  bool get nightDim => cfg.night.dim && _night;

  /// Muestra el reloj ya (web `?standby=1`, pruebas, botón "Probar").
  void showStandby() {
    _standbyForced = true;
    _checkStandby();
  }

  /// Tocar el reloj: vuelve al reproductor (y cuenta de nuevo los minutos).
  void wakeFromStandby() {
    _standbyForced = false;
    _lastActive = clock();
    if (cfg.standby.whenDisconnected && !link.status.value.isConnected) _dismissedDisconnected = true;
    _checkStandby();
  }

  /// ¿Corresponde el reloj de espera ahora?
  @visibleForTesting
  bool computeStandby(DateTime now) {
    if (_standbyForced) return true;
    final s = cfg.standby;
    if (nowPlaying.playing) return false;
    if (s.idleMinutes > 0 && now.difference(_lastActive) >= Duration(minutes: s.idleMinutes)) return true;
    return s.whenDisconnected &&
        !demo &&
        !_idleDemo &&
        !link.status.value.isConnected &&
        _local.track == null &&
        !_dismissedDisconnected;
  }

  void _checkStandby() {
    final now = clock();
    if (nowPlaying.playing) _lastActive = now;
    final night = cfg.night.isNight(now);
    final st = computeStandby(now);
    if (st != _standby || night != _night) {
      _standby = st;
      _night = night;
      _changed();
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _night = cfg.night.isNight(clock());
    link.status.addListener(_onLinkStatus);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    unawaited(_bridge.setKeepScreenOn(prefs.keepScreenOn));
    unawaited(_refreshIps());
    _ipTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (source == CarSource.none) _refreshIps();
    });
    if (_bridge.isSupported) {
      _nativeSub = _bridge.events.listen(_onNative, onError: (_) {});
      unawaited(_bridge.startLocalMediaWatch());
    }
    _msgSub ??= link.messages.listen(apply);
    // v3: la red del carro solo se manda con la sesión autenticada.
    _authSub ??= link.onAuthenticated.listen((_) {
      _sharedHotspot = null;
      unawaited(shareHotspot());
    });
    // Cosas del sistema que no deben esperar a la conexión.
    unawaited(syncVisualizer());
    _syncHotspot(initial: true);
    unawaited(launchCompanionOnStart());
    _syncKeepFront(initial: true);
    performance.start();
    unawaited(connectivity.start());
    updater.start();
    if (kIsWeb) {
      final q = Uri.base.queryParameters;
      if (q['conn'] == 'sample' || demo) connectivity.fillSample();
      if (q['update'] == 'sample') updater.fillSample();
      if (q['standby'] == '1') showStandby();
    } else if (cfg.updates.autoCheck && _bridge.isSupported) {
      unawaited(updater.autoCheckIfDue());
    }
    if (demo) {
      await _startDemo();
    } else if (cfg.connection.autoConnect) {
      await _startLink();
    }
    _syncIdleDemo();
  }

  // ---- Visualizador con el audio real ----

  /// Arranca o detiene el Visualizer nativo según el ajuste y si la app está al frente.
  /// La primera vez pide el permiso de audio.
  Future<void> syncVisualizer() => _vizOp = _vizOp.then((_) => _syncVisualizer()).catchError((Object e) {
    debugPrint('visualizer: $e');
  });

  Future<void> _syncVisualizer() async {
    if (_disposed) return;
    final want = _started && _foreground && cfg.visualizer.wantsRealAudio && _bridge.isSupported;
    if (want && !visualizerRunning) {
      if (!_audioAsked) {
        _audioAsked = true;
        audioPermission = await _bridge.requestAudioPermission();
        if (_disposed) return;
      }
      visualizerRunning = await _bridge.startVisualizer();
      // Si arrancó es porque hay permiso (p. ej. se dio desde los ajustes del sistema).
      if (visualizerRunning) audioPermission = true;
      _changed();
    } else if (!want && visualizerRunning) {
      visualizerRunning = false;
      await _bridge.stopVisualizer();
      audio.reset();
      _changed();
    }
  }

  /// Botón "Dar permiso" de Configuración.
  Future<bool> requestAudioPermission() async {
    audioPermission = await _bridge.requestAudioPermission();
    _audioAsked = true;
    _changed();
    if (audioPermission == true) await syncVisualizer();
    return audioPermission ?? false;
  }

  /// La app pasó a segundo plano / volvió al frente: el Visualizer solo corre al frente.
  void setForeground(bool fg) {
    if (fg == _foreground) return;
    _foreground = fg;
    if (_started) unawaited(syncVisualizer());
  }

  // ---- Hotspot ----

  void _syncHotspot({bool initial = false}) {
    if (!_started || _disposed) return;
    final h = cfg.hotspot;
    hotspot.schedule(h.autoEnable ? h.recheckMinutes : 0);
    if (h.autoEnable && (initial || !_lastHotspot.autoEnable)) {
      unawaited(hotspot.ensureOn());
    } else if (initial && _bridge.isSupported) {
      unawaited(hotspot.refresh());
    }
  }

  /// Red del carro que se manda al celular: la escrita en Configuración → Hotspot o, si
  /// no hay, la configurada en el radio (`configuredSsid`/`configuredPassword`).
  (String, String)? get hotspotNetwork {
    final h = cfg.hotspot;
    if (h.ssid.trim().isNotEmpty) return (h.ssid.trim(), h.password);
    final info = hotspot.info;
    final ssid = info.networkSsid;
    if (ssid == null || ssid.isEmpty) return null;
    return (ssid, info.networkPassword ?? '');
  }

  /// Al autenticar la sesión: le pasa la red del carro al celular (si el usuario lo permite)
  /// para que se una solo (`{"t":"hotspot"}`, CONTRACT.md §1 v2/v3). `true` si se envió.
  Future<bool> shareHotspot({bool force = false}) async {
    if (demo || !cfg.hotspot.shareWithPhone || !link.status.value.isLinked) return false;
    var net = hotspotNetwork;
    if (net == null && _bridge.isSupported) {
      await hotspot.refresh();
      net = hotspotNetwork;
    }
    if (net == null) return false;
    final key = '${net.$1}\u0000${net.$2}';
    if (!force && key == _sharedHotspot) return false;
    final ok = await link.send(LinkProtocol.hotspot(ssid: net.$1, password: net.$2));
    if (ok) {
      _sharedHotspot = key;
      link.diag.note('Red del carro «${net.$1}» enviada al celular');
    }
    return ok;
  }

  // ---- App acompañante ----

  /// Al arrancar (una vez): abre la app acompañante detrás.
  Future<void> launchCompanionOnStart() async {
    final s = cfg.startup;
    final pkg = s.companionToLaunch;
    if (companionLaunched || pkg.isEmpty || !_bridge.isSupported) return;
    companionLaunched = true;
    // Si nos abrió el receptor de arranque, la acompañante ya está abierta detrás.
    if (await _bridge.consumeBootLaunch()) return;
    await _bridge.launchApp(pkg, background: true, delayMs: s.companionDelayMs);
  }

  // ---- Siempre encima y burbuja ----

  void _syncKeepFront({bool initial = false}) {
    final k = cfg.keepFront;
    if (!initial && k == _lastKeepFront) return;
    final old = _lastKeepFront;
    _lastKeepFront = k;
    if (initial || '${k.nativeConfig()}' != '${old.nativeConfig()}') {
      unawaited(_bridge.setKeepInFront(k.nativeConfig(fallback: cfg.startup.companionPackage)));
    }
    if (initial || k.bubbleConfig().toString() != old.bubbleConfig().toString()) {
      unawaited(_bridge.setFloatingBubble(k.bubbleConfig()));
      _bubbleKey = null;
      _pushBubble();
    }
  }

  /// Vuelve a mandar la configuración de "Siempre encima" (tras dar un permiso).
  Future<void> resyncKeepFront() async {
    await _bridge.setKeepInFront(cfg.keepFront.nativeConfig(fallback: cfg.startup.companionPackage));
    await _bridge.setFloatingBubble(cfg.keepFront.bubbleConfig());
    _bubbleKey = null;
    _pushBubble();
  }

  Object? _bubbleKey;

  /// La burbuja muestra el tema actual: se actualiza al cambiar tema, carátula o play/pausa.
  void _pushBubble() {
    if (!cfg.keepFront.bubble || !_bridge.isSupported) return;
    final np = nowPlaying;
    final key = (np.track?.id, identityHashCode(np.artwork), np.playing);
    if (key == _bubbleKey) return;
    _bubbleKey = key;
    unawaited(
      _bridge.updateFloatingBubble(
        title: np.track?.title ?? 'Pixel Car Player',
        artist: np.track?.artist ?? '',
        art: np.artwork,
        playing: np.playing,
      ),
    );
  }

  // ---- Copia de seguridad ----

  /// Toda la configuración de la tableta.
  CarBackup backupNow() => CarBackup(
    customization: cfg,
    trustedPhones: trust.toJson(),
    requirePairing: trust.requirePairing,
    link: {
      'manualIp': ?prefs.manualIp,
      'btAddress': ?prefs.btAddress,
      'btName': ?prefs.btName,
      'keepScreenOn': prefs.keepScreenOn,
    },
  );

  /// Guarda la copia en Documentos/PixelCarPlayer/ (nativo). Devuelve la ruta o `null`.
  Future<String?> saveBackupToFile() => _bridge.saveBackupFile(backupNow().encode(), name: CarBackup.fileName());

  /// Aplica una copia (completa o solo personalización).
  Future<void> restoreBackup(CarBackup b) async {
    custom.set(b.customization);
    if (!b.isFull) return;
    trust.restore(b.trustedPhones, requirePairing: b.requirePairing);
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    prefs
      ..manualIp = str(b.link['manualIp'])
      ..btAddress = str(b.link['btAddress'])
      ..btName = str(b.link['btName'])
      ..keepScreenOn = b.link['keepScreenOn'] is bool ? b.link['keepScreenOn'] as bool : prefs.keepScreenOn;
    await prefs.save();
    await _bridge.setKeepScreenOn(prefs.keepScreenOn);
    _configureLink();
    _changed();
  }

  /// Olvida un celular de confianza (y corta su enlace si está conectado).
  void forgetPhone(String id) {
    trust.forget(id);
    link.dropPeer(id);
    _changed();
  }

  /// "Probar ahora".
  Future<bool> launchCompanionNow() {
    final s = cfg.startup;
    if (s.companionPackage.isEmpty) return Future.value(false);
    return _bridge.launchApp(s.companionPackage, background: true, delayMs: s.companionDelayMs);
  }

  Future<void> _startLink() async {
    _msgSub ??= link.messages.listen(apply);
    _linkStarted = true;
    await link.start();
  }

  /// Empieza a buscar al celular (con "Conexión automática" apagada, o para reintentar ya).
  Future<void> connectNow() async {
    if (demo) return;
    if (_linkStarted) {
      link.reconnect();
    } else {
      await _startLink();
    }
    _changed();
  }

  /// Corta la conexión y deja de buscar hasta [connectNow].
  Future<void> disconnect() async {
    _linkStarted = false;
    await link.stop();
    _changed();
  }

  void _onCustom() {
    final conn = cfg.connection;
    if (conn != _lastConnection) {
      final old = _lastConnection;
      _lastConnection = conn;
      if (old.transport != conn.transport || old.reconnectSeconds != conn.reconnectSeconds) _configureLink();
      if (conn.autoConnect && !old.autoConnect && !_linkStarted && !demo && _started) unawaited(_startLink());
      _syncIdleDemo();
    }
    final viz = cfg.visualizer;
    if (viz.source != _lastViz.source) {
      _lastViz = viz;
      if (!viz.wantsRealAudio) audio.reset();
      unawaited(syncVisualizer());
    }
    _lastViz = viz;
    audio.fastGain = viz.response == CarVizResponse.precise;
    final hs = cfg.hotspot;
    hotspot.allowTemporary = hs.allowTemporary;
    if (hs.ssid != _lastHotspot.ssid ||
        hs.password != _lastHotspot.password ||
        (hs.shareWithPhone && !_lastHotspot.shareWithPhone)) {
      unawaited(shareHotspot());
    }
    if (hs.autoEnable != _lastHotspot.autoEnable || hs.recheckMinutes != _lastHotspot.recheckMinutes) {
      _syncHotspot();
    }
    _lastHotspot = hs;
    performance.mode = cfg.anim.perf;
    _syncKeepFront();
    _checkStandby();
    _changed();
  }

  void _configureLink() {
    final t = cfg.connection.transport;
    link.configure(
      manualIp: t == CarTransport.bt ? null : prefs.manualIp,
      btAddress: t == CarTransport.wifi ? null : prefs.btAddress,
      btName: prefs.btName,
      useWifi: t != CarTransport.bt,
      maxBackoff: Duration(seconds: cfg.connection.reconnectSeconds),
    );
  }

  /// Arranca o para la demo de relleno según haya o no algo real que mostrar.
  void _syncIdleDemo() {
    if (_disposed || !_started) return;
    final want = cfg.connection.demoWhenIdle && !demo && !link.status.value.isConnected && _local.track == null;
    if (want == _idleDemo) return;
    _idleDemo = want;
    _remote = const NowPlaying();
    _queue = const [];
    unawaited(want ? _startDemo() : _stopDemo());
  }

  Future<void> _startDemo() async {
    _remote = const NowPlaying();
    final d = _demo = _demoFactory();
    _demoSub = d.messages.listen(apply);
    await d.start();
  }

  Future<void> _stopDemo() async {
    await _demoSub?.cancel();
    _demoSub = null;
    await _demo?.dispose();
    _demo = null;
  }

  /// Activa/desactiva el modo demo en caliente.
  Future<void> setDemo(bool on) async {
    if (on == demo) return;
    prefs.demo = on;
    unawaited(prefs.save());
    _remote = const NowPlaying();
    _queue = const [];
    if (_idleDemo) {
      _idleDemo = false;
      await _stopDemo();
    }
    if (on) {
      _linkStarted = false;
      await link.stop();
      await _startDemo();
    } else {
      await _stopDemo();
      if (cfg.connection.autoConnect) await _startLink();
      _syncIdleDemo();
    }
    _changed();
  }

  Future<void> setKeepScreenOn(bool on) async {
    prefs.keepScreenOn = on;
    await prefs.save();
    await _bridge.setKeepScreenOn(on);
    _changed();
  }

  /// Guarda la configuración de conexión y reconecta.
  Future<void> setConnection({String? manualIp, String? btAddress, String? btName}) async {
    prefs
      ..manualIp = manualIp
      ..btAddress = btAddress
      ..btName = btName;
    await prefs.save();
    _configureLink();
    _changed();
  }

  Future<void> _refreshIps() async {
    final ips = await _bridge.getLocalIps();
    if (!listEquals(ips, tabletIps)) {
      tabletIps = ips;
      _changed();
    }
  }

  void _onLinkStatus() {
    final st = link.status.value;
    if (!demo) {
      if (st.isConnected) {
        _remoteDevice = st.device;
        _dismissedDisconnected = false;
      } else if (!_idleDemo) {
        _remote = const NowPlaying();
        _queue = const [];
      }
    }
    _syncIdleDemo();
    _checkStandby();
    _changed();
  }

  // ---- Mensajes del enlace / demo ----

  /// Aplica un mensaje del celular (o de la demo) al estado remoto.
  void apply(LinkMessage m) {
    switch (m) {
      case HelloMessage(:final device, :final source):
        _remoteDevice = device;
        _remoteSource = source;
      case TrackMessage(:final track):
        final same = _remote.track?.id == track.id;
        _remote = same
            ? _remote.copyWith(track: track)
            : NowPlaying(
                track: track,
                playing: _remote.playing,
                position: Duration.zero,
                positionAt: DateTime.now(),
                speed: _remote.speed,
              );
      case ArtMessage(:final id, :final bytes):
        if (id != _remote.track?.id) return;
        _remote = _remote.copyWith(artwork: bytes);
      case final StateMessage st:
        _remote = _remote.copyWith(
          playing: st.playing,
          position: st.position,
          positionAt: DateTime.now(),
          speed: st.speed <= 0 ? 1.0 : st.speed,
          modes: PlayerModes(
            shuffle: st.shuffle,
            repeat: st.repeat,
            liked: st.liked,
            canLike: st.canLike,
            canShuffle: st.canShuffle,
            canRepeat: st.canRepeat,
          ),
        );
      case LyricsMessage(:final id, :final status, :final synced, :final lines):
        if (id != _remote.track?.id) return;
        _remote = _remote.copyWith(lyrics: lines, lyricsSynced: synced, lyricsStatus: status);
      case QueueMessage(:final items):
        if (listEquals(items, _queue)) return;
        _queue = List.unmodifiable(items);
      case PingMessage() ||
          BeaconMessage() ||
          CarBeaconMessage() ||
          UnknownMessage() ||
          AuthMessage() ||
          PairRequestMessage() ||
          PairMessage():
        return;
    }
    _changed();
  }

  // ---- Fuente local (MediaSession de la tableta) ----

  String? _localPackage;
  String? _lyricsRequestedFor;

  void _onNative(Map<String, dynamic> e) {
    if (e['type'] == 'fft') {
      // Sin reconstruir la UI: el disco lee los niveles en cada cuadro.
      if (cfg.visualizer.wantsRealAudio) audio.onEvent(e);
      return;
    }
    if (e['type'] != 'localMedia') return;
    final title = (e['title'] as String?) ?? '';
    if (title.isEmpty) {
      if (_local.track == null) return;
      _local = const NowPlaying();
      _syncIdleDemo();
      _changed();
      return;
    }
    final artist = (e['artist'] as String?) ?? '';
    final album = (e['album'] as String?) ?? '';
    final durMs = (e['durationMs'] as num?)?.toInt() ?? 0;
    _localPackage = e['package'] as String?;
    final id = 'local-${Object.hash(title, artist, album, durMs ~/ 1000).toUnsigned(32)}';
    final track = TrackInfo(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: Duration(milliseconds: durMs),
      source: _localPackage,
    );
    final art = e['art'];
    var artBytes = art is Uint8List ? art : (art is List<int> ? Uint8List.fromList(art) : null);
    final same = _local.track?.id == id;
    // El evento trae la carátula completa cada segundo: si no cambió, se
    // reutiliza la misma instancia (sin redecodificar ni re-extraer colores).
    if (same && sameBytes(artBytes, _local.artwork)) artBytes = _local.artwork;
    _local = (same ? _local : NowPlaying(lyricsStatus: LyricsStatus.loading)).copyWith(
      track: track,
      artwork: artBytes ?? (same ? _local.artwork : null),
      playing: e['playing'] == true,
      position: Duration(milliseconds: (e['positionMs'] as num?)?.toInt() ?? 0),
      positionAt: DateTime.now(),
    );
    if (!same) _fetchLocalLyrics(track);
    _syncIdleDemo();
    _changed();
  }

  /// Comparación barata: longitud + muestra de ~64 bytes repartidos.
  @visibleForTesting
  static bool sameBytes(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    final step = (a.length ~/ 64).clamp(1, a.length);
    for (var i = 0; i < a.length; i += step) {
      if (a[i] != b[i]) return false;
    }
    return a.isEmpty || a[a.length - 1] == b[b.length - 1];
  }

  Future<void> _fetchLocalLyrics(TrackInfo t) async {
    if (_lyricsRequestedFor == t.id) return;
    _lyricsRequestedFor = t.id;
    final client = _lrclib ??= LrcLibClient();
    final r = await client.fetch(title: t.title, artist: t.artist, album: t.album, duration: t.duration);
    if (_disposed || _local.track?.id != t.id) return;
    _local = _local.copyWith(lyrics: r.lines, lyricsSynced: r.synced, lyricsStatus: r.status);
    _changed();
  }

  // ---- Comandos ----

  Future<void> play() => _command(LinkAction.play);
  Future<void> pause() => _command(LinkAction.pause);
  Future<void> toggle() => _command(LinkAction.toggle);
  Future<void> next() => _command(LinkAction.next);
  Future<void> previous() => _command(LinkAction.previous);
  Future<void> seek(Duration to) => _command(LinkAction.seek, positionMs: to.inMilliseconds);

  /// Aleatorio (alternar), repetir (off → todo → uno) y me gusta (alternar). v3.
  Future<void> toggleShuffle() => _command(LinkAction.shuffle);
  Future<void> cycleRepeat() => _command(LinkAction.repeat);
  Future<void> toggleLike() => _command(LinkAction.like);

  /// Salta a un tema de "A continuación" (si el celular mandó su `id`).
  Future<void> skipToQueue(QueueItem item) async {
    final id = item.id;
    if (id == null) return;
    _lastActive = clock();
    await _command(LinkAction.skipToQueue, queueId: id);
  }

  Future<void> _command(LinkAction action, {int? positionMs, int? queueId}) async {
    _optimistic(action, positionMs);
    if (_standby) wakeFromStandby();
    switch (source) {
      case CarSource.demo:
        _demo?.command(action, positionMs: positionMs, queueId: queueId);
      case CarSource.phone:
        final ok = await link.sendCommand(action, positionMs: positionMs, queueId: queueId);
        if (!ok && action != LinkAction.skipToQueue) {
          await _bridge.localMediaCommand(action.name, positionMs: positionMs);
        }
      case CarSource.local || CarSource.none:
        await _bridge.localMediaCommand(action.name, positionMs: positionMs);
    }
  }

  /// Respuesta inmediata en la UI; el `state` real lo corrige luego.
  void _optimistic(LinkAction action, int? positionMs) {
    NowPlaying update(NowPlaying np) {
      final now = DateTime.now();
      return switch (action) {
        LinkAction.play => np.copyWith(playing: true, position: np.livePosition(now), positionAt: now),
        LinkAction.pause => np.copyWith(playing: false, position: np.livePosition(now), positionAt: now),
        LinkAction.toggle => np.copyWith(playing: !np.playing, position: np.livePosition(now), positionAt: now),
        LinkAction.seek => np.copyWith(
          position: Duration(milliseconds: positionMs ?? 0),
          positionAt: now,
        ),
        LinkAction.shuffle => np.copyWith(modes: np.modes.copyWith(shuffle: !(np.modes.shuffle ?? false))),
        LinkAction.repeat => np.copyWith(modes: np.modes.copyWith(repeat: (np.modes.repeat ?? RepeatMode.off).next)),
        LinkAction.like => np.copyWith(modes: np.modes.copyWith(liked: !(np.modes.liked ?? false))),
        _ => np,
      };
    }

    switch (source) {
      case CarSource.phone || CarSource.demo:
        _remote = update(_remote);
      case CarSource.local:
        _local = update(_local);
      case CarSource.none:
        return;
    }
    _changed();
  }

  // ---- Reloj ----

  void _tick() {
    final np = nowPlaying;
    final pos = np.livePosition();
    position.value = pos;
    lyricIndex.value = np.lyricIndexAt(pos + lyricLead);
    if (_started && ++_ticks % 4 == 0) _checkStandby();
  }

  void _changed() {
    if (_disposed) return;
    _tick();
    _updateSeed();
    final np = nowPlaying;
    if (np.track != null) lastPlayed = np;
    if (np.playing) _lastActive = clock();
    notifyListeners();
    _pushBubble();
  }

  /// Calcula (o toma de la caché por pista) la semilla de color de la carátula, como
  /// `seedFromImage` de Harmonix v2. El esquema sale de ahí con la variante elegida.
  void _updateSeed() {
    final np = nowPlaying;
    final art = np.artwork;
    if (identical(art, _seedFor)) return;
    _seedFor = art;
    if (art == null) {
      // Se conserva el color anterior hasta que llegue otra carátula,
      // salvo que ya no haya nada que mostrar.
      if (np.track == null) _artSeed = null;
      return;
    }
    final key = '${np.track?.id}#${art.length}';
    final cached = _seedCache.remove(key);
    if (cached != null) {
      _seedCache[key] = cached; // LRU: al final.
      _artSeed = cached;
      return;
    }
    _seedBuilder(art)
        .then((s) {
          if (_disposed) return;
          _seedCache[key] = s;
          while (_seedCache.length > _seedCacheSize) {
            _seedCache.remove(_seedCache.keys.first);
          }
          if (!identical(_seedFor, art)) return;
          _artSeed = s;
          notifyListeners();
        })
        .catchError((Object e) {
          debugPrint('seedFromArtwork: $e');
        });
  }

  @override
  void dispose() {
    _disposed = true;
    custom.removeListener(_onCustom);
    if (_ownsCustom) custom.dispose();
    audio.detected.removeListener(_changed);
    audio.dispose();
    hotspot.dispose();
    if (visualizerRunning) _bridge.stopVisualizer();
    _ticker?.cancel();
    _ipTimer?.cancel();
    _msgSub?.cancel();
    _authSub?.cancel();
    performance.removeListener(_changed);
    performance.dispose();
    connectivity.dispose();
    updater.dispose();
    _nativeSub?.cancel();
    link.status.removeListener(_onLinkStatus);
    _stopDemo();
    link.dispose();
    _lrclib?.close();
    if (_started) {
      _bridge.setKeepScreenOn(false);
      _bridge.stopLocalMediaWatch();
    }
    position.dispose();
    lyricIndex.dispose();
    super.dispose();
  }
}
