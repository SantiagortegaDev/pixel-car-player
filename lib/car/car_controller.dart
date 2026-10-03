import 'dart:async';
import 'dart:ui' show Brightness, Color, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/lyrics/lrclib_client.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

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
  }) : _bridge = bridge ?? NativeBridge.instance,
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
        );
    _lastConnection = conn;
    this.custom.addListener(_onCustom);
  }

  final NativeBridge _bridge;
  final DemoSource Function() _demoFactory;
  final Future<Color> Function(Uint8List artwork) _seedBuilder;

  /// Personalización de la pantalla (se aplica en vivo).
  final CarCustomizationStore custom;
  final bool _ownsCustom;
  late CarConnectionOpts _lastConnection;

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
    if (link.status.value.isConnected) return CarSource.phone;
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
    };
    final key = (seed.toARGB32(), d.variant, brightness);
    if (key == _schemeMemoKey && _schemeMemo != null) return _schemeMemo!;
    _schemeMemoKey = key;
    return _schemeMemo = AppTheme.schemeFromSeed(seed, brightness: brightness, variant: d.variant);
  }

  ColorScheme get scheme => schemeFor();

  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_started) return;
    _started = true;
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
    if (demo) {
      await _startDemo();
    } else if (cfg.connection.autoConnect) {
      await _startLink();
    }
    _syncIdleDemo();
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
      } else if (!_idleDemo) {
        _remote = const NowPlaying();
        _queue = const [];
      }
    }
    _syncIdleDemo();
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
      case StateMessage(:final playing, position: final pos, :final speed):
        _remote = _remote.copyWith(
          playing: playing,
          position: pos,
          positionAt: DateTime.now(),
          speed: speed <= 0 ? 1.0 : speed,
        );
      case LyricsMessage(:final id, :final status, :final synced, :final lines):
        if (id != _remote.track?.id) return;
        _remote = _remote.copyWith(lyrics: lines, lyricsSynced: synced, lyricsStatus: status);
      case QueueMessage(:final items):
        if (listEquals(items, _queue)) return;
        _queue = List.unmodifiable(items);
      case PingMessage() || BeaconMessage() || UnknownMessage():
        return;
    }
    _changed();
  }

  // ---- Fuente local (MediaSession de la tableta) ----

  String? _localPackage;
  String? _lyricsRequestedFor;

  void _onNative(Map<String, dynamic> e) {
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

  Future<void> _command(LinkAction action, {int? positionMs}) async {
    _optimistic(action, positionMs);
    switch (source) {
      case CarSource.demo:
        _demo?.command(action, positionMs: positionMs);
      case CarSource.phone:
        final ok = await link.sendCommand(action, positionMs: positionMs);
        if (!ok) await _bridge.localMediaCommand(action.name, positionMs: positionMs);
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
  }

  void _changed() {
    if (_disposed) return;
    _tick();
    _updateSeed();
    notifyListeners();
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
    _ticker?.cancel();
    _ipTimer?.cancel();
    _msgSub?.cancel();
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
