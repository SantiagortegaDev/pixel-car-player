import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/data/link/link_diagnostics.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// Pista de demostración (canciones inventadas, letras originales).
class DemoTrack {
  const DemoTrack({
    required this.info,
    required this.coverAsset,
    this.lyrics = const [],
    this.synced = true,
    this.lyricsStatus = LyricsStatus.ok,
  });
  final TrackInfo info;
  final String coverAsset;
  final List<LyricLine> lyrics;
  final bool synced;
  final LyricsStatus lyricsStatus;
}

List<LyricLine> _lrc(List<(int, String)> raw) => [for (final (s, t) in raw) LyricLine(Duration(milliseconds: s), t)];

/// "Luces de Neón" — Harmonix Band (letra original para la demo).
final _neonLyrics = _lrc([
  (0, ''),
  (11200, 'Se enciende la ciudad cuando cae el sol'),
  (16800, 'y el asfalto brilla como un corazón'),
  (22300, 'tengo el tanque lleno y nada que perder'),
  (27900, 'solo esta carretera y el amanecer'),
  (33400, ''),
  (35600, 'Luces de neón sobre el retrovisor'),
  (41100, 'cada semáforo late a nuestro favor'),
  (46700, 'sube el volumen, deja la ventana abierta'),
  (52200, 'que la noche es larga y la ruta es nuestra'),
  (57800, ''),
  (60300, 'Kilómetros de estrellas en el parabrisas'),
  (65800, 'tu risa en el asiento, la radio sin prisas'),
  (71400, 'las calles se deshacen en color violeta'),
  (76900, 'y el mapa dice "sigue", no hay una meta'),
  (82500, ''),
  (84800, 'Luces de neón sobre el retrovisor'),
  (90300, 'cada semáforo late a nuestro favor'),
  (95900, 'sube el volumen, deja la ventana abierta'),
  (101400, 'que la noche es larga y la ruta es nuestra'),
  (107000, ''),
  (118500, 'Si el mundo se apaga, nosotros no'),
  (124000, 'tenemos la música y un motor'),
  (129600, 'brillamos de lejos, como una señal'),
  (135100, 'que nadie en la ciudad puede apagar'),
  (140700, ''),
  (143000, 'Oh-oh, luces de neón'),
  (148500, 'oh-oh, en el corazón'),
  (154100, 'oh-oh, luces de neón'),
  (159600, 'manejando hasta que salga el sol'),
  (165200, ''),
  (176800, 'Luces de neón sobre el retrovisor'),
  (182300, 'cada semáforo late a nuestro favor'),
  (187900, 'sube el volumen, deja la ventana abierta'),
  (193400, 'que la noche es larga y la ruta es nuestra'),
  (199000, ''),
  (204500, 'Y cuando amanezca, seguiremos aquí'),
  (210000, 'con las luces de neón dentro de ti'),
  (216000, ''),
]);

/// "Kilómetro Cero" — Los Satélites del Sur (letra original).
final _roadLyrics = _lrc([
  (0, ''),
  (8400, 'Dejé las llaves sobre la mesa'),
  (13100, 'y una nota que nadie leerá'),
  (17900, 'la carretera es una promesa'),
  (22600, 'que no pregunta de dónde vendrás'),
  (27400, ''),
  (29200, 'Kilómetro cero, todo empieza aquí'),
  (34000, 'el sol de frente y el viento a mi favor'),
  (38800, 'kilómetro cero, nada que fingir'),
  (43600, 'solo montañas y una canción'),
  (48400, ''),
  (56000, 'Pasan los pueblos como postales'),
  (60800, 'nombres que nunca sabré pronunciar'),
  (65600, 'el cielo cambia de azul a naranja'),
  (70400, 'y yo aprendo otra vez a respirar'),
  (75200, ''),
  (77000, 'Kilómetro cero, todo empieza aquí'),
  (81800, 'el sol de frente y el viento a mi favor'),
  (86600, 'kilómetro cero, nada que fingir'),
  (91400, 'solo montañas y una canción'),
  (96200, ''),
  (108000, 'No miro atrás, el espejo está vacío'),
  (112800, 'lo que fui se quedó en la estación'),
  (117600, 'tengo un camino largo como un río'),
  (122400, 'y un horizonte en cada curva'),
  (127200, ''),
  (129000, 'Kilómetro cero, kilómetro cero'),
  (133800, 'todo lo que quiero cabe en este carro'),
  (138600, 'kilómetro cero, sigo el sendero'),
  (143400, 'hasta que el mar me diga "ya llegaste"'),
  (148200, ''),
]);

final demoTracks = <DemoTrack>[
  DemoTrack(
    info: const TrackInfo(
      id: 'demo-neon',
      title: 'Luces de Neón',
      artist: 'Harmonix Band',
      album: 'Ruta Nocturna',
      duration: Duration(minutes: 3, seconds: 42),
      source: 'com.spotify.music',
    ),
    coverAsset: 'assets/demo/cover_neon.png',
    lyrics: _neonLyrics,
  ),
  DemoTrack(
    info: const TrackInfo(
      id: 'demo-road',
      title: 'Kilómetro Cero',
      artist: 'Los Satélites del Sur',
      album: 'Carretera Abierta',
      duration: Duration(minutes: 2, seconds: 38),
      source: 'com.spotify.music',
    ),
    coverAsset: 'assets/demo/cover_road.png',
    lyrics: _roadLyrics,
  ),
  const DemoTrack(
    info: TrackInfo(
      id: 'demo-sea',
      title: 'Mar de Fondo',
      artist: 'Bruma',
      album: 'Costa',
      duration: Duration(minutes: 3, seconds: 5),
      source: 'com.spotify.music',
    ),
    coverAsset: 'assets/demo/cover_sea.png',
    lyricsStatus: LyricsStatus.notFound,
    synced: false,
  ),
];

/// Temas inventados que completan la cola de la demo (después de los de [demoTracks]).
const demoQueueExtras = <QueueItem>[
  QueueItem(title: 'Autopista del Sol', artist: 'Harmonix Band'),
  QueueItem(title: 'Faros en la Niebla', artist: 'Bruma'),
  QueueItem(title: 'Ventanas Abiertas', artist: 'Los Satélites del Sur'),
  QueueItem(title: 'Medianoche en la Ruta 9', artist: 'Aurora Costera'),
];

/// Portada local de un tema de la demo (para la lista "A continuación").
String? demoCoverFor(String title) {
  for (final t in demoTracks) {
    if (t.info.title == title) return t.coverAsset;
  }
  return null;
}

/// Simula un celular transmitiendo: emite los mismos [LinkMessage] que el
/// enlace real y acepta los mismos comandos.
///
/// En web acepta `?track=N` (1..3), `?t=SEG` y `?paused=1` para fijar el punto
/// de partida (útil para capturas).
class DemoSource {
  DemoSource({int startTrack = 0, Duration startAt = Duration.zero, bool paused = false})
    : _index = startTrack.clamp(0, demoTracks.length - 1),
      _offset = startAt,
      _playing = !paused;

  factory DemoSource.fromUrl() {
    if (!kIsWeb) return DemoSource(startAt: Duration.zero);
    final q = Uri.base.queryParameters;
    final tr = (int.tryParse(q['track'] ?? '') ?? 1) - 1;
    final t = int.tryParse(q['t'] ?? '') ?? 38;
    return DemoSource(
      startTrack: tr,
      startAt: Duration(seconds: t),
      paused: q['paused'] == '1',
    );
  }

  final _out = StreamController<LinkMessage>.broadcast();
  Stream<LinkMessage> get messages => _out.stream;

  int _index;
  Duration _offset; // posición en el instante _since
  DateTime _since = DateTime.now();
  bool _playing;
  Timer? _timer;
  final Map<String, Uint8List> _artCache = {};

  // v3: aleatorio / repetir / me gusta.
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  final Set<String> _liked = {'demo-road'};

  bool get shuffle => _shuffle;
  RepeatMode get repeat => _repeat;

  DemoTrack get current => demoTracks[_index];

  Duration get position {
    if (!_playing) return _offset;
    return _offset + DateTime.now().difference(_since);
  }

  Future<void> start() async {
    _out.add(const HelloMessage(device: 'Pixel 8 (demo)', source: 'com.spotify.music'));
    await _emitTrack();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  int _sinceState = 0;
  void _tick() {
    if (_playing && position >= current.info.duration) {
      if (_repeat == RepeatMode.one) {
        _offset = Duration.zero;
        _since = DateTime.now();
        _emitState();
      } else {
        _go(1);
      }
      return;
    }
    // Como el celular real: `state` cada 5 s mientras suena.
    if (_playing && ++_sinceState >= 10) _emitState();
  }

  void _emitState() {
    _sinceState = 0;
    if (_out.isClosed) return;
    _out.add(
      StateMessage(
        playing: _playing,
        position: position,
        shuffle: _shuffle,
        repeat: _repeat,
        liked: _liked.contains(current.info.id),
        canLike: true,
        canShuffle: true,
        canRepeat: true,
      ),
    );
  }

  /// Cola con `id` (v3) y miniaturas de las carátulas ya cargadas.
  List<QueueItem> _queueItems() {
    final n = demoTracks.length;
    return [
      for (var k = 1; k < n; k++)
        QueueItem(
          title: demoTracks[(_index + k) % n].info.title,
          artist: demoTracks[(_index + k) % n].info.artist,
          id: (_index + k) % n,
          art: _artCache[demoTracks[(_index + k) % n].coverAsset],
        ),
      for (final (i, e) in demoQueueExtras.indexed)
        QueueItem(title: e.title, artist: e.artist, id: 100 + i, art: _artCache[demoTracks[(i + 1) % n].coverAsset]),
    ];
  }

  Future<void> _loadCovers() async {
    var any = false;
    for (final t in demoTracks) {
      if (_artCache.containsKey(t.coverAsset)) continue;
      try {
        _artCache[t.coverAsset] = (await rootBundle.load(t.coverAsset)).buffer.asUint8List();
        any = true;
      } catch (_) {}
    }
    if (any && !_out.isClosed) _out.add(QueueMessage(_queueItems()));
  }

  Future<void> _emitTrack() async {
    final t = current;
    _out.add(TrackMessage(t.info));
    _emitState();
    _out.add(LyricsMessage(id: t.info.id, status: LyricsStatus.loading));
    _out.add(QueueMessage(_queueItems()));
    unawaited(_loadCovers());
    try {
      final bytes = _artCache[t.coverAsset] ??= (await rootBundle.load(t.coverAsset)).buffer.asUint8List();
      if (current.info.id == t.info.id) {
        _out.add(ArtMessage(id: t.info.id, mime: 'image/png', bytes: bytes));
      }
    } catch (e) {
      debugPrint('DemoSource: sin carátula ${t.coverAsset}: $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (current.info.id != t.info.id || _out.isClosed) return;
    _out.add(LyricsMessage(id: t.info.id, status: t.lyricsStatus, synced: t.synced, lines: t.lyrics));
  }

  void _go(int delta) {
    _index = (_index + delta) % demoTracks.length;
    if (_index < 0) _index += demoTracks.length;
    _offset = Duration.zero;
    _since = DateTime.now();
    _emitTrack();
  }

  void command(LinkAction action, {int? positionMs, int? queueId}) {
    switch (action) {
      case LinkAction.shuffle:
        _shuffle = !_shuffle;
        _emitState();
      case LinkAction.repeat:
        _repeat = _repeat.next;
        _emitState();
      case LinkAction.like:
        final id = current.info.id;
        if (!_liked.remove(id)) _liked.add(id);
        _emitState();
      case LinkAction.skipToQueue:
        final q = queueId ?? -1;
        final target = q >= 100 ? (q - 100 + 1) % demoTracks.length : q;
        if (target < 0 || target >= demoTracks.length) return;
        _go(target - _index);
      case LinkAction.play:
        _setPlaying(true);
      case LinkAction.pause:
        _setPlaying(false);
      case LinkAction.toggle:
        _setPlaying(!_playing);
      case LinkAction.next:
        _go(1);
      case LinkAction.previous:
        if (position > const Duration(seconds: 3)) {
          _offset = Duration.zero;
          _since = DateTime.now();
          _emitState();
        } else {
          _go(-1);
        }
      case LinkAction.seek:
        _offset = Duration(milliseconds: positionMs ?? 0);
        _since = DateTime.now();
        _emitState();
    }
  }

  void _setPlaying(bool p) {
    if (p == _playing) return;
    _offset = position;
    _since = DateTime.now();
    _playing = p;
    _emitState();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _out.close();
  }
}

/// Apps de ejemplo para el selector de "App acompañante" en la demo web (en la tableta
/// salen de `getLaunchableApps`).
const demoLaunchableApps = <Map<String, dynamic>>[
  {'package': 'com.syu.bt', 'label': 'Música Bluetooth'},
  {'package': 'com.android.fmradio', 'label': 'Radio FM'},
  {'package': 'com.google.android.apps.maps', 'label': 'Maps'},
  {'package': 'com.spotify.music', 'label': 'Spotify'},
  {'package': 'com.waze', 'label': 'Waze'},
  {'package': 'com.google.android.youtube', 'label': 'YouTube'},
  {'package': 'com.google.android.apps.youtube.music', 'label': 'YouTube Music'},
];

/// Diagnóstico de ejemplo (web `?diag=sample`): hotspot del carro encendido, el celular
/// avisa por Wi-Fi pero los intentos de la tableta fallan, y luego el celular marca.
void fillDemoDiagnostics(LinkDiagnostics d) {
  final now = DateTime.now();
  d
    ..setNetworks(const [
      LinkNetwork(iface: 'ap0', ip: '192.168.43.1', prefix: 24, isHotspot: true),
      LinkNetwork(iface: 'wlan0', ip: '10.0.0.23', prefix: 24, gateway: '10.0.0.1', isWifi: true),
    ])
    ..listeningPort = LinkProtocol.carTcpPort
    ..note('Escuchando conexiones del celular en el puerto ${LinkProtocol.carTcpPort}')
    ..heard('192.168.43.118', device: 'Pixel 8', port: LinkProtocol.tcpPort, id: '3f9c1a07b2d4e815');
  for (var i = 0; i < 4; i++) {
    d.sentBeacon();
  }
  for (final (s, target, err, ms) in [
    (14, '192.168.43.118:47321', 'sin respuesta (tiempo agotado)', 3002),
    (9, '192.168.43.118:47321', 'rechazada (no hay app escuchando)', 41),
    (4, '10.0.0.1:47321', 'rechazada (no hay app escuchando)', 18),
  ]) {
    d.attempt(
      LinkAttempt(at: now.subtract(Duration(seconds: s)), target: target, transport: 'wifi', ok: false, error: err, ms: ms),
    );
  }
  d.note('Cambiaron las redes: 10.0.0.23,192.168.43.1');
}
