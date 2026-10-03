import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme, MemoryImage;
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
    CarLinkClient? link,
    NativeBridge? bridge,
    LrcLibClient? lrclib,
    DemoSource Function()? demoFactory,
    Future<ColorScheme> Function(Uint8List artwork)? schemeBuilder,
  }) : _bridge = bridge ?? NativeBridge.instance,
       prefs = prefs ?? CarPrefs(demo: demo),
       _demoFactory = demoFactory ?? DemoSource.fromUrl,
       _schemeBuilder = schemeBuilder ?? schemeFromArtwork {
    _lrclib = lrclib;
    this.prefs.demo = demo || this.prefs.demo;
    this.link =
        link ??
        CarLinkClient(
          bridge: _bridge,
          manualIp: this.prefs.manualIp,
          btAddress: this.prefs.btAddress,
          btName: this.prefs.btName,
        );
  }

  final NativeBridge _bridge;
  final DemoSource Function() _demoFactory;
  final Future<ColorScheme> Function(Uint8List artwork) _schemeBuilder;

  /// Esquema Material You (oscuro) generado desde una carátula, igual que el
  /// reproductor multimedia de Android 12+.
  static Future<ColorScheme> schemeFromArtwork(Uint8List bytes) =>
      AppTheme.schemeFromImage(MemoryImage(bytes));

  /// Esquema cuando no hay carátula.
  static final ColorScheme fallbackScheme = AppTheme.schemeFromSeed(AppTheme.fallbackSeed);
  LrcLibClient? _lrclib;
  late final CarLinkClient link;
  CarPrefs prefs;

  /// Adelanto con el que se resalta la línea de letra (compensa latencia BT).
  static const lyricLead = Duration(milliseconds: 150);

  // ---- Estado ----
  NowPlaying _remote = const NowPlaying(); // celular o demo
  NowPlaying _local = const NowPlaying();
  String? _remoteDevice;
  String? _remoteSource;
  ColorScheme _scheme = fallbackScheme;
  Uint8List? _schemeFor;
  final Map<String, ColorScheme> _schemeCache = {};
  static const _schemeCacheSize = 24;
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

  bool get demo => prefs.demo;
  ValueListenable<LinkStatus> get linkStatus => link.status;

  /// Estado del enlace a mostrar (en demo se finge conectado).
  LinkStatus get displayStatus => demo
      ? LinkStatus.connected(
          device: _remoteDevice ?? 'Pixel 8 (demo)',
          transport: 'wifi',
          address: 'demo',
        )
      : link.status.value;

  CarSource get source {
    if (demo) return CarSource.demo;
    if (link.status.value.isConnected) return CarSource.phone;
    if (_local.track != null) return CarSource.local;
    return CarSource.none;
  }

  NowPlaying get nowPlaying => switch (source) {
    CarSource.phone || CarSource.demo => _remote,
    CarSource.local => _local,
    CarSource.none => const NowPlaying(),
  };

  /// Paquete de la app de música (`com.spotify.music`…).
  String? get sourcePackage =>
      source == CarSource.local ? _localPackage : (nowPlaying.track?.source ?? _remoteSource);

  /// Esquema de color actual (de la carátula que suena).
  ColorScheme get scheme => _scheme;

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
    if (demo) {
      await _startDemo();
    } else {
      await _startLink();
    }
  }

  Future<void> _startLink() async {
    _msgSub ??= link.messages.listen(apply);
    await link.start();
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
    if (on) {
      await link.stop();
      await _startDemo();
    } else {
      await _stopDemo();
      await _startLink();
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
    link.configure(manualIp: manualIp, btAddress: btAddress, btName: btName);
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
      } else {
        _remote = const NowPlaying();
      }
    }
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
      _local = const NowPlaying();
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
    final r = await client.fetch(
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
    );
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
        LinkAction.play => np.copyWith(
          playing: true,
          position: np.livePosition(now),
          positionAt: now,
        ),
        LinkAction.pause => np.copyWith(
          playing: false,
          position: np.livePosition(now),
          positionAt: now,
        ),
        LinkAction.toggle => np.copyWith(
          playing: !np.playing,
          position: np.livePosition(now),
          positionAt: now,
        ),
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
    _updateScheme();
    notifyListeners();
  }

  /// Calcula (o toma de la caché por pista) el esquema de la carátula.
  void _updateScheme() {
    final np = nowPlaying;
    final art = np.artwork;
    if (identical(art, _schemeFor)) return;
    _schemeFor = art;
    if (art == null) {
      // Se conserva el color anterior hasta que llegue otra carátula,
      // salvo que ya no haya nada que mostrar.
      if (np.track == null) _scheme = fallbackScheme;
      return;
    }
    final key = '${np.track?.id}#${art.length}';
    final cached = _schemeCache.remove(key);
    if (cached != null) {
      _schemeCache[key] = cached; // LRU: al final.
      _scheme = cached;
      return;
    }
    _schemeBuilder(art).then((s) {
      if (_disposed) return;
      _schemeCache[key] = s;
      while (_schemeCache.length > _schemeCacheSize) {
        _schemeCache.remove(_schemeCache.keys.first);
      }
      if (!identical(_schemeFor, art)) return;
      _scheme = s;
      notifyListeners();
    }).catchError((Object e) {
      debugPrint('schemeFromArtwork: $e');
    });
  }

  @override
  void dispose() {
    _disposed = true;
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
