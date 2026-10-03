import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/audio/car_audio_levels.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/car/settings/settings_system.dart';
import 'package:pixel_car_player/car/system/car_hotspot.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Animaciones, visualizador con el audio real, hotspot, app acompañante y la alineación
/// de la columna de detalles cuando se oculta el panel lateral.
void main() {
  const sizes = [Size(1024, 600), Size(1280, 720), Size(1920, 720), Size(2000, 1200)];

  group('modelo: campos nuevos', () {
    test('valores por defecto', () {
      const d = CarCustomization.defaults;
      expect(d.design.motion, CarMotion.system);
      expect(d.visualizer.source, CarVizSource.auto);
      expect(d.visualizer.wantsRealAudio, isTrue);
      expect(d.visualizer.sensitivity, 1.0);
      expect(d.visualizer.animateAlways, isFalse);
      expect(d.hotspot, const CarHotspotOpts());
      expect(d.hotspot.autoEnable, isFalse);
      expect(d.hotspot.recheckMinutes, 0);
      expect(d.hotspot.ssid, '');
      expect(d.startup.companionEnabled, isFalse);
      expect(d.startup.companionPackage, '');
      expect(d.startup.companionDelayMs, 1500);
      expect(d.startup.companionToLaunch, '');
    });

    test('JSON viejo (sin los campos nuevos) = valores por defecto', () {
      final old = CarCustomization.fromJson({
        'v': 1,
        'design': {'uiScale': 1.1},
        'visualizer': {'bars': 40},
        'startup': {'autostart': true},
      });
      expect(old.design.uiScale, 1.1);
      expect(old.design.motion, CarMotion.system);
      expect(old.visualizer.bars, 40);
      expect(old.visualizer.source, CarVizSource.auto);
      expect(old.visualizer.animateAlways, isFalse);
      expect(old.startup.autostart, isTrue);
      expect(old.startup.companionDelayMs, 1500);
      expect(old.hotspot, const CarHotspotOpts());
    });

    test('ida y vuelta e inválidos', () {
      final v = const CarCustomization().copyWith(
        design: const CarDesign(motion: CarMotion.reduced),
        visualizer: const CarVisualizerOpts(source: CarVizSource.real, sensitivity: 2.5, animateAlways: true),
        hotspot: const CarHotspotOpts(autoEnable: true, recheckMinutes: 15, ssid: 'Mi carro', password: 'clave;1234'),
        startup: const CarStartupOpts(
          companionEnabled: true,
          companionPackage: 'com.syu.bt',
          companionLabel: 'Música BT',
          companionDelayMs: 2500,
        ),
      );
      final back = CarCustomization.fromJson(jsonDecode(jsonEncode(v.toJson())));
      expect(back, v);
      expect(back.startup.companionToLaunch, 'com.syu.bt');
      expect(back.resetSection(CarSection.hotspot).hotspot, const CarHotspotOpts());
      expect(back.isDefault(CarSection.hotspot), isFalse);

      final bad = CarCustomization.fromJson({
        'design': {'motion': 'rapido'},
        'visualizer': {'source': 'mic', 'sensitivity': 99, 'animateAlways': 'sí'},
        'hotspot': {'recheckMinutes': -5, 'ssid': 42, 'password': 'x' * 500},
        'startup': {'companionDelayMs': 1e9, 'companionPackage': 7},
      });
      expect(bad.design.motion, CarMotion.system);
      expect(bad.visualizer.source, CarVizSource.auto);
      expect(bad.visualizer.sensitivity, CarVisualizerOpts.sensitivityRange.max);
      expect(bad.visualizer.animateAlways, isFalse);
      expect(bad.hotspot.recheckMinutes, 0);
      expect(bad.hotspot.ssid, '');
      expect(bad.hotspot.password.length, 128);
      expect(bad.startup.companionDelayMs, CarStartupOpts.companionDelayRange.max);
      expect(bad.startup.companionPackage, '');
    });

    test('QR Wi-Fi con escapes', () {
      expect(wifiQrData('Mi carro', 'clave1234'), 'WIFI:T:WPA;S:Mi carro;P:clave1234;;');
      expect(wifiQrData(r'a;b,c:d"e\f', r'p;w'), r'WIFI:T:WPA;S:a\;b\,c\:d\"e\\f;P:p\;w;;');
      expect(wifiQrData('Abierta', ''), 'WIFI:T:nopass;S:Abierta;;');
    });
  });

  group('guardado de la app acompañante', () {
    test('claves sueltas para el BootReceiver', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CarCustomizationStore(CarCustomization.defaults, true);
      store.update(
        (v) => v.copyWith(
          startup: v.startup.copyWith(companionEnabled: true, companionPackage: 'com.syu.bt', companionDelayMs: 3000),
        ),
      );
      await store.flush();
      final p = await SharedPreferences.getInstance();
      expect(p.getString(CarPrefs.kCompanionPackage), 'com.syu.bt');
      expect(p.getString('car_companion_package'), 'com.syu.bt');
      expect(p.getInt('car_companion_delay'), 3000);

      // Apagada: la clave queda vacía pero se recuerda la app elegida.
      store.update((v) => v.copyWith(startup: v.startup.copyWith(companionEnabled: false)));
      await store.flush();
      expect(p.getString('car_companion_package'), '');
      store.dispose();
      final loaded = await CarCustomizationStore.load();
      expect(loaded.value.startup.companionEnabled, isFalse);
      expect(loaded.value.startup.companionPackage, 'com.syu.bt');
      loaded.dispose();

      // Mandan las claves sueltas (las puede tocar otra versión).
      await p.setString('car_companion_package', 'com.android.fmradio');
      await p.setInt('car_companion_delay', 500);
      final again = await CarCustomizationStore.load();
      expect(again.value.startup.companionEnabled, isTrue);
      expect(again.value.startup.companionPackage, 'com.android.fmradio');
      expect(again.value.startup.companionDelayMs, 500);
      again.dispose();
    });
  });

  group('audio real', () {
    test('64 bandas → barras: graves arriba, promedios por tramo', () {
      final b = Float32List(64);
      for (var i = 0; i < 64; i++) {
        b[i] = i < 8 ? 1 : 0; // solo graves
      }
      // 22 barras por lado (44 en total): la primera barra toma las bandas 0..1.
      expect(CarAudioLevels.mapBands(b, 0, 22), closeTo(0.9, 1e-6));
      expect(CarAudioLevels.mapBands(b, 21, 22), 0);
      // Más barras que bandas: cada barra toma la banda más cercana.
      expect(CarAudioLevels.mapBands(b, 0, 96), closeTo(0.9, 1e-6));
      expect(CarAudioLevels.mapBands(b, 95, 96), 0);
      // Sensibilidad: ganancia antes de la curva.
      final half = Float32List(64)..fillRange(0, 64, 0.25);
      final base = CarAudioLevels.mapBands(half, 3, 22);
      expect(CarAudioLevels.mapBands(half, 3, 22, sensitivity: 2), greaterThan(base));
      expect(CarAudioLevels.mapBands(half, 3, 22, sensitivity: 4), closeTo(0.9, 1e-6));
      // Fuera de rango.
      expect(CarAudioLevels.mapBands(b, 22, 22), 0);
    });

    test('detección con histéresis', () {
      var now = DateTime(2026);
      final a = CarAudioLevels(clock: () => now);
      final loud = List<double>.filled(64, 0.6);
      expect(a.detected.value, isFalse);
      a.onEvent({'type': 'fft', 'bands': loud, 'rms': 0.3});
      expect(a.detected.value, isTrue);
      expect(a.live, isTrue);
      expect(a.level(0, 22), greaterThan(0));
      // Silencio corto: se mantiene.
      now = now.add(const Duration(milliseconds: 500));
      a.onFrame(List<double>.filled(64, 0), 0.001);
      expect(a.detected.value, isTrue);
      // Silencio largo: se apaga.
      now = now.add(const Duration(seconds: 2));
      a.onFrame(List<double>.filled(64, 0), 0.001);
      expect(a.detected.value, isFalse);
      // Datos raros no rompen nada.
      a.onEvent({'type': 'fft', 'bands': 'x', 'rms': 'y'});
      expect(a.detected.value, isFalse);
      a.onFrame([double.nan, 2, -1, 'z'], double.infinity);
      expect(a.bands[0], 0);
      expect(a.bands[1], 1);
      expect(a.bands[2], 0);
      a.reset();
      expect(a.live, isFalse);
      a.dispose();
    });

    test('el controlador anima con audio detectado aunque no llegue "playing"', () {
      final store = CarCustomizationStore();
      final c = CarController(demo: true, custom: store);
      final t = demoTracks.first;
      c.apply(TrackMessage(t.info));
      c.apply(const StateMessage(playing: false, position: Duration.zero));
      expect(c.visualActive, isFalse);
      expect(c.useRealAudio, isFalse);

      c.audio.onFrame(List<double>.filled(64, 0.5), 0.4);
      expect(c.audioDetected, isTrue);
      expect(c.visualActive, isTrue);
      expect(c.useRealAudio, isTrue);

      // Simulado: ignora el audio real.
      store.update((v) => v.copyWith(visualizer: v.visualizer.copyWith(source: CarVizSource.simulated)));
      expect(c.audioDetected, isFalse);
      expect(c.visualActive, isFalse);
      expect(c.useRealAudio, isFalse);

      // "Animar siempre".
      store.update((v) => v.copyWith(visualizer: v.visualizer.copyWith(animateAlways: true)));
      expect(c.visualActive, isTrue);

      // Solo audio real: siempre del audio (aunque esté en silencio).
      store.update((v) => v.copyWith(visualizer: v.visualizer.copyWith(source: CarVizSource.real)));
      expect(c.useRealAudio, isTrue);
      c.dispose();
      store.dispose();
    });
  });

  group('hotspot', () {
    test('verificar y encender', () async {
      final api = _FakeHotspotApi({'enabled': true, 'ssid': 'Carro', 'method': 'tethering', 'canWriteSettings': true});
      final h = CarHotspot(api: api);
      expect(await h.ensureOn(), isTrue);
      expect(api.setCalls, isEmpty);
      expect(h.info.enabled, isTrue);
      expect(h.info.ssid, 'Carro');

      api.state = {'enabled': false, 'canWriteSettings': true};
      api.onSet = (on) => {'ok': true, 'method': 'tethering', 'needsSettings': false};
      expect(await h.ensureOn(), isTrue);
      expect(api.setCalls, [true]);
      expect(h.prompt.value, isNull);

      api.state = {'enabled': false, 'canWriteSettings': false};
      api.onSet = (on) => {'ok': false, 'method': 'none', 'needsSettings': true, 'error': 'systemPathsFailed'};
      expect(await h.ensureOn(), isFalse);
      expect(h.prompt.value, isNotNull);
      expect(h.prompt.value!.canWriteSettings, isFalse);
      expect(h.prompt.value!.error, 'systemPathsFailed');
      expect(hotspotErrorText('locationOff'), contains('ubicación'));
      h.dispose();
    });

    test('sin sistema no hace nada', () async {
      final api = _FakeHotspotApi({}, supported: false);
      final h = CarHotspot(api: api);
      expect(await h.ensureOn(), isFalse);
      expect(api.setCalls, isEmpty);
      expect(h.prompt.value, isNull);
      h.dispose();
    });
  });

  test('apps lanzables', () {
    final a = LaunchableApp.fromMap({'package': 'com.syu.bt', 'label': 'Música Bluetooth'})!;
    expect(a.matches('blue'), isTrue);
    expect(a.matches('SYU'), isTrue);
    expect(a.matches('maps'), isFalse);
    expect(LaunchableApp.fromMap({'label': 'x'}), isNull);
    expect(LaunchableApp.fromMap({'package': 'p'})!.label, 'p');
  });

  // ---------------------------------------------------------------------------
  // Pantalla

  CarController demoController(CarCustomization cfg) {
    final c = CarController(demo: true, custom: CarCustomizationStore(cfg));
    final t = demoTracks.first;
    c.apply(TrackMessage(t.info));
    c.apply(const StateMessage(playing: true, position: Duration(seconds: 45)));
    c.apply(LyricsMessage(id: t.info.id, status: t.lyricsStatus, synced: t.synced, lines: t.lyrics));
    c.apply(const QueueMessage(demoQueueExtras));
    return c;
  }

  Future<void> pumpScreen(WidgetTester tester, Size size, CarController c) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ChangeNotifierProvider<CarController>.value(
          value: c,
          child: CarPlayerScreen(onSettings: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> finish(WidgetTester tester, CarController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    c.custom.dispose();
  }

  CarVisibility hide(Iterable<CarElement> els) {
    var v = const CarVisibility();
    for (final e in els) {
      v = v.withElement(e, false);
    }
    return v;
  }

  final combos = <String, CarVisibility>{
    'completo': const CarVisibility(),
    'sin panel lateral': hide([CarElement.sidePanel]),
    'sin letra ni cola': hide([CarElement.lyricsTab, CarElement.queueTab]),
    'sin portada': hide([CarElement.cover]),
    'sin portada ni panel': hide([CarElement.cover, CarElement.sidePanel]),
    'sin panel ni tiempos': hide([CarElement.sidePanel, CarElement.times]),
    'sin panel ni chips': hide([CarElement.sidePanel, CarElement.chips]),
    'sin panel, sin aleatorio ni repetir': hide([CarElement.sidePanel, CarElement.shuffle, CarElement.repeat]),
  };

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';
    for (final e in combos.entries) {
      testWidgets('detalles alineados (${e.key}) $label', (tester) async {
        final c = demoController(const CarCustomization().copyWith(visibility: e.value));
        await pumpScreen(tester, size, c);
        final title = tester.getRect(find.text(demoTracks.first.info.title));
        final titles = tester.getRect(find.byKey(const ValueKey('car-titles')));
        final progress = tester.getRect(find.byKey(const ValueKey('car-progress')));
        final controls = tester.getRect(find.byKey(const ValueKey('car-controls')));
        final details = tester.getRect(find.byKey(const ValueKey('car-details')));
        final chips = find.byKey(const ValueKey('car-chips'));
        // Mismo borde izquierdo para todo el bloque…
        expect(progress.left, closeTo(title.left, 0.5), reason: 'barra vs título');
        expect(controls.left, closeTo(title.left, 0.5), reason: 'botones vs título');
        expect(titles.left, closeTo(title.left, 0.5));
        if (chips.evaluate().isNotEmpty) expect(tester.getRect(chips).left, closeTo(title.left, 0.5));
        // …y la barra de progreso termina donde terminan los botones (no se va a la derecha).
        expect(progress.right, closeTo(controls.right, 0.5), reason: 'barra vs botones (derecha)');
        expect(progress.left, closeTo(details.left, 0.5));
        expect(progress.right, lessThanOrEqualTo(details.right + 0.5));
        // Sin panel lateral, portada + detalles quedan centrados en la pantalla.
        if (!e.value[CarElement.sidePanel] || (!e.value[CarElement.lyricsTab] && !e.value[CarElement.queueTab])) {
          final w = size.width;
          if (e.value[CarElement.cover]) {
            final disc = tester.getRect(find.byKey(const ValueKey('car-cover-column')));
            expect(disc.left, closeTo(w - details.right, 1.5), reason: 'bloque centrado');
            expect(details.width, lessThanOrEqualTo(StageLayout.detailsMax * carScaleFor(size) + 0.5));
          } else {
            expect(details.center.dx, closeTo(w / 2, 1.5), reason: 'detalles centrados');
          }
        }
        await finish(tester, c);
      });
    }
  }

  test('StageLayout: sin panel los detalles no pasan del ancho de Harmonix', () {
    for (final s in sizes) {
      final k = carScaleFor(s);
      final v = Size(s.width / k, s.height / k);
      expect(StageLayout.of(v, side: false).details, lessThanOrEqualTo(StageLayout.detailsMax));
      expect(StageLayout.of(v, cover: false).details, lessThanOrEqualTo(StageLayout.detailsMax));
      expect(StageLayout.of(v, side: false, cover: false).details, lessThanOrEqualTo(StageLayout.detailsMax));
      // Con botones muy altos la columna crece para que quepan sin achicarse.
      expect(StageLayout.detailsMaxFor(96), greaterThan(StageLayout.detailsMax));
    }
  });

  group('animaciones', () {
    testWidgets('Sistema sigue a «quitar animaciones»; Completas/Reducidas mandan', (tester) async {
      late BuildContext ctx;
      Future<void> pump(CarMotion m, {bool disable = false}) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: disable),
            child: CarCustomScope(
              value: CarCustomization(design: CarDesign(motion: m)),
              child: Builder(
                builder: (c) {
                  ctx = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      }

      await pump(CarMotion.system);
      expect(carReducedMotion(ctx), isFalse);
      await pump(CarMotion.system, disable: true);
      expect(carReducedMotion(ctx), isTrue);
      await pump(CarMotion.full, disable: true);
      expect(carReducedMotion(ctx), isFalse);
      await pump(CarMotion.reduced);
      expect(carReducedMotion(ctx), isTrue);
    });

    for (final m in [CarMotion.full, CarMotion.reduced]) {
      testWidgets('reproductor con animaciones ${m.name}', (tester) async {
        final c = demoController(CarCustomization(design: CarDesign(motion: m)));
        await pumpScreen(tester, const Size(1280, 720), c);
        // Sin text-in: los textos no quedan dentro de un Opacity animado.
        final fades = find.descendant(of: find.byType(HxTextIn), matching: find.byType(Opacity));
        expect(fades, m == CarMotion.reduced ? findsNothing : findsWidgets);
        // Cambio de color instantáneo.
        c.custom.update(
          (v) => v.copyWith(design: v.design.copyWith(colorSource: CarColorSource.fixed, fixedColor: 0xFFB3261E)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final bg = tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
        final want = AppTheme.schemeFromSeed(const Color(0xFFB3261E)).surface;
        if (m == CarMotion.reduced) {
          expect(bg, want);
        } else {
          expect(bg, isNot(want));
        }
        await tester.pump(const Duration(seconds: 2));
        await finish(tester, c);
      });
    }

    testWidgets('el selector de Diseño cambia el ajuste', (tester) async {
      final c = demoController(const CarCustomization());
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: CarSettingsCategory.diseno),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Animaciones'), findsWidgets);
      await tester.tap(find.text('Reducidas'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.design.motion, CarMotion.reduced);
      expect(find.text('Ahora: reducidas'), findsOneWidget);
      await tester.tap(find.text('Completas'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.design.motion, CarMotion.full);
      await finish(tester, c);
    });
  });

  group('configuración nueva', () {
    Future<CarController> pumpSettings(WidgetTester tester, CarSettingsCategory cat, CarCustomization cfg) async {
      final c = demoController(cfg);
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: cat),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return c;
    }

    testWidgets('hotspot: QR con la red guardada', (tester) async {
      final c = await pumpSettings(
        tester,
        CarSettingsCategory.hotspot,
        const CarCustomization(
          hotspot: CarHotspotOpts(ssid: 'Mi carro', password: 'clave1234'),
        ),
      );
      expect(find.text('Verificar y encender el hotspot al iniciar'), findsOneWidget);
      expect(find.text('Encender ahora'), findsOneWidget);
      expect(find.text('Hotspot del carro'), findsOneWidget);
      await tester.ensureVisible(find.byType(QrImageView));
      expect(find.byType(QrImageView), findsOneWidget);
      // Activar la verificación muestra el intervalo.
      await tester.ensureVisible(find.text('Verificar y encender el hotspot al iniciar'));
      await tester.tap(find.text('Verificar y encender el hotspot al iniciar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.hotspot.autoEnable, isTrue);
      expect(find.text('Volver a verificar cada'), findsOneWidget);
      // Editar la red.
      await tester.enterText(find.byKey(const ValueKey('hotspot-ssid')), 'Carro 2');
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.hotspot.ssid, 'Carro 2');
      await tester.pump(const Duration(seconds: 4));
      await finish(tester, c);
    });

    testWidgets('inicio: app acompañante', (tester) async {
      final c = await pumpSettings(tester, CarSettingsCategory.inicio, const CarCustomization());
      expect(find.text('App acompañante'), findsOneWidget);
      final sw = find.text('Abrir la app acompañante al iniciar Pixel Car Player (en segundo plano)');
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pump(const Duration(milliseconds: 500));
      // Sin app elegida no se enciende.
      expect(c.cfg.startup.companionEnabled, isFalse);
      c.custom.update(
        (v) => v.copyWith(
          startup: v.startup.copyWith(companionPackage: 'com.syu.bt', companionLabel: 'Música Bluetooth'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(sw);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.startup.companionEnabled, isTrue);
      expect(c.cfg.startup.companionToLaunch, 'com.syu.bt');
      expect(find.text('Música Bluetooth'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await finish(tester, c);
    });

    testWidgets('portada: origen de las barras y animar siempre', (tester) async {
      final c = await pumpSettings(tester, CarSettingsCategory.portada, const CarCustomization());
      final sim = find.text('Simulado');
      await tester.ensureVisible(sim);
      expect(find.text('Permiso de audio'), findsOneWidget);
      await tester.tap(sim);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.visualizer.source, CarVizSource.simulated);
      expect(find.text('Permiso de audio'), findsNothing);
      final always = find.text('Animar siempre');
      await tester.ensureVisible(always);
      await tester.tap(always);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.cfg.visualizer.animateAlways, isTrue);
      await tester.pump(const Duration(seconds: 4));
      await finish(tester, c);
    });
  });
}

class _FakeHotspotApi implements HotspotApi {
  _FakeHotspotApi(this.state, {this.supported = true});
  Map<String, dynamic> state;
  @override
  final bool supported;
  final setCalls = <bool>[];
  Map<String, dynamic> Function(bool on) onSet = (_) => {'ok': true, 'method': 'none'};

  @override
  Future<Map<String, dynamic>> getState() async => state;

  @override
  Future<Map<String, dynamic>> setEnabled(bool enabled) async {
    setCalls.add(enabled);
    return onSet(enabled);
  }
}
