import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';
import 'package:provider/provider.dart';

/// Renderiza la pantalla del carro (vista "Reproduciendo" de Harmonix v2) en los tamaños
/// objetivo y falla si hay overflow o excepciones de layout.
void main() {
  const sizes = [Size(1024, 600), Size(1280, 720), Size(1920, 720), Size(2000, 1200)];

  Future<void> pumpScreen(
    WidgetTester tester,
    Size size,
    CarController c, {
    bool lyrics = false,
    void Function(BuildContext)? onSettings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ChangeNotifierProvider<CarController>.value(
          value: c,
          child: CarPlayerScreen(onSettings: onSettings ?? (_) {}, initialLyricsFullscreen: lyrics),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  void feed(CarController c, DemoTrack t, {bool queue = true}) {
    c.apply(TrackMessage(t.info));
    c.apply(const StateMessage(playing: true, position: Duration(seconds: 45)));
    c.apply(LyricsMessage(id: t.info.id, status: t.lyricsStatus, synced: t.synced, lines: t.lyrics));
    if (queue) c.apply(const QueueMessage(demoQueueExtras));
  }

  Future<void> finish(WidgetTester tester, CarController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('idle $label', (tester) async {
      final c = CarController();
      await pumpScreen(tester, size, c);
      expect(find.text('Esperando al celular…'), findsOneWidget);
      expect(find.text('Ajustes de conexión'), findsOneWidget);
      expect(find.text('Ver demo'), findsOneWidget);
      await finish(tester, c);
    });

    for (final (i, t) in demoTracks.indexed) {
      testWidgets('player $label pista ${i + 1}', (tester) async {
        final c = CarController(demo: true);
        feed(c, t);
        await pumpScreen(tester, size, c);
        expect(find.text(t.info.title), findsOneWidget);
        expect(find.text('Reproduciendo'), findsOneWidget);
        expect(find.text('Letra'), findsOneWidget);
        expect(find.text('A continuación'), findsOneWidget);
        expect(find.bySemanticsLabel('Pausar'), findsOneWidget);
        if (t.lyricsStatus == LyricsStatus.notFound) {
          expect(find.text('No hay letra para este tema.'), findsOneWidget);
        }
        await finish(tester, c);
      });
    }

    testWidgets('cola $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks.first);
      await pumpScreen(tester, size, c);
      await tester.tap(find.text('A continuación'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(demoQueueExtras.first.title), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('cola vacía $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks.first, queue: false);
      await pumpScreen(tester, size, c);
      await tester.tap(find.text('A continuación'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No hay más temas en la cola.'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('letras pantalla completa $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks.first);
      await pumpScreen(tester, size, c, lyrics: true);
      expect(find.text('Letra'), findsOneWidget); // encabezado
      expect(find.byTooltip('Volver al reproductor'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver al reproductor'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Reproduciendo'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('letra buscando y sin sincronizar $label', (tester) async {
      final c = CarController(demo: true);
      final t = demoTracks.first;
      c.apply(TrackMessage(t.info));
      c.apply(LyricsMessage(id: t.info.id, status: LyricsStatus.loading));
      await pumpScreen(tester, size, c);
      expect(find.bySemanticsLabel('Buscando la letra'), findsOneWidget);
      c.apply(
        LyricsMessage(
          id: t.info.id,
          status: LyricsStatus.ok,
          synced: false,
          lines: [for (final l in t.lyrics) LyricLine(Duration.zero, l.text)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Se enciende la ciudad'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('pausado $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks[1]);
      c.apply(const StateMessage(playing: false, position: Duration(seconds: 20)));
      await pumpScreen(tester, size, c);
      expect(find.bySemanticsLabel('Reproducir'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('ajustes $label', (tester) async {
      final c = CarController(demo: true);
      feed(c, demoTracks.first);
      await pumpScreen(
        tester,
        size,
        c,
        onSettings: (ctx) => showCarSettings(ctx, controller: c, onChangeMode: () {}),
      );
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ajustes'), findsWidgets);
      expect(find.text('Conexión automática'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      await tester.tap(find.text('Bluetooth'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Celular emparejado'), findsOneWidget);
      await tester.tap(find.text('Inicio'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Mantener pantalla encendida'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pump(const Duration(seconds: 1));
      await finish(tester, c);
    });
  }

  testWidgets('en pantallas grandes todo se agranda por igual', (tester) async {
    final c = CarController(demo: true);
    feed(c, demoTracks.first);
    await pumpScreen(tester, const Size(1280, 720), c);
    final small = tester.getRect(find.text('Reproduciendo')).height;
    await pumpScreen(tester, const Size(2000, 1200), c);
    final big = tester.getRect(find.text('Reproduciendo')).height;
    expect(big / small, closeTo(carScaleFor(const Size(2000, 1200)), 0.05));
    await finish(tester, c);
  });

  test('columnas del stage', () {
    for (final s in sizes) {
      final k = carScaleFor(s);
      final l = StageLayout.of(Size(s.width / k, s.height / k));
      expect(l.disc, greaterThanOrEqualTo(200), reason: '$s');
      expect(l.details, greaterThanOrEqualTo(280), reason: '$s');
      expect(l.side, greaterThanOrEqualTo(260), reason: '$s');
    }
    // 1280×720 = mismas columnas que Harmonix (460 | 341.6 | 280).
    final l = StageLayout.of(const Size(1280, 720));
    expect(l.disc, 460);
    expect(l.details, closeTo(341.6, 0.5));
    expect(l.side, closeTo(280, 0.5));
  });
}
