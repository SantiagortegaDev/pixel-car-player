import 'dart:convert';
import 'dart:typed_data';

import 'package:pixel_car_player/core/models/now_playing.dart';

/// Protocolo de enlace celular ⇄ tableta (docs/CONTRACT.md §1).
///
/// Una línea JSON UTF-8 por mensaje, terminada en `\n`, campo `t` = tipo.
class LinkProtocol {
  LinkProtocol._();

  static const int version = 1;
  static const int tcpPort = 47321;
  static const int beaconPort = 47322;

  /// v2: la tableta también escucha conexiones del celular en este puerto…
  static const int carTcpPort = 47323;

  /// …y avisa por UDP (`car_beacon`) a este puerto cada [carBeaconInterval].
  static const int carBeaconPort = 47324;
  static const Duration carBeaconInterval = Duration(seconds: 2);
  static const String rfcommUuid = '7c1e3a52-5b8e-4f0a-9d3c-2f6b8a4e91d7';

  /// Codifica un mensaje como línea (incluye `\n` final).
  static String encodeLine(Map<String, dynamic> msg) => '${jsonEncode(msg)}\n';

  /// Decodifica una línea (con o sin `\n`). Devuelve `null` si no es JSON
  /// válido o no tiene campo `t`.
  static LinkMessage? decodeLine(String line) {
    final s = line.trim();
    if (s.isEmpty) return null;
    try {
      final raw = jsonDecode(s);
      if (raw is! Map) return null;
      return LinkMessage.fromJson(Map<String, dynamic>.from(raw));
    } on FormatException {
      return null;
    }
  }

  // ---- Tableta → celular ----
  /// `hello` de la tableta; [id] = identificador estable de esta instalación (v2).
  static Map<String, dynamic> hello(String device, {String? id}) => {
    't': 'hello',
    'v': version,
    'device': device,
    if (id != null && id.isNotEmpty) 'id': id,
  };

  /// Beacon UDP de la tableta (v2, puerto [carBeaconPort]).
  static Map<String, dynamic> carBeacon({required String device, required String id, int port = carTcpPort}) => {
    't': 'car_beacon',
    'v': 2,
    'device': device,
    'id': id,
    'port': port,
  };

  /// Tableta → celular: la red del carro, para que el celular se una solo.
  static Map<String, dynamic> hotspot({required String ssid, required String password}) => {
    't': 'hotspot',
    'ssid': ssid,
    'password': password,
  };
  static Map<String, dynamic> pong() => {'t': 'pong'};
  static Map<String, dynamic> resync() => {'t': 'resync'};

  /// Celular → tableta: próximos temas de la cola (hasta [maxQueue]).
  static Map<String, dynamic> queue(List<QueueItem> items) => {
    't': 'queue',
    'items': [for (final i in items.take(maxQueue)) i.toJson()],
  };

  /// Máximo de temas de `queue` que se envían / aceptan.
  static const int maxQueue = 20;

  static Map<String, dynamic> cmd(LinkAction action, {int? positionMs}) => {
    't': 'cmd',
    'action': action.name,
    if (action == LinkAction.seek) 'positionMs': positionMs ?? 0,
  };
}

/// Acciones de `cmd` (también usadas por `localMediaCommand`).
enum LinkAction { play, pause, toggle, next, previous, seek }

/// Acumula fragmentos de texto y devuelve líneas completas.
/// Tolera `\r\n`, fragmentos parciales y varias líneas por fragmento.
class LineBuffer {
  LineBuffer({this.maxLength = 8 * 1024 * 1024});

  /// Límite de seguridad para una línea sin terminar (carátulas b64 ≈ 100 KB).
  final int maxLength;
  final StringBuffer _pending = StringBuffer();

  /// Agrega [chunk] y devuelve las líneas completas (sin `\n`, sin vacías).
  List<String> add(String chunk) {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk.codeUnitAt(i) == 0x0A) {
        _pending.write(chunk.substring(start, i));
        var line = _pending.toString();
        _pending.clear();
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        if (line.trim().isNotEmpty) out.add(line);
        start = i + 1;
      }
    }
    if (start < chunk.length) _pending.write(chunk.substring(start));
    if (_pending.length > maxLength) _pending.clear();
    return out;
  }

  /// Texto pendiente (sin terminar).
  String get pending => _pending.toString();

  void clear() => _pending.clear();
}

/// Decodificador UTF-8 por bytes + [LineBuffer] (maneja caracteres multibyte
/// partidos entre paquetes TCP).
class ByteLineDecoder {
  ByteLineDecoder() {
    _sink = const Utf8Decoder(allowMalformed: true).startChunkedConversion(_StringCollector(_collected));
  }

  final List<String> _collected = [];
  final LineBuffer _lines = LineBuffer();
  late final ByteConversionSink _sink;

  List<String> add(List<int> bytes) {
    _sink.add(bytes);
    if (_collected.isEmpty) return const [];
    final text = _collected.join();
    _collected.clear();
    return _lines.add(text);
  }
}

class _StringCollector implements Sink<String> {
  _StringCollector(this.target);
  final List<String> target;
  @override
  void add(String data) => target.add(data);
  @override
  void close() {}
}

/// Mensaje recibido del celular (o del beacon UDP).
sealed class LinkMessage {
  const LinkMessage();

  factory LinkMessage.fromJson(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'hello':
        final id = j['id'];
        return HelloMessage(
          device: (j['device'] as String?) ?? 'Celular',
          source: j['source'] as String?,
          version: (j['v'] as num?)?.toInt() ?? 1,
          id: id is String && id.isNotEmpty ? id : null,
        );
      case 'track':
        return TrackMessage(TrackInfo.fromJson(j));
      case 'art':
        Uint8List? bytes;
        try {
          final b64 = j['b64'] as String?;
          if (b64 != null && b64.isNotEmpty) bytes = base64Decode(b64);
        } on FormatException {
          bytes = null;
        }
        return ArtMessage(id: (j['id'] as String?) ?? '', mime: (j['mime'] as String?) ?? 'image/jpeg', bytes: bytes);
      case 'state':
        return StateMessage(
          playing: j['playing'] == true,
          position: Duration(milliseconds: (j['positionMs'] as num?)?.toInt() ?? 0),
          speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
        );
      case 'lyrics':
        final lines =
            (j['lines'] as List?)
                ?.whereType<Map>()
                .map((e) => LyricLine.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const <LyricLine>[];
        return LyricsMessage(
          id: (j['id'] as String?) ?? '',
          status: lyricsStatusFromString(j['status'] as String?),
          synced: j['synced'] == true,
          lines: lines,
        );
      case 'queue':
        final items =
            (j['items'] as List?)
                ?.whereType<Map>()
                .map((e) => QueueItem.fromJson(Map<String, dynamic>.from(e)))
                .where((e) => e.title.isNotEmpty)
                .take(LinkProtocol.maxQueue)
                .toList() ??
            const <QueueItem>[];
        return QueueMessage(items);
      case 'ping':
        return const PingMessage();
      case 'beacon':
        return BeaconMessage(
          device: (j['device'] as String?) ?? 'Celular',
          port: (j['port'] as num?)?.toInt() ?? LinkProtocol.tcpPort,
          id: j['id'] is String ? j['id'] as String : null,
        );
      case 'car_beacon':
        return CarBeaconMessage(
          device: (j['device'] as String?) ?? 'Tableta',
          id: (j['id'] as String?) ?? '',
          port: (j['port'] as num?)?.toInt() ?? LinkProtocol.carTcpPort,
        );
      default:
        return UnknownMessage(j['t']?.toString());
    }
  }
}

class HelloMessage extends LinkMessage {
  const HelloMessage({required this.device, this.source, this.version = 1, this.id});
  final String device;
  final String? source;
  final int version;

  /// Identificador estable de la instalación del celular (v2; `null` en v1).
  final String? id;
}

class TrackMessage extends LinkMessage {
  const TrackMessage(this.track);
  final TrackInfo track;
}

class ArtMessage extends LinkMessage {
  const ArtMessage({required this.id, this.mime = 'image/jpeg', this.bytes});
  final String id;
  final String mime;
  final Uint8List? bytes;
}

class StateMessage extends LinkMessage {
  const StateMessage({required this.playing, required this.position, this.speed = 1.0});
  final bool playing;
  final Duration position;
  final double speed;
}

class LyricsMessage extends LinkMessage {
  const LyricsMessage({required this.id, required this.status, this.synced = false, this.lines = const []});
  final String id;
  final LyricsStatus status;
  final bool synced;
  final List<LyricLine> lines;
}

/// Tema de la cola (`queue`): solo título y artista.
class QueueItem {
  const QueueItem({required this.title, this.artist = ''});
  final String title;
  final String artist;

  factory QueueItem.fromJson(Map<String, dynamic> j) =>
      QueueItem(title: (j['title'] as String?) ?? '', artist: (j['artist'] as String?) ?? '');

  Map<String, dynamic> toJson() => {'title': title, 'artist': artist};

  @override
  bool operator ==(Object other) => other is QueueItem && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// Próximos temas (puede no llegar nunca: la lista vacía es válida).
class QueueMessage extends LinkMessage {
  const QueueMessage(this.items);
  final List<QueueItem> items;
}

class PingMessage extends LinkMessage {
  const PingMessage();
}

class BeaconMessage extends LinkMessage {
  const BeaconMessage({required this.device, required this.port, this.id});
  final String device;
  final int port;
  final String? id;
}

/// Beacon de una tableta (v2). La tableta no los usa; sirve para pruebas y diagnóstico.
class CarBeaconMessage extends LinkMessage {
  const CarBeaconMessage({required this.device, required this.id, required this.port});
  final String device;
  final String id;
  final int port;
}

class UnknownMessage extends LinkMessage {
  const UnknownMessage(this.type);
  final String? type;
}
