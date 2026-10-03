import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/lyrics/lrclib_client.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

const _track = TrackInfo(
  id: 't1',
  title: 'Luces de Neón',
  artist: 'Harmonix Band',
  duration: Duration(minutes: 3, seconds: 42),
);

final _lines = [
  const LyricLine(Duration.zero, ''),
  const LyricLine(Duration(seconds: 10), 'uno'),
  const LyricLine(Duration(seconds: 20), 'dos'),
  const LyricLine(Duration(seconds: 30), 'tres'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('índice de letra', () {
    final np = NowPlaying(track: _track, lyrics: _lines, lyricsSynced: true);

    test('búsqueda binaria', () {
      expect(np.lyricIndexAt(Duration.zero), 0);
      expect(np.lyricIndexAt(const Duration(seconds: 9, milliseconds: 999)), 0);
      expect(np.lyricIndexAt(const Duration(seconds: 10)), 1);
      expect(np.lyricIndexAt(const Duration(seconds: 25)), 2);
      expect(np.lyricIndexAt(const Duration(minutes: 3)), 3);
    });

    test('antes de la primera línea y no sincronizadas', () {
      final late = NowPlaying(lyrics: [const LyricLine(Duration(seconds: 5), 'a')], lyricsSynced: true);
      expect(late.lyricIndexAt(const Duration(seconds: 1)), -1);
      expect(np.copyWith(lyricsSynced: false).lyricIndexAt(const Duration(seconds: 20)), -1);
    });
  });

  group('interpolación de posición', () {
    final at = DateTime(2026, 1, 1, 12);

    test('avanza con el reloj local mientras suena', () {
      final np = NowPlaying(
          track: _track, playing: true, position: const Duration(seconds: 30), positionAt: at);
      expect(np.livePosition(at.add(const Duration(milliseconds: 1500))),
          const Duration(seconds: 31, milliseconds: 500));
    });

    test('respeta la velocidad', () {
      final np = NowPlaying(
          track: _track, playing: true, position: Duration.zero, positionAt: at, speed: 2);
      expect(np.livePosition(at.add(const Duration(seconds: 3))), const Duration(seconds: 6));
    });

    test('pausado no avanza; no pasa de la duración', () {
      final paused = NowPlaying(
          track: _track, playing: false, position: const Duration(seconds: 30), positionAt: at);
      expect(paused.livePosition(at.add(const Duration(minutes: 1))), const Duration(seconds: 30));
      final end = NowPlaying(
          track: _track, playing: true, position: const Duration(minutes: 3, seconds: 40), positionAt: at);
      expect(end.livePosition(at.add(const Duration(minutes: 1))), _track.duration);
    });
  });

  group('LRC', () {
    test('parsea etiquetas múltiples y descarta metadatos', () {
      final l = parseLrc('[ar:Alguien]\n[00:12.30]Hola\n[01:05.5][00:01.000]Coro\n[00:20]');
      expect(l.map((e) => e.time.inMilliseconds), [1000, 12300, 20000, 65500]);
      expect(l.map((e) => e.text), ['Coro', 'Hola', '', 'Coro']);
    });
  });

  group('CarController.apply', () {
    late CarController c;
    setUp(() => c = CarController(demo: true));
    tearDown(() => c.dispose());

    test('ignora art/lyrics de otra pista y limpia al cambiar de pista', () {
      c.apply(const TrackMessage(_track));
      c.apply(ArtMessage(id: 'otra', bytes: Uint8List.fromList([1])));
      expect(c.nowPlaying.artwork, isNull);
      c.apply(LyricsMessage(id: 'otra', status: LyricsStatus.ok, synced: true, lines: _lines));
      expect(c.nowPlaying.lyrics, isEmpty);

      c.apply(ArtMessage(id: 't1', bytes: Uint8List.fromList([1, 2])));
      c.apply(LyricsMessage(id: 't1', status: LyricsStatus.ok, synced: true, lines: _lines));
      expect(c.nowPlaying.artwork, [1, 2]);
      expect(c.nowPlaying.lyrics.length, 4);

      // Mismo id: conserva carátula y letras.
      c.apply(const TrackMessage(_track));
      expect(c.nowPlaying.artwork, isNotNull);
      expect(c.nowPlaying.lyrics.length, 4);

      // Nueva pista: se limpian.
      c.apply(const TrackMessage(TrackInfo(id: 't2', title: 'Otra', artist: 'X')));
      expect(c.nowPlaying.artwork, isNull);
      expect(c.nowPlaying.lyrics, isEmpty);
    });

    test('state fija positionAt al reloj local', () {
      c.apply(const TrackMessage(_track));
      final before = DateTime.now();
      c.apply(const StateMessage(playing: true, position: Duration(seconds: 42)));
      final np = c.nowPlaying;
      expect(np.playing, isTrue);
      expect(np.position, const Duration(seconds: 42));
      expect(np.positionAt!.isBefore(before), isFalse);
    });

    test('sameBytes', () {
      final a = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final b = Uint8List.fromList(a);
      expect(CarController.sameBytes(a, b), isTrue);
      b[999] = 7;
      expect(CarController.sameBytes(a, b), isFalse);
      expect(CarController.sameBytes(null, a), isFalse);
    });
  });

  group('esquema Material You desde la carátula', () {
    final art1 = Uint8List.fromList([1, 2, 3]);
    final art2 = Uint8List.fromList([4, 5, 6, 7]);
    final red = AppTheme.schemeFromSeed(const Color(0xFFD02030));
    final green = AppTheme.schemeFromSeed(const Color(0xFF20B040));

    test('sin carátula usa el esquema semilla, oscuro', () {
      final c = CarController();
      expect(c.scheme, CarController.fallbackScheme);
      expect(c.scheme.brightness, Brightness.dark);
      c.dispose();
    });

    test('genera, aplica y cachea por pista', () async {
      var calls = 0;
      final c = CarController(
        demo: true,
        schemeBuilder: (b) async {
          calls++;
          return b.length == 3 ? red : green;
        },
      );
      c.apply(const TrackMessage(_track));
      c.apply(ArtMessage(id: 't1', mime: 'image/png', bytes: art1));
      await pumpEventQueue();
      expect(c.scheme, red);
      expect(calls, 1);

      const other = TrackInfo(id: 't2', title: 'Otra', artist: 'X');
      c.apply(const TrackMessage(other));
      c.apply(ArtMessage(id: 't2', mime: 'image/png', bytes: art2));
      await pumpEventQueue();
      expect(c.scheme, green);

      // Volver a la primera pista: sale de la caché, sin recalcular.
      c.apply(const TrackMessage(_track));
      c.apply(ArtMessage(id: 't1', mime: 'image/png', bytes: art1));
      expect(c.scheme, red);
      expect(calls, 2);
      c.dispose();
    });

    test('un error al generar conserva el esquema actual', () async {
      final c = CarController(demo: true, schemeBuilder: (_) async => throw StateError('x'));
      c.apply(const TrackMessage(_track));
      c.apply(ArtMessage(id: 't1', mime: 'image/png', bytes: art1));
      await pumpEventQueue();
      expect(c.scheme, CarController.fallbackScheme);
      c.dispose();
    });
  });
}
