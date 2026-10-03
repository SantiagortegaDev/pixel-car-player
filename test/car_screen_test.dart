import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';
import 'package:provider/provider.dart';

/// Renderiza la pantalla del carro en los tamaños objetivo y falla si hay
/// overflow o excepciones de layout.
void main() {
  const sizes = [Size(1024, 600), Size(1280, 720), Size(1920, 720), Size(2000, 1200)];

  Future<void> pumpScreen(WidgetTester tester, Size size, CarController c,
      {bool lyrics = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: HarmonixTheme.dark(),
      home: ChangeNotifierProvider<CarController>.value(
        value: c,
        child: CarPlayerScreen(onSettings: () {}, initialLyricsFullscreen: lyrics),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
  }

  void feed(CarController c, DemoTrack t) {
    c.apply(TrackMessage(t.info));
    c.apply(const StateMessage(playing: true, position: Duration(seconds: 45)));
    c.apply(LyricsMessage(
        id: t.info.id, status: t.lyricsStatus, synced: t.synced, lines: t.lyrics));
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('idle $label', (tester) async {
      final c = CarController();
      await pumpScreen(tester, size, c);
      expect(find.text('Esperando al celular…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    for (final (i, t) in demoTracks.indexed) {
      testWidgets('player $label pista ${i + 1}', (tester) async {
        final c = CarController(demo: true);
        feed(c, t);
        await pumpScreen(tester, size, c);
        expect(find.text(t.info.title), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    }

    testWidgets('letras pantalla completa $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks.first);
      await pumpScreen(tester, size, c, lyrics: true);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('letra sin sincronizar $label', (tester) async {
      final c = CarController(demo: true);
      final t = demoTracks.first;
      c.apply(TrackMessage(t.info));
      c.apply(LyricsMessage(
          id: t.info.id,
          status: LyricsStatus.ok,
          synced: false,
          lines: [for (final l in t.lyrics) LyricLine(Duration.zero, l.text)]));
      await pumpScreen(tester, size, c);
      expect(find.text('Letra sin sincronizar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
