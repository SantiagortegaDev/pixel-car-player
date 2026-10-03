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
  static Map<String, dynamic> hello(String device) => {
    't': 'hello',
    'v': version,
    'device': device,
  };
  static Map<String, dynamic> pong() => {'t': 'pong'};
  static Map<String, dynamic> resync() => {'t': 'resync'};
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
    _sink = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(_StringCollector(_collected));
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
        return HelloMessage(
          device: (j['device'] as String?) ?? 'Celular',
          source: j['source'] as String?,
          version: (j['v'] as num?)?.toInt() ?? 1,
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
        return ArtMessage(
          id: (j['id'] as String?) ?? '',
          mime: (j['mime'] as String?) ?? 'image/jpeg',
          bytes: bytes,
        );
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
      case 'ping':
        return const PingMessage();
      case 'beacon':
        return BeaconMessage(
          device: (j['device'] as String?) ?? 'Celular',
          port: (j['port'] as num?)?.toInt() ?? LinkProtocol.tcpPort,
        );
      default:
        return UnknownMessage(j['t']?.toString());
    }
  }
}

class HelloMessage extends LinkMessage {
  const HelloMessage({required this.device, this.source, this.version = 1});
  final String device;
  final String? source;
  final int version;
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
  const LyricsMessage({
    required this.id,
    required this.status,
    this.synced = false,
    this.lines = const [],
  });
  final String id;
  final LyricsStatus status;
  final bool synced;
  final List<LyricLine> lines;
}

class PingMessage extends LinkMessage {
  const PingMessage();
}

class BeaconMessage extends LinkMessage {
  const BeaconMessage({required this.device, required this.port});
  final String device;
  final int port;
}

class UnknownMessage extends LinkMessage {
  const UnknownMessage(this.type);
  final String? type;
}
