import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/car/widgets/disc.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Personalización de la pantalla del carro: modelo, guardado, aplicación en vivo y que
/// ninguna combinación desborde en los tamaños objetivo.
void main() {
  const sizes = [Size(1024, 600), Size(1280, 720), Size(1920, 720), Size(2000, 1200)];

  /// Una personalización con casi todo cambiado.
  final heavy = const CarCustomization().copyWith(
    design: const CarDesign(
      colorSource: CarColorSource.fixed,
      fixedColor: 0xFFE8743B,
      variant: SchemeVariant.vibrant,
      themeMode: CarThemeMode.light,
      uiScale: 1.3,
      titleScale: 1.6,
      controlHeight: 96,
      progressStyle: CarProgressStyle.plain,
      shapesCount: 30,
      shapesOpacity: 2.5,
    ),
    cover: const CarCoverOpts(shape: 'clover8', rotate: false, scale: 1.4, glow: true),
    visualizer: const CarVisualizerOpts(
      amplification: 3,
      bars: 96,
      thickness: 2.5,
      spacing: 40,
      roundCaps: false,
      color: CarVizColor.tertiary,
    ),
    lyrics: const CarLyricsOpts(scale: 1.8, spacing: 3, align: CarLyricsAlign.center, glow: false, offsetMs: -300),
    texts: const CarTexts().withText(CarText.headerPlayer, 'Sonando ahora').withText(CarText.tabQueue, ''),
    visibility: const CarVisibility().withElement(CarElement.album, false).withElement(CarElement.clock, true),
    connection: const CarConnectionOpts(transport: CarTransport.wifi, reconnectSeconds: 30, demoWhenIdle: true),
    startup: const CarStartupOpts(autostart: true, autostartDelay: 12, lockLandscape: true),
    gestures: const CarGestureOpts(tapCover: true, swipeCover: false),
  );

  group('modelo', () {
    test('ida y vuelta por JSON', () {
      final json = jsonEncode(heavy.toJson());
      final back = CarCustomization.fromJson(jsonDecode(json), shapes: CarCustomizationStore.shapeNames);
      expect(back, heavy);
      expect(back.text(CarText.headerPlayer), 'Sonando ahora');
      expect(back.text(CarText.tabQueue), '');
      expect(back.show(CarElement.album), isFalse);
      expect(back.show(CarElement.clock), isTrue);
      expect(back.visualizer.amplification, 3);
      expect(CarCustomization.decode(heavy.encode()), heavy);
    });

    test('lo que falta toma el valor por defecto', () {
      expect(CarCustomization.fromJson(null), CarCustomization.defaults);
      expect(CarCustomization.fromJson(const {}), CarCustomization.defaults);
      final partial = CarCustomization.fromJson({
        'design': {'uiScale': 1.2},
        'visualizer': {'amplification': 2.5},
        'futureSection': {'x': 1},
      });
      expect(partial.design.uiScale, 1.2);
      expect(partial.design.variant, SchemeVariant.tonalSpot);
      expect(partial.visualizer.amplification, 2.5);
      expect(partial.visualizer.bars, 44);
      expect(partial.cover, const CarCoverOpts());
      expect(partial.texts[CarText.noLyrics], 'No hay letra para este tema.');
    });

    test('valores inválidos se acotan o se ignoran', () {
      final v = CarCustomization.fromJson({
        'design': {'uiScale': 99, 'variant': 'nope', 'fixedColor': '#abc', 'themeMode': 3},
        'visualizer': {'amplification': -4, 'bars': 33, 'color': 'magenta'},
        'cover': {'shape': 'hexagonote'},
        'visibility': {'title': false, 'noExiste': false, 'album': 'sí'},
        'texts': {'idleTitle': 'Hola', 'otra': 'x', 'noLyrics': 7},
        'startup': {'autostartDelay': 1e9},
      }, shapes: CarCustomizationStore.shapeNames);
      expect(v.design.uiScale, CarDesign.uiScaleRange.max);
      expect(v.design.variant, SchemeVariant.tonalSpot);
      expect(v.design.fixedColor, 0xFFAABBCC);
      expect(v.design.themeMode, CarThemeMode.dark);
      expect(v.visualizer.amplification, CarVisualizerOpts.amplificationRange.min);
      expect(v.visualizer.bars.isEven, isTrue);
      expect(v.visualizer.color, CarVizColor.primary);
      expect(v.cover.shape, 'cookie9');
      expect(v.show(CarElement.title), isFalse);
      expect(v.show(CarElement.album), isTrue);
      expect(v.text(CarText.idleTitle), 'Hola');
      expect(v.text(CarText.noLyrics), CarText.noLyrics.defaultText);
      expect(v.startup.autostartDelay, CarStartupOpts.delayRange.max);
      expect(() => CarCustomization.decode('[1,2]'), throwsFormatException);
      expect(() => CarCustomization.decode('no es json'), throwsFormatException);
    });

    test('restablecer por sección y todo', () {
      final r = heavy.resetSection(CarSection.visualizer);
      expect(r.visualizer, const CarVisualizerOpts());
      expect(r.design, heavy.design);
      expect(r.isDefault(CarSection.visualizer), isTrue);
      expect(r.isDefault(CarSection.design), isFalse);
      final store = CarCustomizationStore(heavy);
      store.resetSections(const [CarSection.texts, CarSection.visibility]);
      expect(store.value.texts, const CarTexts());
      expect(store.value.visibility, const CarVisibility());
      expect(store.value.cover, heavy.cover);
      store.resetAll();
      expect(store.value, CarCustomization.defaults);
      store.import(heavy.encode());
      expect(store.value, heavy);
      expect(() => store.import('{'), throwsFormatException);
      store.dispose();
    });

    test('textos y visibilidad: solo se guarda lo distinto', () {
      final t = const CarTexts().withText(CarText.tabLyrics, 'Letra');
      expect(t.customCount, 0);
      expect(t.toJson(), isEmpty);
      final vis = const CarVisibility().withElement(CarElement.title, true).withElement(CarElement.clock, false);
      expect(vis.toJson(), isEmpty);
      expect(const CarVisibility().withAll(false).hiddenCount, CarElement.values.length);
    });

    test('colores hex', () {
      expect(colorHex(0xFF3F6D8E), '#3F6D8E');
      expect(parseColorHex('3f6d8e'), 0xFF3F6D8E);
      expect(parseColorHex('#FF3F6D8E'), 0xFF3F6D8E);
      expect(parseColorHex('#12'), isNull);
    });

    test('variantes de esquema', () {
      const seed = Color(0xFF3F6D8E);
      final tonal = AppTheme.schemeFromSeed(seed);
      expect(AppTheme.schemeFromSeed(seed, variant: SchemeVariant.tonalSpot), tonal);
      for (final v in SchemeVariant.values.skip(1)) {
        expect(AppTheme.schemeFromSeed(seed, variant: v).primary, isNot(tonal.primary), reason: '$v');
      }
      expect(AppTheme.schemeFromSeed(seed, brightness: Brightness.light).brightness, Brightness.light);
    });

    test('geometría del disco: valores de fábrica = Harmonix; amplificada cabe', () {
      const s = 460.0;
      final def = DiscGeometry.of(s, const CarVisualizerOpts());
      expect(def.coverR * 2, (s * 0.62).roundToDouble());
      expect(def.magnitude, closeTo(s * 0.11, 0.01));
      final big = DiscGeometry.of(s, const CarVisualizerOpts(amplification: 2.5));
      expect(big.magnitude, greaterThan(def.magnitude * 2));
      expect(big.coverR, lessThan(def.coverR));
      expect(big.coverR + big.spacing + big.stroke + big.magnitude, lessThanOrEqualTo(s / 2 + s * 0.06 + 0.01));
    });
  });

  group('guardado', () {
    test('JSON + claves del inicio automático aparte', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CarCustomizationStore(CarCustomization.defaults, true);
      store.update((v) => v.copyWith(startup: const CarStartupOpts(autostart: true, autostartDelay: 7)));
      await store.flush();
      final p = await SharedPreferences.getInstance();
      expect(p.getBool(CarPrefs.kAutostart), isTrue);
      expect(p.getInt(CarPrefs.kAutostartDelay), 7);
      expect(p.getBool('car_autostart'), isTrue);
      expect(p.getInt('car_autostart_delay'), 7);
      final saved = jsonDecode(p.getString(CarCustomizationStore.key)!) as Map;
      expect((saved['startup'] as Map)['autostart'], isTrue);
      store.dispose();

      // Al cargar mandan las claves sueltas.
      await p.setBool(CarPrefs.kAutostart, false);
      final loaded = await CarCustomizationStore.load();
      expect(loaded.value.startup.autostart, isFalse);
      expect(loaded.value.startup.autostartDelay, 7);
      loaded.dispose();
    });

    test('JSON roto = valores por defecto', () async {
      SharedPreferences.setMockInitialValues({CarCustomizationStore.key: '{roto'});
      final s = await CarCustomizationStore.load();
      expect(s.value, CarCustomization.defaults);
      s.dispose();
    });
  });

  group('controlador', () {
    test('color fijo, variante y modo cambian el esquema', () {
      final store = CarCustomizationStore();
      final c = CarController(custom: store);
      expect(c.scheme, CarController.fallbackScheme);
      store.update(
        (v) => v.copyWith(design: v.design.copyWith(colorSource: CarColorSource.fixed, fixedColor: 0xFFB3261E)),
      );
      expect(c.seed, const Color(0xFFB3261E));
      expect(c.scheme, AppTheme.schemeFromSeed(const Color(0xFFB3261E)));
      store.update((v) => v.copyWith(design: v.design.copyWith(themeMode: CarThemeMode.light)));
      expect(c.scheme.brightness, Brightness.light);
      store.update((v) => v.copyWith(design: v.design.copyWith(themeMode: CarThemeMode.auto)));
      expect(c.schemeFor(Brightness.dark).brightness, Brightness.dark);
      expect(c.schemeFor(Brightness.light).brightness, Brightness.light);
      store.update((v) => v.copyWith(lyrics: v.lyrics.copyWith(offsetMs: 900)));
      expect(c.lyricLead, const Duration(milliseconds: 900));
      c.dispose();
      store.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Pantalla

  Future<void> pumpScreen(
    WidgetTester tester,
    Size size,
    CarController c, {
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
          child: CarPlayerScreen(onSettings: onSettings ?? (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  CarController demoController(CarCustomization cfg, {int track = 0}) {
    final c = CarController(demo: true, custom: CarCustomizationStore(cfg));
    final t = demoTracks[track];
    c.apply(TrackMessage(t.info));
    c.apply(const StateMessage(playing: true, position: Duration(seconds: 45)));
    c.apply(LyricsMessage(id: t.info.id, status: t.lyricsStatus, synced: t.synced, lines: t.lyrics));
    c.apply(const QueueMessage(demoQueueExtras));
    return c;
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

  final layouts = <String, CarCustomization>{
    'todo oculto': const CarCustomization().copyWith(visibility: const CarVisibility().withAll(false)),
    'sin panel lateral': const CarCustomization().copyWith(visibility: hide([CarElement.sidePanel])),
    'sin portada': const CarCustomization().copyWith(visibility: hide([CarElement.cover])),
    'solo portada': const CarCustomization().copyWith(
      visibility: const CarVisibility().withAll(false).withElement(CarElement.cover, true),
    ),
    'solo letra': const CarCustomization().copyWith(
      visibility: const CarVisibility()
          .withAll(false)
          .withElement(CarElement.sidePanel, true)
          .withElement(CarElement.lyricsTab, true),
    ),
    'sin portada ni panel': const CarCustomization().copyWith(
      visibility: hide([CarElement.cover, CarElement.sidePanel]),
    ),
    'sin detalles': const CarCustomization().copyWith(
      visibility: hide([
        CarElement.title,
        CarElement.artist,
        CarElement.album,
        CarElement.progress,
        CarElement.shuffle,
        CarElement.previous,
        CarElement.playPause,
        CarElement.next,
        CarElement.repeat,
        CarElement.chips,
      ]),
    ),
    'muy personalizada': heavy,
    'mínimos': const CarCustomization().copyWith(
      design: const CarDesign(uiScale: 0.8, titleScale: 0.7, controlHeight: 48, shapesCount: 0),
      cover: const CarCoverOpts(scale: 0.6),
      visualizer: const CarVisualizerOpts(amplification: 0.25, bars: 16, thickness: 0.4, spacing: 0),
      lyrics: const CarLyricsOpts(scale: 0.7, spacing: 0.5),
    ),
  };

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    for (final e in layouts.entries) {
      testWidgets('reproductor ${e.key} $label', (tester) async {
        final c = demoController(e.value);
        await pumpScreen(tester, size, c);
        final cfg = e.value;
        expect(find.text(demoTracks.first.info.title), cfg.show(CarElement.title) ? findsOneWidget : findsNothing);
        expect(find.byType(Disc), cfg.show(CarElement.cover) ? findsOneWidget : findsNothing);
        if (!cfg.show(CarElement.sidePanel)) expect(find.text('Se enciende la ciudad cuando cae el sol'), findsNothing);
        if (!cfg.show(CarElement.album)) expect(find.text(demoTracks.first.info.album), findsNothing);
        await finish(tester, c);
      });
    }

    testWidgets('letra completa sin nada más $label', (tester) async {
      final c = demoController(
        const CarCustomization().copyWith(
          visibility: const CarVisibility().withAll(false),
          startup: const CarStartupOpts(startLyricsFullscreen: true),
        ),
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<CarController>.value(
            value: c,
            child: CarPlayerScreen(onSettings: (_) {}, initialLyricsFullscreen: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      // El botón para volver siempre está.
      expect(find.byTooltip('Volver al reproductor'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('espera personalizada $label', (tester) async {
      final store = CarCustomizationStore(
        const CarCustomization().copyWith(
          texts: const CarTexts().withText(CarText.idleTitle, 'Hola, Santi').withText(CarText.idleDemoButton, ''),
          visibility: hide([CarElement.idleSteps]),
        ),
      );
      final c = CarController(custom: store);
      await pumpScreen(tester, size, c);
      expect(find.text('Hola, Santi'), findsOneWidget);
      expect(find.text('Ver demo'), findsNothing);
      expect(find.text('Cómo conectar'), findsNothing);
      expect(find.text('IP de esta tableta'), findsOneWidget);
      await finish(tester, c);
    });

    for (final cat in CarSettingsCategory.values) {
      testWidgets('configuración ${cat.name} $label', (tester) async {
        final c = demoController(cat == CarSettingsCategory.portada ? heavy : const CarCustomization());
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: cat),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(cat.label), findsWidgets);
        // Recorre la página hasta abajo para construir y medir todo.
        final scroll = find.byKey(PageStorageKey('settings-${cat.name}'));
        for (var i = 0; i < 20; i++) {
          await tester.drag(scroll, const Offset(0, -500), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(seconds: 1));
        await finish(tester, c);
      });
    }
  }

  testWidgets('los cambios se ven en vivo', (tester) async {
    final c = demoController(const CarCustomization());
    await pumpScreen(tester, const Size(1280, 720), c);
    expect(find.text('Reproduciendo'), findsOneWidget);
    expect(find.text(demoTracks.first.info.album), findsOneWidget);
    c.custom.update(
      (v) => v.copyWith(
        texts: v.texts.withText(CarText.headerPlayer, 'En el carro'),
        visibility: v.visibility.withElement(CarElement.album, false).withElement(CarElement.settingsButton, false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Reproduciendo'), findsNothing);
    expect(find.text('En el carro'), findsOneWidget);
    expect(find.text(demoTracks.first.info.album), findsNothing);
    expect(find.byTooltip('Ajustes'), findsNothing);
    c.custom.update((v) => v.copyWith(texts: v.texts.withText(CarText.headerPlayer, '')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('En el carro'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('mantener presionado el fondo abre Configuración', (tester) async {
    final c = demoController(
      const CarCustomization().copyWith(visibility: hide([CarElement.settingsButton, CarElement.statusChip])),
    );
    var opened = 0;
    await pumpScreen(tester, const Size(1280, 720), c, onSettings: (_) => opened++);
    expect(find.byTooltip('Ajustes'), findsNothing);
    await tester.longPressAt(const Offset(640, 700));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, 1);
    await finish(tester, c);
  });

  testWidgets('elementos visibles: el switch oculta en vivo', (tester) async {
    final c = demoController(const CarCustomization());
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: CarSettingsCategory.visibles),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(c.cfg.show(CarElement.header), isTrue);
    await tester.tap(find.byKey(const ValueKey('vis-header')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.cfg.show(CarElement.header), isFalse);
    // Restablecer la categoría.
    await tester.tap(find.text('Restablecer').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.cfg.show(CarElement.header), isTrue);
    await finish(tester, c);
  });

  testWidgets('textos: editar y vaciar', (tester) async {
    final c = demoController(const CarCustomization());
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CarSettingsPage(controller: c, onChangeMode: () {}, initial: CarSettingsCategory.textos),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const ValueKey('text-headerPlayer')), 'Ahora');
    await tester.pump();
    expect(c.cfg.text(CarText.headerPlayer), 'Ahora');
    await tester.enterText(find.byKey(const ValueKey('text-headerPlayer')), '');
    await tester.pump();
    expect(c.cfg.text(CarText.headerPlayer), '');
    expect(find.text('Oculto'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('diseño: color fijo desde las muestras', (tester) async {
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
    await tester.ensureVisible(find.text('Fijo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Fijo'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.cfg.design.colorSource, CarColorSource.fixed);
    await tester.ensureVisible(find.bySemanticsLabel('Color #B3261E'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Color #B3261E'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.cfg.design.fixedColor, 0xFFB3261E);
    expect(c.seed, const Color(0xFFB3261E));
    await finish(tester, c);
  });
}
