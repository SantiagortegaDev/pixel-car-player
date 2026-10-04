import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
import 'package:pixel_car_player/phone/widgets/hotspot_card.dart';
import 'package:pixel_car_player/phone/widgets/link_diagnostics_card.dart';
import 'package:pixel_car_player/setup/mode_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget w,
  Size size,
  Brightness brightness,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final scheme = AppTheme.schemeFromSeed(
    AppTheme.fallbackSeed,
    brightness: brightness,
  );
  await tester.pumpWidget(MaterialApp(theme: AppTheme.build(scheme), home: w));
  // Hay animaciones infinitas (formas que giran): nada de pumpAndSettle.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // Sin plataforma Android: PhoneRoot usa el estado demo (como en web).
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const sizes = [
    Size(412, 915),
    Size(1024, 600),
    Size(1280, 720),
    Size(2000, 1200),
  ];

  for (final brightness in Brightness.values) {
    for (final size in sizes) {
      final tag = '${brightness.name} ${size.width}x${size.height}';

      testWidgets('ModeSelectScreen $tag', (tester) async {
        AppMode? picked;
        await _pump(
          tester,
          ModeSelectScreen(onSelected: (m) => picked = m),
          size,
          brightness,
        );
        expect(find.text('Pixel Car Player'), findsOneWidget);
        expect(find.text('Pantalla del carro (tableta)'), findsOneWidget);
        expect(find.text('Transmisor (celular con Spotify)'), findsOneWidget);
        expect(find.text('Elegir'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.text('Transmisor (celular con Spotify)'),
        );
        await tester.pump();
        await tester.tap(find.text('Transmisor (celular con Spotify)'));
        expect(picked, AppMode.phone);
        await tester.ensureVisible(find.text('Elegir').first);
        await tester.pump();
        await tester.tap(find.text('Elegir').first);
        expect(picked, AppMode.car);
      });

      testWidgets(
        'PhoneRoot $tag',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
          var changed = false;
          await _pump(
            tester,
            PhoneRoot(
              onChangeMode: () => changed = true,
              now: () => DateTime(2026, 10, 3, 16),
            ),
            size,
            brightness,
          );
          // El tema sigue al sistema.
          final ctx = tester.element(find.text('Buenas tardes'));
          expect(Theme.of(ctx).brightness, brightness);

          expect(find.text('Pixel Car Player'), findsOneWidget);
          expect(find.text('Luces de Neón'), findsOneWidget);
          expect(find.text('Reproduciendo'), findsOneWidget);
          expect(find.text('Letras sincronizadas'), findsOneWidget);
          expect(find.text('Transmisor activo'), findsOneWidget);
          expect(find.text('Detener'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.scrollUntilVisible(
            find.text('Pantalla K24'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Pantalla K24'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Conexión.
          await tester.tap(find.text('Conexión'));
          await _settle(tester);
          expect(find.text('Cómo conectar'), findsOneWidget);
          expect(find.text('192.168.43.1:47321'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Hotspot del carro.
          await tester.scrollUntilVisible(
            find.text('Conectarme automáticamente'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Conectarme automáticamente'), findsOneWidget);
          expect(find.text('Sin Wi-Fi'), findsOneWidget);
          await tester.enterText(
            find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
            'Carro',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Contraseña'),
            'clave12345',
          );
          await tester.ensureVisible(find.text('Guardar'));
          await tester.pump();
          // Con las tarjetas nuevas queda pegado al borde de arriba: centrarlo.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 200),
          );
          await tester.pump();
          await tester.tap(find.text('Guardar'));
          await _settle(tester);
          final hp = await SharedPreferences.getInstance();
          expect(hp.getString('phone_car_hotspot_ssid'), 'Carro');
          expect(hp.getString('phone_car_hotspot_password'), 'clave12345');
          expect(hp.getBool('phone_car_hotspot_autoconnect'), isTrue);
          expect(find.textContaining('Guardado'), findsOneWidget);
          // El snackbar flotante tapa la barra inferior: esperar a que se vaya.
          await tester.pump(const Duration(seconds: 6));
          await _settle(tester);
          expect(tester.takeException(), isNull);

          // Ajustes: fuente de música y permisos.
          await tester.tap(find.text('Ajustes'));
          await _settle(tester);
          expect(find.text('Leer música de'), findsOneWidget);
          expect(find.text('YT Music'), findsOneWidget);
          expect(find.text('Permisos'), findsOneWidget);
          await tester.tap(find.text('YT Music'));
          await _settle(tester);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('phone_source'), 'youtubeMusic');
          await tester.tap(find.text('Iniciar automáticamente'));
          await _settle(tester);
          expect(prefs.getBool('phone_autostart'), isFalse);
          expect(tester.takeException(), isNull);

          // Menú de la píldora del inicio → Cambiar modo.
          await tester.tap(find.text('Inicio'));
          await _settle(tester);
          await tester.tap(find.byIcon(Symbols.more_vert_rounded));
          await _settle(tester);
          await tester.tap(find.text('Cambiar modo'));
          await _settle(tester);
          expect(changed, isTrue);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Conexión: hotspot + diagnóstico ${brightness.name} 412x915',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        await _pump(
          tester,
          PhoneRoot(onChangeMode: () {}, now: () => DateTime(2026, 10, 3, 16)),
          const Size(412, 915),
          brightness,
        );
        await tester.tap(find.text('Conexión'));
        await _settle(tester);
        await tester.scrollUntilVisible(
          find.text('IP del carro (opcional)'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('IP del carro (opcional)'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'IP del carro (opcional)'),
          '192.168.43.1',
        );
        await _settle(tester);
        expect(
          (await SharedPreferences.getInstance()).getString('phone_car_ip'),
          '192.168.43.1',
        );
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('Wi-Fi conectado'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Wi-Fi conectado'), findsOneWidget);
        expect(find.text('Transmisor activo'), findsWidgets);
        expect(find.text('Pantalla conectada'), findsOneWidget);
        expect(find.text('Enviando canción'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Copiar registro'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Actualizar'), findsOneWidget);
        expect(find.text('Borrar'), findsOneWidget);
        expect(find.text('Sin registro todavía.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4)); // refresco periódico
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'HotspotCard recarga y avisa con hotspotReceived',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final c = PhoneController();
      await tester.runAsync(c.init);
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                HotspotCard(c: c),
                LinkDiagnosticsCard(c: c),
              ],
            ),
          ),
        ),
        const Size(412, 1800),
        Brightness.light,
      );
      SharedPreferences.setMockInitialValues({
        'phone_car_hotspot_ssid': 'Tableta K24',
        'phone_car_hotspot_password': 'clave12345',
        'phone_car_hotspot_autoconnect': true,
      });
      await tester.runAsync(() => c.onHotspotReceived('Tableta K24'));
      await _settle(tester);
      expect(find.text('Recibido del carro'), findsOneWidget);
      expect(
        find.text(
          'La tableta compartió su hotspot «Tableta K24»: el celular se unirá solo',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
            )
            .controller!
            .text,
        'Tableta K24',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
