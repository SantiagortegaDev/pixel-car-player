import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/audio/car_audio_levels.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/car/widgets/lyrics.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// Animación de la letra al pasar de línea, respuesta del visualizador y campos nuevos.
void main() {
  group('modelo', () {
    test('valores por defecto de los campos nuevos', () {
      const d = CarCustomization.defaults;
      expect(d.lyrics.anim, CarLyricAnim.slide);
      expect(d.lyrics.animMs, 350);
      expect(d.lyrics.animCurve, CarLyricCurve.emphasized);
      expect(d.lyrics.animFullscreen, isTrue);
      expect(d.lyrics.scrollMs, 600);
      expect(d.lyrics.inactiveOpacity, 1.0);
      expect(d.visualizer.response, CarVizResponse.normal);
      expect(d.hotspot.shareWithPhone, isTrue);
      expect(d.hotspot.allowTemporary, isFalse);
    });

    test('JSON viejo (sin los campos) toma los valores por defecto', () {
      final old = CarCustomization.fromJson({
        'lyrics': {'scale': 1.2, 'glow': false},
        'visualizer': {'bars': 40},
        'hotspot': {'ssid': 'Carro'},
      });
      expect(old.lyrics.scale, 1.2);
      expect(old.lyrics.anim, CarLyricAnim.slide);
      expect(old.lyrics.scrollMs, 600);
      expect(old.visualizer.response, CarVizResponse.normal);
      expect(old.hotspot.ssid, 'Carro');
      expect(old.hotspot.shareWithPhone, isTrue);
    });

    test('ida y vuelta y acotado', () {
      final c = const CarCustomization().copyWith(
        lyrics: const CarLyricsOpts(
          anim: CarLyricAnim.karaoke,
          animMs: 700,
          animCurve: CarLyricCurve.linear,
          animFullscreen: false,
          scrollMs: 900,
          inactiveOpacity: 0.4,
        ),
        visualizer: const CarVisualizerOpts(response: CarVizResponse.precise),
        hotspot: const CarHotspotOpts(shareWithPhone: false, allowTemporary: true),
      );
      final back = CarCustomization.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back, c);
      final wild = CarLyricsOpts.fromJson({'animMs': 5000, 'scrollMs': 1, 'inactiveOpacity': 0, 'anim': 'nope'});
      expect(wild.animMs, 800);
      expect(wild.scrollMs, 150);
      expect(wild.inactiveOpacity, 0.2);
      expect(wild.anim, CarLyricAnim.slide);
    });

    test('pantalla completa usa Suave si la animación no aplica ahí', () {
      const o = CarLyricsOpts(anim: CarLyricAnim.scale, animFullscreen: false);
      expect(o.animFor(), CarLyricAnim.scale);
      expect(o.animFor(fullscreen: true), CarLyricAnim.fade);
      expect(const CarLyricsOpts(anim: CarLyricAnim.none, animFullscreen: false).animFor(fullscreen: true),
          CarLyricAnim.none);
    });

    test('suavizado de cada respuesta', () {
      expect(CarVizResponse.normal.smoothing, (0.35, 0.12));
      expect(CarVizResponse.precise.smoothing, (0.8, 0.4));
      expect(CarVizResponse.smooth.smoothing.$1, lessThan(0.35));
    });
  });

  test('progreso karaoke entre esta línea y la siguiente', () {
    final lines = [
      const LyricLine(Duration(seconds: 10), 'a'),
      const LyricLine(Duration(seconds: 14), 'b'),
    ];
    expect(karaokeProgress(lines, 0, const Duration(seconds: 10)), 0);
    expect(karaokeProgress(lines, 0, const Duration(seconds: 12)), closeTo(0.5, 1e-9));
    expect(karaokeProgress(lines, 0, const Duration(seconds: 20)), 1);
    // Última línea: hasta el final del tema, máximo 6 s.
    expect(karaokeProgress(lines, 1, const Duration(seconds: 17), trackEnd: const Duration(seconds: 20)),
        closeTo(0.5, 1e-9));
    expect(karaokeProgress(lines, 1, const Duration(seconds: 17)), closeTo(0.5, 1e-9));
    expect(karaokeProgress(lines, -1, Duration.zero), 0);
  });

  group('audio real', () {
    test('fps y ganancia rápida', () {
      var now = DateTime(2026);
      final a = CarAudioLevels(clock: () => now);
      for (var i = 0; i < 20; i++) {
        a.onFrame(List.filled(64, 0.3), 0.2);
        now = now.add(const Duration(milliseconds: 50));
      }
      expect(a.fps, closeTo(20, 1));
      expect(a.gain, 1, reason: 'Normal: sin ganancia extra');
      a.fastGain = true;
      expect(a.gain, closeTo(3, 0.01), reason: 'pico 0,3 → 0,9/0,3');
      a.reset();
      expect(a.fps, 0);
      a.dispose();
    });

    test('vizNow: simulado / sin señal / real', () async {
      final store = CarCustomizationStore(
        const CarCustomization().copyWith(visualizer: const CarVisualizerOpts(source: CarVizSource.simulated)),
      );
      final c = CarController(custom: store);
      expect(c.vizNow, CarVizNow.simulated);
      store.update((v) => v.copyWith(visualizer: v.visualizer.copyWith(source: CarVizSource.auto)));
      expect(c.vizNow, CarVizNow.realNoSignal);
      c.audio.onFrame(List.filled(64, 0.5), 0.3);
      expect(c.vizNow, CarVizNow.real);
      store.update((v) => v.copyWith(visualizer: v.visualizer.copyWith(response: CarVizResponse.precise)));
      expect(c.audio.fastGain, isTrue);
      c.dispose();
      store.dispose();
    });
  });

  group('LyricLineView', () {
    Future<void> pump(WidgetTester t, {required bool active, required CarLyricAnim anim, Duration? d}) =>
        t.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: LyricLineView(
                key: const ValueKey('l'),
                text: 'Luces de neón sobre el retrovisor',
                active: active,
                style: const TextStyle(fontSize: 24),
                anim: anim,
                duration: d ?? const Duration(milliseconds: 400),
              ),
            ),
          ),
        );

    LyricLineViewState state(WidgetTester t) => t.state(find.byKey(const ValueKey('l')));

    testWidgets('Deslizar: la línea nueva sube a su lugar', (t) async {
      await pump(t, active: false, anim: CarLyricAnim.slide);
      await pump(t, active: true, anim: CarLyricAnim.slide);
      await t.pump(const Duration(milliseconds: 40));
      final mid = t.widget<Transform>(find.descendant(of: find.byType(LyricLineView), matching: find.byType(Transform)));
      final dy = mid.transform.getTranslation().y;
      expect(dy, greaterThan(0));
      expect(dy, lessThanOrEqualTo(LyricLineView.slidePx));
      await t.pump(const Duration(milliseconds: 500));
      expect(state(t).t, 1);
      expect(find.descendant(of: find.byType(LyricLineView), matching: find.byType(Transform)), findsNothing);
      // Al salir no se desplaza (solo se apaga).
      await pump(t, active: false, anim: CarLyricAnim.slide);
      await t.pump(const Duration(milliseconds: 40));
      expect(find.descendant(of: find.byType(LyricLineView), matching: find.byType(Transform)), findsNothing);
      expect(state(t).t, inExclusiveRange(0, 1));
    });

    testWidgets('Escala: 0,94 → 1', (t) async {
      await pump(t, active: false, anim: CarLyricAnim.scale);
      Transform tf() =>
          t.widget<Transform>(find.descendant(of: find.byType(LyricLineView), matching: find.byType(Transform)));
      expect(tf().transform.storage[0], closeTo(LyricLineView.inactiveScale, 1e-6));
      await pump(t, active: true, anim: CarLyricAnim.scale);
      await t.pump(const Duration(milliseconds: 500));
      expect(tf().transform.storage[0], closeTo(1, 1e-6));
    });

    testWidgets('Desenfoque: activa nítida, inactiva desenfocada', (t) async {
      await pump(t, active: false, anim: CarLyricAnim.blur);
      expect(t.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isTrue);
      await pump(t, active: true, anim: CarLyricAnim.blur);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.widget<ImageFiltered>(find.byType(ImageFiltered)).enabled, isFalse);
    });

    testWidgets('sin duración (reducidas / Ninguna): cambio instantáneo', (t) async {
      await pump(t, active: false, anim: CarLyricAnim.none, d: Duration.zero);
      await pump(t, active: true, anim: CarLyricAnim.none, d: Duration.zero);
      expect(state(t).t, 1);
    });
  });

  testWidgets('Karaoke en el reproductor y la configuración de Letra no desbordan', (t) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = CarController(
      demo: true,
      custom: CarCustomizationStore(
        const CarCustomization().copyWith(lyrics: const CarLyricsOpts(anim: CarLyricAnim.karaoke)),
      ),
    );
    final tr = demoTracks.first;
    c.apply(TrackMessage(tr.info));
    c.apply(const StateMessage(playing: true, position: Duration(seconds: 13)));
    c.apply(LyricsMessage(id: tr.info.id, status: tr.lyricsStatus, synced: true, lines: tr.lyrics));
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: CarSettingsCategory.letra),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Animación al pasar de línea'), findsOneWidget);
    expect(find.text('Karaoke'), findsWidgets);
    // Cambiar el estilo desde la configuración.
    await t.ensureVisible(find.text('Escala').first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Escala').first);
    await t.pump(const Duration(milliseconds: 600));
    expect(c.cfg.lyrics.anim, CarLyricAnim.scale);
    await t.pump(const Duration(seconds: 3));
    await t.pumpWidget(const SizedBox());
    c.dispose();
    c.custom.dispose();
  });
}
