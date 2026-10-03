import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pixel_car_player/core/models/now_playing.dart';

/// Resultado de buscar letras.
class LyricsResult {
  const LyricsResult(this.status, {this.synced = false, this.lines = const []});
  final LyricsStatus status;
  final bool synced;
  final List<LyricLine> lines;

  static const notFound = LyricsResult(LyricsStatus.notFound);
}

final _lrcTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Parser LRC: admite varias etiquetas por línea (`[00:12.30][01:05.00]texto`)
/// y descarta etiquetas de metadatos (`[ar:...]`).
List<LyricLine> parseLrc(String lrc) {
  final out = <LyricLine>[];
  for (final raw in const LineSplitter().convert(lrc)) {
    final matches = _lrcTag.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final text = raw.substring(matches.last.end).trim();
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracStr = m.group(3);
      var ms = 0;
      if (fracStr != null) {
        ms = switch (fracStr.length) {
          1 => int.parse(fracStr) * 100,
          2 => int.parse(fracStr) * 10,
          _ => int.parse(fracStr.substring(0, 3)),
        };
      }
      out.add(LyricLine(Duration(minutes: min, seconds: sec, milliseconds: ms), text));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Cliente mínimo de https://lrclib.net (usado solo cuando la fuente es la
/// sesión multimedia local de la tableta; el celular resuelve las suyas).
class LrcLibClient {
  LrcLibClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _host = 'lrclib.net';
  static const _headers = {'User-Agent': 'PixelCarPlayer/1.0 (https://github.com/santiagortegadev)'};

  Future<LyricsResult> fetch({
    required String title,
    required String artist,
    String album = '',
    Duration duration = Duration.zero,
  }) async {
    try {
      final get = await _client
          .get(
            Uri.https(_host, '/api/get', {
              'track_name': title,
              'artist_name': artist,
              if (album.isNotEmpty) 'album_name': album,
              if (duration > Duration.zero) 'duration': '${duration.inSeconds}',
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      if (get.statusCode == 200) {
        final r = _fromJson(jsonDecode(utf8.decode(get.bodyBytes)));
        if (r.status == LyricsStatus.ok) return r;
      }
      final search = await _client
          .get(Uri.https(_host, '/api/search', {'track_name': title, 'artist_name': artist}), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (search.statusCode == 200) {
        final list = jsonDecode(utf8.decode(search.bodyBytes));
        if (list is List) {
          LyricsResult? plain;
          for (final item in list) {
            final r = _fromJson(item);
            if (r.status == LyricsStatus.ok && r.synced) return r;
            if (r.status == LyricsStatus.ok) plain ??= r;
          }
          if (plain != null) return plain;
        }
      }
      return LyricsResult.notFound;
    } catch (_) {
      return LyricsResult.notFound;
    }
  }

  LyricsResult _fromJson(Object? j) {
    if (j is! Map) return LyricsResult.notFound;
    final synced = j['syncedLyrics'];
    if (synced is String && synced.trim().isNotEmpty) {
      final lines = parseLrc(synced);
      if (lines.isNotEmpty) {
        return LyricsResult(LyricsStatus.ok, synced: true, lines: lines);
      }
    }
    final plain = j['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) {
      return LyricsResult(
        LyricsStatus.ok,
        synced: false,
        lines: [for (final l in const LineSplitter().convert(plain)) LyricLine(Duration.zero, l)],
      );
    }
    return LyricsResult.notFound;
  }

  void close() => _client.close();
}
