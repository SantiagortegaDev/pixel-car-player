import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/color/artwork_palette.dart';
import 'package:pixel_car_player/car/lyrics/lrclib_client.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
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

  group('paleta', () {
    Uint8List solid(int r, int g, int b, {int n = 400}) {
      final out = Uint8List(n * 4);
      for (var i = 0; i < n; i++) {
        out.setAll(i * 4, [r, g, b, 255]);
      }
      return out;
    }

    test('imagen roja → acento rojo legible', () {
      final p = paletteFromRgba(solid(220, 30, 40));
      final h = HSLColor.fromColor(p.accent);
      expect(h.hue < 15 || h.hue > 345, isTrue);
      expect(h.lightness, greaterThan(0.5));
      expect(HSLColor.fromColor(p.accentBright).lightness, greaterThan(h.lightness));
    });

    test('imagen gris → acento Harmonix', () {
      final p = paletteFromRgba(solid(128, 128, 128));
      expect(p.accent, ArtworkPalette.harmonix.accent);
    });
  });
}
