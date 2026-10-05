import 'dart:typed_data';

/// Línea de letra sincronizada (LRC). `time` = inicio de la línea.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;

  bool get isGap => text.trim().isEmpty;

  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(
        Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
        (j['text'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'ms': time.inMilliseconds, 'text': text};
}

enum LyricsStatus { none, loading, ok, notFound }

LyricsStatus lyricsStatusFromString(String? s) => switch (s) {
      'ok' => LyricsStatus.ok,
      'loading' => LyricsStatus.loading,
      'not_found' => LyricsStatus.notFound,
      _ => LyricsStatus.none,
    };

/// Metadatos de la pista actual (mensaje `track`).
class TrackInfo {
  const TrackInfo({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = Duration.zero,
    this.source,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? source;

  factory TrackInfo.fromJson(Map<String, dynamic> j) => TrackInfo(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        album: (j['album'] as String?) ?? '',
        duration: Duration(milliseconds: (j['durationMs'] as num?)?.toInt() ?? 0),
        source: j['source'] as String?,
      );

  Map<String, dynamic> toJson() => {
        't': 'track',
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration.inMilliseconds,
        if (source != null) 'source': source,
      };
}

/// Modo de repetición del reproductor del celular (`state.repeat`).
enum RepeatMode {
  off,
  all,
  one;

  static RepeatMode? parse(Object? v) => switch (v) {
    'off' => RepeatMode.off,
    'all' => RepeatMode.all,
    'one' => RepeatMode.one,
    _ => null,
  };

  /// El que sigue en el ciclo off → all → one.
  RepeatMode get next => RepeatMode.values[(index + 1) % RepeatMode.values.length];
}

/// Aleatorio / repetir / me gusta y qué se puede cambiar (v3, `state`). `null` = no se sabe
/// (celular viejo o sesión local).
class PlayerModes {
  const PlayerModes({this.shuffle, this.repeat, this.liked, this.canLike, this.canShuffle, this.canRepeat});
  final bool? shuffle;
  final RepeatMode? repeat;
  final bool? liked;
  final bool? canLike;
  final bool? canShuffle;
  final bool? canRepeat;

  static const unknown = PlayerModes();

  PlayerModes copyWith({bool? shuffle, RepeatMode? repeat, bool? liked}) => PlayerModes(
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        liked: liked ?? this.liked,
        canLike: canLike,
        canShuffle: canShuffle,
        canRepeat: canRepeat,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayerModes &&
      other.shuffle == shuffle &&
      other.repeat == repeat &&
      other.liked == liked &&
      other.canLike == canLike &&
      other.canShuffle == canShuffle &&
      other.canRepeat == canRepeat;

  @override
  int get hashCode => Object.hash(shuffle, repeat, liked, canLike, canShuffle, canRepeat);
}

/// Estado completo que muestra la pantalla del carro.
class NowPlaying {
  const NowPlaying({
    this.track,
    this.artwork,
    this.playing = false,
    this.position = Duration.zero,
    this.positionAt,
    this.speed = 1.0,
    this.lyrics = const [],
    this.lyricsSynced = false,
    this.lyricsStatus = LyricsStatus.none,
    this.modes = PlayerModes.unknown,
  });

  final TrackInfo? track;
  final Uint8List? artwork;
  final bool playing;

  /// Posición reportada y el instante local (reloj de este dispositivo) en que se recibió.
  final Duration position;
  final DateTime? positionAt;
  final double speed;

  final List<LyricLine> lyrics;
  final bool lyricsSynced;
  final LyricsStatus lyricsStatus;

  /// Aleatorio / repetir / me gusta (v3).
  final PlayerModes modes;

  /// Posición interpolada "ahora".
  Duration livePosition([DateTime? now]) {
    if (!playing || positionAt == null) return position;
    final elapsed = (now ?? DateTime.now()).difference(positionAt!);
    final p = position + elapsed * speed;
    final d = track?.duration ?? Duration.zero;
    if (d > Duration.zero && p > d) return d;
    return p;
  }

  /// Índice de la línea activa para [pos], -1 si aún no empieza / no sincronizada.
  int lyricIndexAt(Duration pos) {
    if (!lyricsSynced || lyrics.isEmpty) return -1;
    var lo = 0, hi = lyrics.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lyrics[mid].time <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  static const _unset = Object();

  NowPlaying copyWith({
    Object? track = _unset,
    Object? artwork = _unset,
    bool? playing,
    Duration? position,
    DateTime? positionAt,
    double? speed,
    List<LyricLine>? lyrics,
    bool? lyricsSynced,
    LyricsStatus? lyricsStatus,
    PlayerModes? modes,
  }) =>
      NowPlaying(
        track: identical(track, _unset) ? this.track : track as TrackInfo?,
        artwork: identical(artwork, _unset) ? this.artwork : artwork as Uint8List?,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        positionAt: positionAt ?? this.positionAt,
        speed: speed ?? this.speed,
        lyrics: lyrics ?? this.lyrics,
        lyricsSynced: lyricsSynced ?? this.lyricsSynced,
        lyricsStatus: lyricsStatus ?? this.lyricsStatus,
        modes: modes ?? this.modes,
      );
}
